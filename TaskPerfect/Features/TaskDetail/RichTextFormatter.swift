import UIKit

/// Converts between `TPBody` and `NSAttributedString`, and applies formatting
/// commands to a `UITextView`.
///
/// The HTML side matters more than it looks. Exchange stores a task body as
/// plain text or HTML, and Outlook writes Word-flavored markup back — inline
/// styles, conditional comments, namespaced tags. `NSAttributedString` reads
/// that reasonably well; what it writes back is verbose but valid, and Outlook
/// renders it. Bullets and bold survive a round trip through Outlook; specific
/// colors and sizes often don't.
///
/// `@MainActor` because most of these take a `UITextView`, and UIKit is
/// main-actor-isolated under Swift 6. Every caller is `RichNotesEditor`'s
/// coordinator, which is already on the main actor, so this costs nothing.
@MainActor
enum RichTextFormatter {

    // MARK: Conversion

    static func attributedString(from body: TPBody) -> NSAttributedString {
        guard body.isHTML else {
            return NSAttributedString(
                string: body.content,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .callout),
                    .foregroundColor: UIColor.label
                ]
            )
        }
        guard let data = body.content.data(using: .utf8),
              let attributed = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else {
            // Unparseable markup shouldn't lose the note. Fall back to the words.
            return NSAttributedString(string: body.plainText)
        }
        normalize(attributed)
        return attributed
    }

    static func body(from attributed: NSAttributedString) -> TPBody {
        guard attributed.length > 0 else { return TPBody(content: "", isHTML: true) }
        let range = NSRange(location: 0, length: attributed.length)
        guard let data = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ), let html = String(data: data, encoding: .utf8) else {
            return TPBody(content: attributed.string, isHTML: false)
        }
        return TPBody(content: extractBodyFragment(html), isHTML: true)
    }

    /// Keep the fragment, drop the generated `<html>` wrapper and `<style>`
    /// block. Exchange stores a body, not a document, and the wrapper is noise
    /// that grows every time a note is edited.
    private static func extractBodyFragment(_ html: String) -> String {
        guard let start = html.range(of: "<body", options: .caseInsensitive),
              let open = html.range(of: ">", range: start.lowerBound..<html.endIndex),
              let end = html.range(of: "</body>", options: .caseInsensitive)
        else { return html }
        return String(html[open.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// HTML import fixes fonts and colors absolutely, which ignores Dynamic Type
    /// and breaks in dark mode. Re-point anything that came in as plain black
    /// at `.label` so it follows the system.
    private static func normalize(_ text: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.foregroundColor, in: range) { value, sub, _ in
            guard value == nil || (value as? UIColor)?.isEssentiallyBlack == true else { return }
            text.addAttribute(.foregroundColor, value: UIColor.label, range: sub)
        }
    }

    // MARK: Commands

    static func apply(_ command: RichTextCommand, to view: UITextView) {
        switch command {
        case .toggleBold:   toggleTrait(.traitBold, in: view)
        case .toggleItalic: toggleTrait(.traitItalic, in: view)
        case .font(let design):
            mutateFont(in: view) { font in
                guard let name = design.customFontName,
                      let custom = UIFont(name: name, size: font.pointSize)
                else { return .preferredFont(forTextStyle: .callout).withSize(font.pointSize) }
                return custom
            }
        case .size(let points):
            mutateFont(in: view) { $0.withSize(points) }
        case .color(let color):
            addAttribute(.foregroundColor, value: color, in: view)
        case .bulletList:  applyList(marker: .bullet, in: view)
        case .numberList:  applyList(marker: .number, in: view)
        case .indent:      shiftIndent(by: 24, in: view)
        case .outdent:     shiftIndent(by: -24, in: view)
        }
    }

    // MARK: Command plumbing

    /// With a selection, format it. Without one, set the typing attributes so
    /// the next characters pick it up — which is what "turn on bold and keep
    /// typing" needs to work.
    private static func addAttribute(_ key: NSAttributedString.Key, value: Any, in view: UITextView) {
        let range = view.selectedRange
        if range.length > 0 {
            let text = NSMutableAttributedString(attributedString: view.attributedText)
            text.addAttribute(key, value: value, range: range)
            replace(view, with: text, keeping: range)
        } else {
            view.typingAttributes[key] = value
        }
    }

    private static func mutateFont(in view: UITextView, _ transform: (UIFont) -> UIFont) {
        let range = view.selectedRange
        if range.length > 0 {
            let text = NSMutableAttributedString(attributedString: view.attributedText)
            text.enumerateAttribute(.font, in: range) { value, sub, _ in
                let current = (value as? UIFont) ?? .preferredFont(forTextStyle: .callout)
                text.addAttribute(.font, value: transform(current), range: sub)
            }
            replace(view, with: text, keeping: range)
        } else {
            let current = (view.typingAttributes[.font] as? UIFont)
                ?? .preferredFont(forTextStyle: .callout)
            view.typingAttributes[.font] = transform(current)
        }
    }

    private static func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits, in view: UITextView) {
        let current = (view.selectedRange.length > 0
            ? view.attributedText.attribute(.font, at: view.selectedRange.location,
                                            effectiveRange: nil) as? UIFont
            : view.typingAttributes[.font] as? UIFont)
            ?? .preferredFont(forTextStyle: .callout)
        let isOn = current.fontDescriptor.symbolicTraits.contains(trait)
        mutateFont(in: view) { font in
            var traits = font.fontDescriptor.symbolicTraits
            if isOn { traits.remove(trait) } else { traits.insert(trait) }
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
    }

    private enum ListMarker { case bullet, number }

    /// A text-level list rather than a real `<ul>`: `NSAttributedString` has no
    /// list model, and prefixed lines convert to `<ul>`/`<ol>` well enough for
    /// Outlook to render. The tradeoff is that editing a marker by hand can
    /// break the list — acceptable for notes, and the alternative is a full
    /// list engine.
    private static func applyList(marker: ListMarker, in view: UITextView) {
        let text = NSMutableAttributedString(attributedString: view.attributedText)
        let lineRange = (text.string as NSString).lineRange(for: view.selectedRange)
        let lines = (text.string as NSString).substring(with: lineRange)
            .components(separatedBy: "\n")

        var index = 1
        let rebuilt = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            let stripped = line.replacingOccurrences(
                of: "^\\s*(•\\s+|\\d+\\.\\s+)", with: "", options: .regularExpression)
            defer { index += 1 }
            return marker == .bullet ? "• \(stripped)" : "\(index). \(stripped)"
        }.joined(separator: "\n")

        text.replaceCharacters(in: lineRange, with: rebuilt)
        replace(view, with: text,
                keeping: NSRange(location: lineRange.location + (rebuilt as NSString).length, length: 0))
    }

    private static func shiftIndent(by points: CGFloat, in view: UITextView) {
        let text = NSMutableAttributedString(attributedString: view.attributedText)
        let lineRange = (text.string as NSString).lineRange(for: view.selectedRange)
        guard lineRange.length > 0 else { return }

        text.enumerateAttribute(.paragraphStyle, in: lineRange) { value, sub, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle)
                ?? NSMutableParagraphStyle()
            style.firstLineHeadIndent = max(0, style.firstLineHeadIndent + points)
            style.headIndent = max(0, style.headIndent + points)
            text.addAttribute(.paragraphStyle, value: style, range: sub)
        }
        replace(view, with: text, keeping: view.selectedRange)
    }

    private static func replace(_ view: UITextView, with text: NSAttributedString, keeping range: NSRange) {
        view.attributedText = text
        // Restoring the selection matters: reassigning attributedText moves the
        // caret to the end, so formatting a word would fling the cursor away.
        view.selectedRange = NSRange(
            location: min(range.location, text.length),
            length: min(range.length, max(0, text.length - range.location))
        )
        view.delegate?.textViewDidChange?(view)
    }
}

private extension UIColor {
    /// HTML import gives literal black; the app wants `.label` so dark mode works.
    var isEssentiallyBlack: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return r < 0.06 && g < 0.06 && b < 0.06 && a > 0.9
    }
}

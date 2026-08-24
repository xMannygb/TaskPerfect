import SwiftUI
import UIKit

/// A formatted notes field, backed by `UITextView`.
///
/// SwiftUI has no rich text editor on iOS 17 — `TextEditor` is plain only — so
/// this bridges UIKit. The bridge is worth it because Exchange stores task
/// bodies as HTML, and `NSAttributedString` converts to and from HTML natively.
///
/// Formatting is applied to the current selection, or to the typing attributes
/// when nothing is selected, which is what makes "turn on bold and keep typing"
/// behave the way people expect.
struct RichNotesEditor: View {

    /// Named `note`, not `body`: `View` already requires a `body`, and a
    /// stored property of that name is a redeclaration of it.
    @Binding var note: TPBody
    @State private var coordinatorBox = CoordinatorBox()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TextViewBridge(body: $note, box: coordinatorBox)
                .frame(minHeight: 120)
        }
    }

    /// Centred one step below the body, matching `.callout`.
    private static let noteSizes: [(label: String, points: CGFloat)] = [
        ("Smallest", 11), ("Default Size", 13), ("Large", 16),
        ("Larger", 19), ("Largest", 23)
    ]

    // MARK: Toolbar

    /// One scrolling row. Ten controls at the 44pt minimum tap target need more
    /// width than a phone screen has, so it scrolls rather than shrinking the
    /// targets or wrapping to a second row that pushes the note down.
    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(CategoryTextStyle.Design.allCases, id: \.self) { design in
                        Button {
                            coordinatorBox.apply(.font(design))
                        } label: {
                            Text(design.label)
                        }
                    }
                } label: {
                    toolbarLabel("Font", systemImage: "textformat")
                }

                Menu {
                    // Named relative to the note's own size rather than in
                    // points — "13 pt" means nothing next to a body that scales
                    // with Dynamic Type.
                    ForEach(Self.noteSizes, id: \.points) { entry in
                        Button(entry.label) { coordinatorBox.apply(.size(entry.points)) }
                    }
                } label: {
                    toolbarLabel("Size", systemImage: "textformat.size")
                }

                Menu {
                    Button("Default Color") { coordinatorBox.apply(.color(.label)) }
                    ForEach(OutlookCategoryPalette.entries, id: \.index) { entry in
                        Button {
                            coordinatorBox.apply(.color(UIColor(OutlookCategoryPalette.color(for: entry.index))))
                        } label: {
                            Text(entry.name)
                        }
                    }
                } label: {
                    toolbarLabel("Color", systemImage: "paintpalette")
                }

                toolbarButton("bold", systemImage: "bold") { coordinatorBox.apply(.toggleBold) }
                toolbarButton("italic", systemImage: "italic") { coordinatorBox.apply(.toggleItalic) }
                toolbarButton("bullets", systemImage: "list.bullet") { coordinatorBox.apply(.bulletList) }
                toolbarButton("numbers", systemImage: "list.number") { coordinatorBox.apply(.numberList) }
                toolbarButton("outdent", systemImage: "decrease.indent") { coordinatorBox.apply(.outdent) }
                toolbarButton("indent", systemImage: "increase.indent") { coordinatorBox.apply(.indent) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.Palette.canvas)
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 15))
            .frame(width: 38, height: 34)
            .background(Theme.Palette.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Palette.hairline))
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Commands

enum RichTextCommand {
    case toggleBold
    case toggleItalic
    case font(CategoryTextStyle.Design)
    case size(CGFloat)
    case color(UIColor)
    case bulletList
    case numberList
    case indent
    case outdent
}

/// Lets the SwiftUI toolbar reach the live `UITextView` without the view itself
/// owning UIKit state.
@MainActor
@Observable
final class CoordinatorBox {
    weak var textView: UITextView?

    func apply(_ command: RichTextCommand) {
        guard let textView else { return }
        RichTextFormatter.apply(command, to: textView)
    }
}

// MARK: - Bridge

private struct TextViewBridge: UIViewRepresentable {

    @Binding var body: TPBody
    let box: CoordinatorBox

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        // .callout, not .body: exactly one step below on the iOS type scale, so
        // notes start a shade smaller while still scaling with Dynamic Type. A
        // hardcoded point size would go smaller but stop responding to it.
        view.font = .preferredFont(forTextStyle: .callout)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        view.attributedText = RichTextFormatter.attributedString(from: body)
        box.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        box.textView = view
        // Only push when the model changed underneath us — writing on every
        // update would fight the cursor while typing.
        guard !context.coordinator.isEditing else { return }
        let incoming = RichTextFormatter.attributedString(from: body)
        if incoming.string != view.attributedText.string {
            view.attributedText = incoming
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: TextViewBridge
        var isEditing = false

        init(_ parent: TextViewBridge) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { isEditing = true }
        func textViewDidEndEditing(_ textView: UITextView) { isEditing = false }

        func textViewDidChange(_ textView: UITextView) {
            parent.body = RichTextFormatter.body(from: textView.attributedText)
        }
    }
}

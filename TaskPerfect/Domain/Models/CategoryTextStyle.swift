import Foundation

/// How a category paints the subject line of tasks tagged with it.
///
/// A **device preference**, not mailbox data. Exchange has nowhere to store this,
/// and Outlook on a desktop won't show it — keeping it local avoids pretending
/// otherwise. Keyed by category name, so renames have to migrate the key
/// (`AppSettings.migrateTextStyle`).
public struct CategoryTextStyle: Codable, Hashable, Sendable {

    /// Index into `OutlookCategoryPalette`, or `defaultColorIndex` for plain black.
    public var colorIndex: Int
    public var design: Design
    /// Points added to the system body size. Negative shrinks.
    public var sizeDelta: Int
    public var isBold: Bool
    public var isItalic: Bool

    public static let defaultColorIndex = -1
    /// System body size on iOS. `sizeDelta` is relative to this.
    /// One step below the iOS body default. The old value was a shade large for
    /// a list you scan rather than read, and `sizeRange` is untouched — so
    /// Default now sits where −1 used to, with three steps down and four up.
    public static let baseSize: CGFloat = 16
    public static let sizeRange = -3...4

    /// Order here is the order the picker shows: System first as the default,
    /// then the rest alphabetically.
    ///
    /// Two kinds sit side by side. The four system designs resolve through
    /// `Font.system(design:)` and adapt to Dynamic Type and the user's chosen
    /// system face. The named families resolve through `Font.custom` and are
    /// fixed faces — Outlook users expect Arial and Times by name, not by
    /// category, so both belong in one list.
    public enum Design: String, CaseIterable, Codable, Sendable {
        case system
        case arial
        case bodoni
        case calibri
        case monospaced
        case rounded
        case serif
        case times

        public var label: String {
            switch self {
            case .system:     return "System Font"
            case .arial:      return "Arial"
            case .bodoni:     return "Bodoni MT"
            case .calibri:    return "Calibri"
            case .monospaced: return "Mono"
            case .rounded:    return "Rounded"
            case .serif:      return "Serif"
            case .times:      return "Times New Roman"
            }
        }

        /// The PostScript name to ask for, or `nil` for a system design.
        ///
        /// A name absent from the device falls back to the system font rather
        /// than failing — `Font.custom` does that silently, which is the right
        /// behavior here: a missing face shouldn't make a task unreadable.
        public var customFontName: String? {
            switch self {
            case .arial:   return "ArialMT"
            case .bodoni:  return "BodoniSvtyTwoITCTT-Book"
            case .calibri: return "Calibri"
            case .times:   return "TimesNewRomanPSMT"
            default:       return nil
            }
        }

        /// Bold variants, where the family provides a separate face.
        public var customFontNameBold: String? {
            switch self {
            case .arial:   return "Arial-BoldMT"
            case .bodoni:  return "BodoniSvtyTwoITCTT-Bold"
            case .calibri: return "Calibri-Bold"
            case .times:   return "TimesNewRomanPS-BoldMT"
            default:       return nil
            }
        }
    }

    public init(
        colorIndex: Int = CategoryTextStyle.defaultColorIndex,
        design: Design = .system,
        sizeDelta: Int = 0,
        isBold: Bool = false,
        isItalic: Bool = false
    ) {
        self.colorIndex = colorIndex
        self.design = design
        self.sizeDelta = sizeDelta
        self.isBold = isBold
        self.isItalic = isItalic
    }

    public static let standard = CategoryTextStyle()

    /// Nothing has been changed from the system default.
    public var isDefault: Bool { self == .standard }

    public var resolvedSize: CGFloat {
        CategoryTextStyle.baseSize + CGFloat(sizeDelta.clamped(to: CategoryTextStyle.sizeRange))
    }

    public var sizeLabel: String {
        sizeDelta == 0 ? "Default" : (sizeDelta > 0 ? "+\(sizeDelta)" : "\(sizeDelta)")
    }

    /// One-line description for the category list.
    public var summary: String {
        var parts: [String] = []
        if colorIndex != CategoryTextStyle.defaultColorIndex {
            parts.append(OutlookCategoryPalette.name(for: colorIndex))
        }
        if design != .system { parts.append(design.label) }
        if sizeDelta != 0 { parts.append(sizeLabel) }
        if isBold { parts.append("Bold") }
        if isItalic { parts.append("Italic") }
        return parts.isEmpty ? "Default" : parts.joined(separator: " · ")
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

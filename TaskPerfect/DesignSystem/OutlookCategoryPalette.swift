import SwiftUI

/// The 25 Outlook category colors, addressed by index 0...24.
///
/// Both EWS (`color` attribute in the CategoryList blob) and Microsoft Graph
/// (`preset0`...`preset24`) use this same ordering, so an index is portable.
///
/// ⚠️ These hex values are close approximations. Before shipping, put a device next to
/// desktop Outlook and tune them — users notice when "Blue Category" is the wrong blue.
public enum OutlookCategoryPalette {

    public struct Entry: Sendable {
        public let index: Int
        public let name: String
        public let hex: UInt32
    }

    public static let entries: [Entry] = [
        Entry(index:  0, name: "Red",         hex: 0xE74C3C),
        Entry(index:  1, name: "Orange",      hex: 0xF39C12),
        Entry(index:  2, name: "Peach",       hex: 0xF8CBAD),
        Entry(index:  3, name: "Yellow",      hex: 0xF1C40F),
        Entry(index:  4, name: "Green",       hex: 0x2ECC71),
        Entry(index:  5, name: "Teal",        hex: 0x1ABC9C),
        Entry(index:  6, name: "Olive",       hex: 0xA9BD4F),
        Entry(index:  7, name: "Blue",        hex: 0x3498DB),
        Entry(index:  8, name: "Purple",      hex: 0x9B59B6),
        Entry(index:  9, name: "Maroon",      hex: 0xC0392B),
        Entry(index: 10, name: "Steel",       hex: 0x95A5A6),
        Entry(index: 11, name: "Dark Steel",  hex: 0x7F8C8D),
        Entry(index: 12, name: "Gray",        hex: 0xBDC3C7),
        Entry(index: 13, name: "Dark Gray",   hex: 0x7B7B7B),
        Entry(index: 14, name: "Black",       hex: 0x000000),
        Entry(index: 15, name: "Dark Red",    hex: 0xA93226),
        Entry(index: 16, name: "Dark Orange", hex: 0xCA6F1E),
        Entry(index: 17, name: "Dark Peach",  hex: 0xD4A190),
        Entry(index: 18, name: "Dark Yellow", hex: 0xB7950B),
        Entry(index: 19, name: "Dark Green",  hex: 0x1E8449),
        Entry(index: 20, name: "Dark Teal",   hex: 0x148F77),
        Entry(index: 21, name: "Dark Olive",  hex: 0x7D8C2E),
        Entry(index: 22, name: "Dark Blue",   hex: 0x2471A3),
        Entry(index: 23, name: "Dark Purple", hex: 0x6C3483),
        Entry(index: 24, name: "Dark Maroon", hex: 0x7B241C),

        // ── Beyond Outlook's presets ──────────────────────────────────────
        //
        // Indices 0–24 are Exchange's fixed preset list. These four are ours,
        // which has a consequence worth knowing: a *category* colored with one
        // of these cannot round-trip to the mailbox, because the CategoryList
        // blob only understands 0–24. `ewsPresetIndex(for:)` maps them to the
        // nearest preset on write, so desktop Outlook shows something close
        // rather than nothing.
        //
        // As *font* colors they're unrestricted — subject styling is a device
        // preference and never leaves the phone.
        Entry(index: 25, name: "Navy",          hex: 0x14396E),
        Entry(index: 26, name: "Sky Blue",      hex: 0x1E90FF),
        Entry(index: 27, name: "Bright Orange", hex: 0xFF7A00),
        Entry(index: 28, name: "Amber",         hex: 0xD97706),

        // Deliberately more saturated than their Outlook counterparts — that
        // extra chroma is what makes them read as different rather than as a
        // slightly-off duplicate of a preset a few swatches away.
        Entry(index: 29, name: "Vivid Green",   hex: 0x00D45E),
        Entry(index: 30, name: "Forest",        hex: 0x00693C),
        Entry(index: 31, name: "Deep Gold",     hex: 0xD4A800),
        Entry(index: 32, name: "Silver",        hex: 0x7D8FA8),
        Entry(index: 33, name: "Graphite",      hex: 0x3F4A5A),
        Entry(index: 34, name: "Vivid Pink",    hex: 0xE8197B),
        Entry(index: 35, name: "Pine",          hex: 0x00706A),
        Entry(index: 36, name: "Burnt Orange",  hex: 0xE03E00),
        Entry(index: 37, name: "Burgundy",      hex: 0x7A0038),
        Entry(index: 38, name: "Cobalt",        hex: 0x1550E0),
        Entry(index: 39, name: "Crimson",        hex: 0xB3000F),
        Entry(index: 40, name: "Scarlet",        hex: 0xE01020),
        Entry(index: 41, name: "Deep Olive",     hex: 0x5E6B00),
        Entry(index: 42, name: "Rosewood",       hex: 0xC41E4E),
        Entry(index: 43, name: "Cherry",         hex: 0xFF2D2D),
        Entry(index: 44, name: "Umber",          hex: 0x8A5320),
        Entry(index: 45, name: "Mist",           hex: 0x9BB2E2),
        Entry(index: 46, name: "Bronze",         hex: 0xB08C4A),
        Entry(index: 47, name: "Mustard",        hex: 0x9B7A00)
    ]

    /// Highest index Exchange can store on a category.
    public static let lastExchangePreset = 24

    /// Presets only — what a category color picker may offer if the color has
    /// to survive a round trip to Outlook.
    public static var exchangePresets: [Entry] {
        entries.filter { $0.index <= lastExchangePreset }
    }

    /// The four beyond Exchange's presets. Offered for categories under a
    /// "Not Outlook Compatible" heading — the app renders them faithfully, and
    /// desktop Outlook falls back to `ewsPresetIndex(for:)`.
    public static var extendedColors: [Entry] {
        entries.filter { $0.index > lastExchangePreset }
    }

    /// Nearest preset for an extended color, by RGB distance. Used when writing
    /// the CategoryList blob back to Exchange.
    public static func ewsPresetIndex(for index: Int) -> Int {
        guard index > lastExchangePreset, entries.indices.contains(index) else {
            return max(0, min(index, lastExchangePreset))
        }
        let target = entries[index].hex
        let tr = Int((target >> 16) & 0xFF), tg = Int((target >> 8) & 0xFF), tb = Int(target & 0xFF)
        return exchangePresets.min { a, b in
            func distance(_ hex: UInt32) -> Int {
                let r = Int((hex >> 16) & 0xFF) - tr
                let g = Int((hex >> 8) & 0xFF) - tg
                let b = Int(hex & 0xFF) - tb
                return r*r + g*g + b*b
            }
            return distance(a.hex) < distance(b.hex)
        }?.index ?? 0
    }

    /// Color for a category index. Out-of-range or -1 yields a neutral gray,
    /// which is how Outlook renders a category with no color assigned.
    public static func color(for index: Int) -> Color {
        guard entries.indices.contains(index) else {
            return Color(white: 0.62)
        }
        return Color(hex: entries[index].hex)
    }

    public static func name(for index: Int) -> String {
        guard entries.indices.contains(index) else { return "None" }
        return entries[index].name
    }

    /// Foreground color that stays legible on top of the given category color.
    public static func foreground(for index: Int) -> Color {
        guard entries.indices.contains(index) else { return .primary }
        return luminance(of: entries[index].hex) > 0.6 ? .black : .white
    }

    /// A version of the category color that stays legible as small text on a
    /// light background.
    ///
    /// The palette is built for filled chips, where a pale swatch works fine.
    /// Peach (#F8CBAD) and Gray (#BDC3C7) as 12pt text on white are close to
    /// invisible, so anything above the luminance threshold gets darkened until
    /// it clears it. The hue is preserved — you can still tell which category
    /// it is.
    public static func textColor(for index: Int) -> Color {
        guard entries.indices.contains(index) else { return Color(white: 0.42) }
        return Color(hex: darkenedForText(entries[index].hex))
    }

    static func darkenedForText(_ hex: UInt32, ceiling: Double = 0.45) -> UInt32 {
        let lum = luminance(of: hex)
        guard lum > ceiling else { return hex }
        let factor = ceiling / lum
        let r = UInt32((Double((hex >> 16) & 0xFF) * factor).rounded())
        let g = UInt32((Double((hex >>  8) & 0xFF) * factor).rounded())
        let b = UInt32((Double( hex        & 0xFF) * factor).rounded())
        return (min(r, 255) << 16) | (min(g, 255) << 8) | min(b, 255)
    }

    private static func luminance(of hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

public extension CategoryTextStyle {
    /// Subject-line color. The default resolves to true black rather than the
    /// UI's ink navy — "default" here means black, as requested.
    var textColor: Color {
        colorIndex == CategoryTextStyle.defaultColorIndex
            ? Color(hex: 0x000000)
            : OutlookCategoryPalette.color(for: colorIndex)
    }

    /// Only meaningful for the four system designs; a named family ignores it.
    var swiftUIDesign: Font.Design {
        switch design {
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        default:          return .default
        }
    }

    var font: Font { font(forcingBold: false) }

    /// Build the subject font.
    ///
    /// Named families go through `Font.custom`, which needs the bold face
    /// requested by name — unlike `Font.system`, it won't synthesize weight from
    /// a `.bold` argument. `relativeTo:` keeps Dynamic Type working, which a
    /// fixed-size custom font would otherwise break.
    ///
    /// - Parameter forcingBold: an overdue row is bold regardless of the
    ///   category's own setting.
    func font(forcingBold: Bool, emphasis: TPTask.Emphasis = .init()) -> Font {
        // The per-task override wins over the category, and `nil` falls back to
        // it — which is what lets a task in a bold category be set explicitly
        // non-bold.
        let bold = (emphasis.bold ?? isBold) || forcingBold
        // ?? not ||, so an explicit 0 overrides a category that sets a size.
        let size = CategoryTextStyle.baseSize
            + CGFloat((emphasis.sizeDelta ?? sizeDelta)
                .clamped(to: CategoryTextStyle.sizeRange))
        if let name = bold
            ? (design.customFontNameBold ?? design.customFontName)
            : design.customFontName {
            return .custom(name, size: size, relativeTo: .body)
        }
        return .system(size: size, weight: bold ? .bold : .regular, design: swiftUIDesign)
    }
}

public extension TPCategory {
    var color: Color { OutlookCategoryPalette.color(for: colorIndex) }
    /// For the category name printed on a task row.
    var labelColor: Color {
        hasColor ? OutlookCategoryPalette.textColor(for: colorIndex) : Theme.Palette.slate
    }
    var foregroundColor: Color { OutlookCategoryPalette.foreground(for: colorIndex) }
}

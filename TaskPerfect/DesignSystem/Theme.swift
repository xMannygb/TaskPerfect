import SwiftUI

/// Design tokens.
///
/// Deliberately near-monochrome. The mailbox already carries 25 user-assigned
/// category colors; layering a brand palette on top of that fights the data.
/// Category color is the only saturated color in the app — everything else is
/// ink, slate and paper so the categories read instantly.
public enum Theme {

    // MARK: Color

    public enum Palette {
        /// Primary text and the checkbox fill.
        public static let ink       = Color(hex: 0x16283D)
        /// Secondary text, metadata, inactive glyphs.
        public static let slate     = Color(hex: 0x6B7280)
        /// Section headings. True black, heavier than body ink, so the day
        /// dividers read as structure rather than as more content.
        public static let heading   = Color.black
        /// The No Due Date section heading. Undated work isn't urgent and isn't
        /// scheduled, so it gets its own color rather than borrowing the black
        /// used by dated sections.
        public static let undated   = Color(hex: 0x14396E)
        /// Hairlines and dividers.
        public static let hairline  = Color(hex: 0xE3E5E9)
        /// Row surface.
        public static let paper     = Color.white
        /// Screen background behind rows.
        public static let canvas    = Color(hex: 0xF2F3F5)
        /// Past-due only. Used nowhere else, so it always means one thing.
        public static let overdue   = Color(hex: 0xC0392B)
        /// Row background for a past-due task. Roughly 3% red over white —
        /// enough to register while scanning, not enough to fight the bold red
        /// subject that already carries the signal.
        public static let overdueWash = Color(hex: 0xFBEAE8)
        /// Row background for a task with no due date, keyed to the navy section
        /// heading. Same weight as the overdue wash so neither shouts louder.
        public static let undatedWash = Color(hex: 0xE8EDF7)
        /// High importance marker.
        public static let flag      = Color(hex: 0xE08A1E)
    }

    // MARK: Type

    /// Utility face for dates, counts and percentages.
    /// Monospaced digits stop numbers jittering as rows update during sync.
    public static func numeric(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }

    public enum Metrics {
        public static let spineWidth: CGFloat = 4
        public static let rowInset: CGFloat = 16
        public static let rowSpacing: CGFloat = 12
        public static let corner: CGFloat = 10
    }
}

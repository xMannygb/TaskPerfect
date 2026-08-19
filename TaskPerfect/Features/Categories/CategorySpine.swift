import SwiftUI

/// The leading color spine on a task row.
///
/// One segment per category, stacked vertically. This is the app's signature
/// element: chips wrap badly on a phone and push the subject line around, while a
/// spine shows three categories in four points and keeps every row's text aligned.
///
/// Categories with no color assigned render as a hairline, not a gap — the row
/// should still read as "categorised".
public struct CategorySpine: View {

    let categories: [TPCategory]

    public init(categories: [TPCategory]) {
        self.categories = categories
    }

    public var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if categories.isEmpty {
                    Color.clear
                } else {
                    ForEach(categories) { category in
                        (category.hasColor ? category.color : Theme.Palette.hairline)
                            .frame(height: geo.size.height / CGFloat(categories.count))
                    }
                }
            }
        }
        .frame(width: Theme.Metrics.spineWidth)
        .clipShape(Capsule())
        .accessibilityHidden(true)   // names are read from the row label instead
    }
}

/// Compact category label for the detail screen and filter menu, where there is
/// room for names and the spine's density is no longer the priority.
public struct CategoryChip: View {

    let category: TPCategory
    var isSelected: Bool = false

    public init(category: TPCategory, isSelected: Bool = false) {
        self.category = category
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(category.hasColor ? category.color : Theme.Palette.hairline)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().strokeBorder(Theme.Palette.hairline, lineWidth: category.hasColor ? 0 : 1)
                )
            Text(category.name)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isSelected ? Theme.Palette.canvas : .clear)
        )
        .overlay(
            Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
    }
}

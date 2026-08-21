import SwiftUI

/// Name and color for one category. Also used to create a new one.
public struct CategoryEditorView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let category: TPCategory?
    @State private var name: String
    @State private var colorIndex: Int
    @State private var style: CategoryTextStyle = .standard
    @State private var didLoadStyle = false
    @FocusState private var nameFocused: Bool

    public init(category: TPCategory?, initialName: String = "") {
        self.category = category
        _name = State(initialValue: category?.name ?? initialName)
        _colorIndex = State(initialValue: category?.colorIndex ?? 7)
    }

    private var isNew: Bool { category == nil }

    public var body: some View {
        Form {
            Section("Category Name") {
                TextField("Category name", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
            }

            if let category, !isNew {
                let count = store.taskCount(forCategory: category.name)
                if count > 0, name != category.name {
                    Section {
                        Label(
                            "\(count) task\(count == 1 ? "" : "s") will be updated to the new name.",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }

            Section {
                swatchGrid(OutlookCategoryPalette.exchangePresets)
                LabeledContent("Selected", value: OutlookCategoryPalette.name(for: colorIndex))
                    .foregroundStyle(Theme.Palette.slate)
            } header: {
                Text("Category Color (Outlook Compatible)")
            }

            Section {
                swatchGrid(OutlookCategoryPalette.extendedColors)
            } header: {
                Text("Category Color (Not Outlook Compatible)")
            } footer: {
                if isExtendedColor {
                    Label(
                        "Outlook on your computer will show \(OutlookCategoryPalette.name(for: OutlookCategoryPalette.ewsPresetIndex(for: colorIndex))) instead — it only stores its own 25 colors. Task Perfect shows the color you picked.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(Theme.Palette.flag)
                } else {
                    Text("Exchange only stores its own 25 colors on a category. Pick one of these and Task Perfect shows it, while Outlook falls back to the nearest match.")
                }
            }

            subjectTextSection

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    CategoryChip(category: TPCategory(name: name.isEmpty ? "Preview" : name, colorIndex: colorIndex))
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(OutlookCategoryPalette.color(for: colorIndex))
                            .frame(width: 4, height: 34)
                        Image(systemName: "circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.Palette.slate)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Reconcile the corporate card statement")
                                .font(style.font)
                                .italic(style.isItalic)
                                .foregroundStyle(style.textColor)
                                .lineLimit(2)
                            Text("🗓 Aug 15 · \(name.isEmpty ? "Category" : name)")
                                .font(Theme.numeric(12))
                                .foregroundStyle(Theme.Palette.slate)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("How a task will look")
            }
        }
        .navigationTitle(isNew ? "New Category" : "Edit Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if isNew { nameFocused = true }
            if !didLoadStyle {
                style = store.settings.textStyle(for: category?.name ?? name) ?? .standard
                didLoadStyle = true
            }
        }
    }

    // MARK: Subject text

    // Two sibling Sections, so the result-builder transform has to be asked for
    // explicitly — without it there is no single expression to return.
    @ViewBuilder
    private var subjectTextSection: some View {
        Section {
            // Default sits first and is plain black — the requested default, not
            // the UI's ink navy.
            fontColorGrid
        } header: {
            Text("Task Subject Text Color")
        }

        Section {
            // A menu, not segmented control: eight named fonts won't fit as
            // segments, and the names are what identify them.
            Picker("Font", selection: $style.design) {
                ForEach(CategoryTextStyle.Design.allCases, id: \.self) { design in
                    // Each option previews its own family, so the list reads as
                    // a font list rather than a list of words.
                    Text(design.label)
                        .font(CategoryTextStyle(design: design).font)
                        .tag(design)
                }
            }
            .pickerStyle(.menu)

            Stepper(value: $style.sizeDelta, in: CategoryTextStyle.sizeRange) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(style.sizeLabel)
                        .font(Theme.numeric(16, weight: .medium))
                        .foregroundStyle(Theme.Palette.slate)
                }
            }

            Toggle("Bold", isOn: $style.isBold)
            Toggle("Italic", isOn: $style.isItalic)

            // Names both, because it clears the color set in the section above
            // as well as the font settings in this one.
            Button("Reset color and font to default") {
                withAnimation { style = .standard }
            }
            .foregroundStyle(style.isDefault ? Theme.Palette.slate : Theme.Palette.overdue)
            .disabled(style.isDefault)
        } header: {
            Text("Task Subject Font Style")
        } footer: {
            Text("Applies to the subject line of tasks in this category. If a task has several categories, the first one carrying a custom style wins — the same order the color spine paints.")
        }
    }

    private var fontColorGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                swatch(
                    index: CategoryTextStyle.defaultColorIndex,
                    color: Color(hex: 0x000000),
                    label: "Default (black)"
                )
                ForEach(OutlookCategoryPalette.entries, id: \.index) { entry in
                    swatch(index: entry.index, color: Color(hex: entry.hex), label: entry.name)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(index: Int, color: Color, label: String) -> some View {
        Button {
            style.colorIndex = index
        } label: {
            Circle()
                .fill(color)
                .frame(height: 28)
                .overlay(
                    Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
                .overlay {
                    if style.colorIndex == index {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                index == CategoryTextStyle.defaultColorIndex
                                    ? .white
                                    : OutlookCategoryPalette.foreground(for: index)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(style.colorIndex == index ? .isSelected : [])
    }

    private var isExtendedColor: Bool {
        colorIndex > OutlookCategoryPalette.lastExchangePreset
    }

    private func swatchGrid(_ entries: [OutlookCategoryPalette.Entry]) -> some View {
        // Same geometry as the subject-text swatches below — 7 across at 28pt.
        // Two grids of different-sized circles in one screen read as a mistake.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
            ForEach(entries, id: \.index) { entry in
                Button {
                    colorIndex = entry.index
                } label: {
                    Circle()
                        .fill(Color(hex: entry.hex))
                        .frame(height: 28)
                        .overlay {
                            if colorIndex == entry.index {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(OutlookCategoryPalette.foreground(for: entry.index))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(colorIndex == entry.index ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenStyle = style
        dismiss()
        Task {
            if let category {
                if trimmed != category.name {
                    await store.rename(category, to: trimmed)
                }
                if colorIndex != category.colorIndex {
                    // Re-fetch by the new name — the rename already landed.
                    let target = store.categories.first { $0.name == trimmed } ?? category
                    await store.recolor(target, to: colorIndex)
                }
            } else {
                await store.addCategory(name: trimmed, colorIndex: colorIndex)
            }
            store.settings.setTextStyle(chosenStyle, for: trimmed)
        }
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings())
    return NavigationStack { CategoryEditorView(category: nil) }
        .environment(store)
        .task { await store.load() }
}

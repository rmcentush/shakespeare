import SwiftUI
import UniformTypeIdentifiers

struct ToolbarView: View {
    @Environment(EditorViewModel.self) private var viewModel
    var featureTourTarget: FeatureTourTarget?
    private static let mixedTypographyValue = "__mixed__"
    private static let customTypographyValue = "__custom__"
    private static let defaultTypographyValue = "__default__"
    private let lineHeightOptions: [Double] = Array(stride(from: 1.0, through: 2.5, by: 0.1)).map {
        Double(round($0 * 10) / 10)
    }

    private var selectedFontFamily: String {
        if viewModel.selectionState.isFontFamilyMixed {
            return Self.mixedTypographyValue
        }
        let value = viewModel.selectionState.fontFamily
        if value.isEmpty { return FontManager.baseFont }
        return FontManager.availableFonts.contains(value) ? value : Self.customTypographyValue
    }

    private var selectedFontSize: Int {
        if viewModel.selectionState.isFontSizeMixed { return 0 }
        guard !viewModel.selectionState.fontSize.isEmpty else {
            return Int(FontManager.baseSize)
        }
        let value = viewModel.selectionState.fontSize
            .replacingOccurrences(of: "px", with: "")
        guard let size = Double(value), size.rounded() == size else { return -1 }
        let integerSize = Int(size)
        return (12...28).contains(integerSize) ? integerSize : -1
    }

    private var selectedLineHeight: String {
        if viewModel.selectionState.isLineHeightMixed {
            return Self.mixedTypographyValue
        }
        guard let value = Double(viewModel.selectionState.lineHeight) else {
            return Self.defaultTypographyValue
        }
        guard lineHeightOptions.contains(where: { abs($0 - value) < 0.001 }) else {
            return Self.customTypographyValue
        }
        return String(format: "%.1f", value)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                leadingToolbarContent
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 8)
                    .padding(.vertical, 4)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            trailingToolbarContent
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var leadingToolbarContent: some View {
        HStack(spacing: 2) {
            // Font picker
            Picker("", selection: Binding(
                get: { selectedFontFamily },
                set: { newFont in
                    guard FontManager.availableFonts.contains(newFont) else { return }
                    viewModel.applyFormat("fontFamily", value: newFont)
                }
            )) {
                if selectedFontFamily == Self.mixedTypographyValue {
                    Text("Mixed").tag(Self.mixedTypographyValue)
                } else if selectedFontFamily == Self.customTypographyValue {
                    Text("Custom").tag(Self.customTypographyValue)
                }
                Text("Georgia").tag("Georgia")
                Text("Palatino").tag("Palatino")
                Text("Baskerville").tag("Baskerville")
                Text("Times New Roman").tag("Times New Roman")
                Text("Helvetica Neue").tag("Helvetica Neue")
                Text("San Francisco").tag("-apple-system")
            }
            .frame(width: 140)
            .help("Font Family")
            .accessibilityLabel("Font Family")

            Picker("", selection: Binding(
                get: { selectedFontSize },
                set: { newSize in
                    guard (12...28).contains(newSize) else { return }
                    viewModel.applyFormat("fontSize", value: "\(newSize)")
                }
            )) {
                if selectedFontSize == 0 {
                    Text("Mixed").tag(0)
                } else if selectedFontSize == -1 {
                    Text("Custom").tag(-1)
                }
                ForEach(Array(12...28), id: \.self) { size in
                    Text("\(size) px").tag(size)
                }
            }
            .frame(width: 78)
            .help("Font Size")
            .accessibilityLabel("Font Size")

            Picker("", selection: Binding(
                get: { selectedLineHeight },
                set: { newHeight in
                    if newHeight == Self.defaultTypographyValue {
                        viewModel.applyFormat("unsetLineHeight")
                    } else if Double(newHeight) != nil {
                        viewModel.applyFormat("lineHeight", value: newHeight)
                    }
                }
            )) {
                if selectedLineHeight == Self.mixedTypographyValue {
                    Text("Mixed").tag(Self.mixedTypographyValue)
                } else if selectedLineHeight == Self.customTypographyValue {
                    Text("Custom").tag(Self.customTypographyValue)
                }
                Text("Default").tag(Self.defaultTypographyValue)
                ForEach(lineHeightOptions, id: \.self) { lineHeight in
                    Text(String(format: "%.1fx", lineHeight))
                        .tag(String(format: "%.1f", lineHeight))
                }
            }
            .frame(width: 74)
            .help("Line Spacing")
            .accessibilityLabel("Line Spacing")

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Text formatting
            Group {
                FormatButton(
                    icon: "bold",
                    isActive: viewModel.selectionState.isBold,
                    label: "Bold",
                    help: "Bold (Cmd+B)",
                    isTourHighlighted: featureTourTarget == .formatting
                ) {
                    viewModel.applyFormat("bold")
                }
                FormatButton(
                    icon: "italic",
                    isActive: viewModel.selectionState.isItalic,
                    label: "Italic",
                    help: "Italic (Cmd+I)"
                ) {
                    viewModel.applyFormat("italic")
                }
                FormatButton(
                    icon: "underline",
                    isActive: viewModel.selectionState.isUnderline,
                    label: "Underline",
                    help: "Underline (Cmd+U)"
                ) {
                    viewModel.applyFormat("underline")
                }
                FormatButton(
                    icon: "strikethrough",
                    isActive: viewModel.selectionState.isStrike,
                    label: "Strikethrough"
                ) {
                    viewModel.applyFormat("strike")
                }
                LinkButton()
                FootnoteButton()
                TextColorButton()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            DocumentStylePicker(currentHeading: viewModel.selectionState.heading) { level in
                if level == 0 {
                    viewModel.applyFormat("paragraph")
                } else {
                    viewModel.applyFormat("heading", value: "\(level)")
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Lists
            Group {
                FormatButton(
                    icon: "list.bullet",
                    isActive: viewModel.selectionState.isBulletList,
                    label: "Bulleted List"
                ) {
                    viewModel.applyFormat("bulletList")
                }
                FormatButton(
                    icon: "list.number",
                    isActive: viewModel.selectionState.isOrderedList,
                    label: "Numbered List"
                ) {
                    viewModel.applyFormat("orderedList")
                }
                FormatButton(
                    icon: "text.quote",
                    isActive: viewModel.selectionState.isBlockquote,
                    label: "Block Quote"
                ) {
                    viewModel.applyFormat("blockquote")
                }
            }

            // Insert image
            FormatButton(icon: "photo", isActive: false, label: "Insert Image") {
                insertImage()
            }

            if viewModel.selectionState.isImage {
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                ImageLayoutControls()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Alignment
            Group {
                AlignButton(alignment: "left", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignLeft")
                }
                AlignButton(alignment: "center", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignCenter")
                }
                AlignButton(alignment: "right", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignRight")
                }
                AlignButton(alignment: "justify", current: viewModel.selectionState.textAlign) {
                    viewModel.applyFormat("alignJustify")
                }
            }
        }
    }

    private var trailingToolbarContent: some View {
        HStack(spacing: 2) {
            ZoomControls()

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Focus mode
            FocusModeButton(isTourHighlighted: featureTourTarget == .focus)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Light/Dark mode toggle
            AppearanceToggle()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await viewModel.importImage(from: url)
                } catch {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn’t Import Image"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

}

struct AppearanceToggle: View {
    @Environment(EditorViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("editorAppearance") private var appearance: String = "system"
    @State private var isExpanded = false

    private let options = [
        AppearanceOption(id: "system", icon: "circle.lefthalf.filled", label: "System"),
        AppearanceOption(id: "light", icon: "sun.max", label: "Light"),
        AppearanceOption(id: "dark", icon: "moon", label: "Dark")
    ]

    private var selectedOption: AppearanceOption {
        options.first { $0.id == appearance } ?? options[0]
    }

    private var otherOptions: [AppearanceOption] {
        options.filter { $0.id != selectedOption.id }
    }

    private var expansionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.01)
            : .spring(response: 0.28, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                ForEach(otherOptions) { option in
                    AppearanceOptionButton(option: option, isSelected: false, isExpanded: false) {
                        select(option)
                    }
                    .transition(
                        .scale(scale: 0.72, anchor: .trailing)
                            .combined(with: .opacity)
                    )
                }
            }

            AppearanceOptionButton(option: selectedOption, isSelected: true, isExpanded: isExpanded) {
                withAnimation(expansionAnimation) {
                    isExpanded.toggle()
                }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(expansionAnimation, value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
        .onAppear {
            applyAppearance(appearance)
        }
        .onChange(of: appearance) { _, newValue in
            applyAppearance(newValue)
        }
        .onExitCommand {
            guard isExpanded else { return }
            withAnimation(expansionAnimation) {
                isExpanded = false
            }
        }
    }

    private func select(_ option: AppearanceOption) {
        withAnimation(expansionAnimation) {
            appearance = option.id
            isExpanded = false
        }
    }

    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
            viewModel.setThemeCSS(FontManager.shared.themedCSS(for: mode))
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
            viewModel.setThemeCSS(FontManager.shared.themedCSS(for: mode))
        default:
            NSApp.appearance = nil
            viewModel.setThemeCSS(FontManager.shared.themedCSS(for: mode))
        }
    }
}

private struct AppearanceOption: Identifiable {
    let id: String
    let icon: String
    let label: String
}

private struct AppearanceOptionButton: View {
    let option: AppearanceOption
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: option.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 30, height: 28)
                .background(
                    isSelected
                        ? Color.accentColor
                        : isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(
            isSelected
                ? "\(option.label) Appearance — \(isExpanded ? "Hide" : "Show") Options"
                : "\(option.label) Appearance"
        )
        .accessibilityLabel(
            isSelected
                ? "\(option.label) appearance, selected. \(isExpanded ? "Hide" : "Show") options"
                : "Use \(option.label.lowercased()) appearance"
        )
    }
}

struct ZoomControls: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var isResetHovered = false

    var body: some View {
        HStack(spacing: 0) {
            FormatButton(
                icon: "minus.magnifyingglass",
                isActive: false,
                label: "Zoom Out",
                help: "Zoom Out (Cmd+-)"
            ) {
                viewModel.zoomOut()
            }
            .disabled(!viewModel.canZoomOut)

            Button {
                viewModel.resetZoom()
            } label: {
                Text("\(viewModel.zoomPercent)%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(viewModel.zoomPercent == 100 ? .secondary : .primary)
                    .frame(width: 50, height: 28)
                    .background(isResetHovered ? Color.primary.opacity(0.08) : Color.clear)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isResetHovered = hovering
            }
            .help("Actual Size (Cmd+0)")
            .accessibilityLabel("Reset Zoom to 100%")

            FormatButton(
                icon: "plus.magnifyingglass",
                isActive: false,
                label: "Zoom In",
                help: "Zoom In (Cmd++)"
            ) {
                viewModel.zoomIn()
            }
            .disabled(!viewModel.canZoomIn)
        }
        .accessibilityElement(children: .contain)
    }
}

struct FormatButton: View {
    let icon: String
    let isActive: Bool
    let label: String
    let helpText: String
    let isTourHighlighted: Bool
    let action: () -> Void
    @State private var isHovered = false

    init(
        icon: String,
        isActive: Bool,
        label: String,
        help: String? = nil,
        isTourHighlighted: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isActive = isActive
        self.label = label
        self.helpText = help ?? label
        self.isTourHighlighted = isTourHighlighted
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .background(
                    isActive ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
                .featureTourHighlight(isTourHighlighted)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
        .accessibilityLabel(label)
    }
}

struct DocumentStylePicker: View {
    let currentHeading: Int
    let onSelect: (Int) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { currentHeading },
            set: { newLevel in
                guard newLevel != currentHeading else { return }
                onSelect(newLevel)
            }
        )) {
            Text("Body").tag(0)
            Text("Title").tag(1)
            Text("Subtitle").tag(2)
            Text("Section head").tag(3)
        }
        .frame(width: 132)
        .help("Document Style")
        .accessibilityLabel("Document Style")
    }
}

struct AlignButton: View {
    let alignment: String
    let current: String
    let action: () -> Void
    @State private var isHovered = false

    private var iconName: String {
        switch alignment {
        case "center": return "text.aligncenter"
        case "right": return "text.alignright"
        case "justify": return "text.justify"
        default: return "text.alignleft"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .frame(width: 28, height: 28)
                .background(
                    current == alignment ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Align \(alignment.capitalized)")
        .accessibilityLabel("Align \(alignment.capitalized)")
    }
}

struct ImageLayoutControls: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showAccessibilityPopover = false
    @State private var altText = ""
    @State private var isDecorative = false

    private var state: EditorViewModel.SelectionState {
        viewModel.selectionState
    }

    var body: some View {
        Group {
            FormatButton(
                icon: "textformat",
                isActive: state.imageLayout == "inline",
                label: "Inline Image"
            ) {
                viewModel.applyFormat("setImageLayout", value: "inline")
            }

            FormatButton(
                icon: "text.aligncenter",
                isActive: state.imageLayout == "block" && state.imageAlign == "center",
                label: "Centered Image"
            ) {
                viewModel.applyFormat("setImageLayout", value: "block-center")
            }

            FormatButton(
                icon: "text.alignleft",
                isActive: state.imageLayout == "float-left",
                label: "Float Image Left"
            ) {
                viewModel.applyFormat("setImageLayout", value: "float-left")
            }

            FormatButton(
                icon: "text.alignright",
                isActive: state.imageLayout == "float-right",
                label: "Float Image Right"
            ) {
                viewModel.applyFormat("setImageLayout", value: "float-right")
            }

            FormatButton(
                icon: "arrow.counterclockwise",
                isActive: false,
                label: "Reset Image Crop"
            ) {
                viewModel.applyFormat("resetImageCrop")
            }

            Button {
                altText = state.imageAlt
                isDecorative = state.imageDecorative
                showAccessibilityPopover = true
            } label: {
                Image(systemName: "accessibility")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(
                        state.imageDecorative || !state.imageAlt.isEmpty
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }
            .buttonStyle(.plain)
            .help("Image Description")
            .accessibilityLabel("Edit image description")
            .popover(isPresented: $showAccessibilityPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Image Accessibility")
                        .font(.headline)

                    TextField("Describe the image", text: $altText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .disabled(isDecorative)

                    Toggle("Decorative image", isOn: $isDecorative)

                    Text(isDecorative
                        ? "Assistive technologies will skip this image."
                        : "A concise description helps people using screen readers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("Cancel") { showAccessibilityPopover = false }
                        Button("Apply") {
                            if isDecorative {
                                viewModel.applyFormat("setImageDecorative", value: "true")
                            } else {
                                viewModel.applyFormat("setImageDecorative", value: "false")
                                viewModel.applyFormat("setImageAlt", value: altText)
                            }
                            showAccessibilityPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isDecorative && altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(width: 320)
            }
        }
    }
}

struct TextColorButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showPopover = false
    @State private var isHovered = false

    private static let palette: [(name: String, hex: String, color: Color)] = [
        ("Black", "#000000", Color.black),
        ("Dark Gray", "#6b7280", Color(red: 0.42, green: 0.45, blue: 0.50)),
        ("Red", "#e53e3e", Color(red: 0.90, green: 0.24, blue: 0.24)),
        ("Orange", "#dd6b20", Color(red: 0.87, green: 0.42, blue: 0.13)),
        ("Yellow", "#d69e2e", Color(red: 0.84, green: 0.62, blue: 0.18)),
        ("Green", "#38a169", Color(red: 0.22, green: 0.63, blue: 0.41)),
        ("Teal", "#319795", Color(red: 0.19, green: 0.59, blue: 0.58)),
        ("Blue", "#3182ce", Color(red: 0.19, green: 0.51, blue: 0.81)),
        ("Purple", "#805ad5", Color(red: 0.50, green: 0.35, blue: 0.84)),
        ("Pink", "#d53f8c", Color(red: 0.84, green: 0.25, blue: 0.55)),
    ]

    private var activeColor: Color? {
        guard !viewModel.selectionState.isTextColorMixed else { return nil }
        let c = viewModel.selectionState.textColor.lowercased()
        guard !c.isEmpty else { return nil }
        return Self.palette.first(where: { c == $0.hex })?.color
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            VStack(spacing: 1) {
                Text("A")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(activeColor ?? .primary)
                RoundedRectangle(cornerRadius: 1)
                    .fill(activeColor ?? Color.primary)
                    .frame(width: 14, height: 3)
            }
            .frame(width: 28, height: 28)
            .background(
                showPopover ? Color.accentColor.opacity(0.2) :
                isHovered ? Color.primary.opacity(0.08) : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help("Text Color")
        .accessibilityLabel("Text Color")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 5)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Self.palette, id: \.hex) { item in
                        ColorSwatch(
                            color: item.color,
                            hex: item.hex,
                            name: item.name,
                            isSelected: viewModel.selectionState.textColor.lowercased() == item.hex
                        ) {
                            viewModel.applyFormat("toggleColor", value: item.hex)
                            showPopover = false
                        }
                    }
                }

                Divider()

                Button {
                    viewModel.applyFormat("unsetColor")
                    showPopover = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                        Text("Remove Color")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(
                    viewModel.selectionState.textColor.isEmpty &&
                    !viewModel.selectionState.isTextColorMixed
                )
            }
            .padding(10)
        }
    }
}

struct ColorSwatch: View {
    let color: Color
    let hex: String
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.3) : Color.clear), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help(name)
        .accessibilityLabel("\(name) text color\(isSelected ? ", selected" : "")")
    }
}

struct LinkButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showPopover = false
    @State private var linkURL = ""
    @State private var isHovered = false

    var body: some View {
        Button {
            if viewModel.selectionState.isLink {
                viewModel.applyFormat("unlink")
            } else {
                linkURL = ""
                showPopover = true
            }
        } label: {
            Image(systemName: "link")
                .frame(width: 28, height: 28)
                .background(
                    viewModel.selectionState.isLink ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Insert Link (Cmd+K)")
        .accessibilityLabel(viewModel.selectionState.isLink ? "Remove Link" : "Insert Link")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                Text("Insert Link")
                    .font(.headline)
                TextField("https://", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { applyLink() }
                HStack {
                    Button("Cancel") {
                        showPopover = false
                    }
                    Spacer()
                    Button("Apply") {
                        applyLink()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(linkURL.isEmpty)
                }
            }
            .padding()
        }
    }

    private func applyLink() {
        guard !linkURL.isEmpty else { return }
        var url = linkURL
        if !url.contains("://") {
            url = "https://" + url
        }
        viewModel.applyFormat("setLink", value: url)
        showPopover = false
    }
}

struct FootnoteButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    @State private var showPopover = false
    @State private var noteText = ""
    @State private var isHovered = false

    private var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button {
            noteText = viewModel.selectionState.isFootnote ? viewModel.selectionState.footnoteText : ""
            showPopover = true
        } label: {
            Image(systemName: "textformat.superscript")
                .frame(width: 28, height: 28)
                .background(
                    viewModel.selectionState.isFootnote ? Color.accentColor.opacity(0.2) :
                    isHovered ? Color.primary.opacity(0.08) : Color.clear
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(viewModel.selectionState.isFootnote ? "Edit Footnote" : "Insert Footnote")
        .accessibilityLabel(viewModel.selectionState.isFootnote ? "Edit Footnote" : "Insert Footnote")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.selectionState.isFootnote ? "Edit Footnote" : "Insert Footnote")
                    .font(.headline)

                TextEditor(text: $noteText)
                    .font(.body)
                    .frame(width: 280, height: 120)
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    if viewModel.selectionState.isFootnote {
                        Button("Remove", role: .destructive) {
                            viewModel.applyFormat("removeFootnote")
                            showPopover = false
                        }
                    }

                    Spacer()

                    Button("Cancel") {
                        showPopover = false
                    }

                    Button("Apply") {
                        applyFootnote()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedNoteText.isEmpty)
                }
            }
            .padding()
        }
    }

    private func applyFootnote() {
        guard !trimmedNoteText.isEmpty else { return }
        viewModel.applyFormat("setFootnote", value: trimmedNoteText)
        showPopover = false
    }
}

struct FocusModeButton: View {
    @Environment(EditorViewModel.self) private var viewModel
    let isTourHighlighted: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .toggleFocusMode, object: viewModel)
        } label: {
            Image(systemName: "eye")
                .frame(width: 28, height: 28)
                .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                .cornerRadius(4)
                .featureTourHighlight(isTourHighlighted)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Focus Mode (Cmd+Shift+F)")
        .accessibilityLabel("Focus Mode")
    }
}

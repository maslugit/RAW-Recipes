import SwiftUI
import AppKit
import CoreText

// MARK: - Design tokens
//
// Every color, text style and metric the app uses lives here. Views use the token names
// (Theme.secondaryText, Theme.TextStyle.label …), never raw values, so a change here
// changes it everywhere. Hex values match the design file.

enum Theme {
    // MARK: Colors
    /// Window background – dark, but not pure black.
    static let nsBackground = NSColor(white: 0.07, alpha: 1)
    static let background = Color(nsColor: nsBackground)
    /// Slightly lighter, for the stacks (title bar, preview, filmstrip, import).
    static let panel = Color(white: 0.12)
    static let button = Color(white: 0.07)
    static let buttonPressed = Color(white: 0.17)
    static let border = Color(white: 0.24)
    static let divider = Color(white: 0.18)
    /// Gray background for pickers.
    static let track = Color(white: 0.20)

    static let text = Color.white
    static let secondaryText = Color(white: 0.75)
    static let tertiaryText = Color(white: 0.52)

    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// Warnings, e.g. the badge for files missing from an import.
    static let danger = Color(hex: "#D13030")
    static let onDanger = Color.white

    /// Behind photos and thumbnails (letterboxing).
    static let imageBackground = Color.black
    /// The RAW / JPG tags in the filmstrip.
    static let tagFill = Color(white: 0.16)
    static let tagStroke = Color(white: 0.45)

    // MARK: Metrics

    static let gap: CGFloat = 8
    static let corner: CGFloat = 16        // stacks
    static let buttonCorner: CGFloat = 10  // buttons
    static let thumbCorner: CGFloat = 8    // thumbnails
}

// MARK: - Fonts

/// Averia Serif Libre (SIL Open Font License), bundled with the app.
/// The .ttf files live in Sources/RAWRecipes/Resources/Fonts. If missing, the system serif is used.
enum AppFont {
    static let regular = "AveriaSerifLibre-Regular"
    static let bold = "AveriaSerifLibre-Bold"
    private(set) static var isAvailable = false

    /// Called once at app launch.
    static func register() {
        for directory in fontDirectories() {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        isAvailable = NSFont(name: regular, size: 12) != nil
    }

    private static func fontDirectories() -> [URL] {
        // Built .app (build-app.sh copies the fonts here).
        if let resources = Bundle.main.resourceURL {
            let fonts = resources.appendingPathComponent("Fonts")
            if FileManager.default.fileExists(atPath: fonts.path) { return [fonts] }
        }
        // Running from Xcode: the Swift package resource bundle.
        guard let resources = Bundle.module.resourceURL else { return [] }
        return [resources.appendingPathComponent("Fonts"), resources]
    }
}

extension Theme {
    /// Text styles. Averia Serif Libre for text, the system monospace for file names and values.
    enum TextStyle {
        /// The photo name above the preview.
        static var title: Font { Theme.font(19, bold: true) }
        /// Section headers and the window title.
        static var heading: Font { Theme.font(18, bold: true) }
        /// Buttons, rows, values – the default size.
        static var body: Font { Theme.font(18) }
        /// Summaries, setting names, dates.
        static var secondary: Font { Theme.font(16) }
        /// Smaller text, e.g. "Save Lightroom to" and the breakdown rows.
        static var label: Font { Theme.font(15) }
        /// File extensions and statuses: ".xmp", "Included".
        static var mono: Font { .system(size: 13, design: .monospaced) }
        /// File names under the thumbnails.
        static var fileName: Font { .system(size: 14) }
        /// The count badge.
        static var badge: Font { .system(size: 11, weight: .regular, design: .monospaced) }
        /// RAW / JPG tags on the thumbnails.
        static var tag: Font { .system(size: 9.5, weight: .semibold, design: .monospaced) }
    }

    /// Averia at any size. Prefer a TextStyle; use this only for one-off sizes.
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        if AppFont.isAvailable {
            return .custom(bold ? AppFont.bold : AppFont.regular, size: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
    }
}

extension View {
    /// A "stack": lighter black background with rounded corners.
    func panel() -> some View {
        background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

// MARK: - Dark button

struct DarkButtonStyle: ButtonStyle {
    var height: CGFloat = 42

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        DarkButtonBody(configuration: configuration, height: height)
    }

    private struct DarkButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.TextStyle.body)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .fill(configuration.isPressed ? Theme.buttonPressed : Theme.button)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

// MARK: - Checkbox

/// Green and filled by default. The app uses a white border and white check mark (filled: false).
struct GreenCheckbox: View {
    let isOn: Bool
    var color: Color = Theme.green
    var checkColor: Color = .white
    var size: CGFloat = 16
    /// `false`: the box is not filled when checked – only the border and check mark get the color.
    var filled = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(isOn && filled ? color : Color.black.opacity(0.45))
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .strokeBorder(isOn ? color : Theme.tertiaryText, lineWidth: 1.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.56, weight: .heavy))
                    .foregroundStyle(checkColor)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Sidecar toggle (Lightroom / RapidRAW)

struct SidecarToggle: View {
    let title: String
    @Binding var isOn: Bool
    /// Fills the full width.
    var fullWidth = false
    /// Shown in light gray at the far right, e.g. ".xmp".
    var fileExtension: String? = nil

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                GreenCheckbox(isOn: isOn, color: .white, checkColor: .white, size: 18, filled: false)
                Text(title)
                if fullWidth || fileExtension != nil { Spacer(minLength: 8) }
                if let fileExtension {
                    Text(fileExtension)
                        .font(Theme.TextStyle.mono)   // same as the file type in the filmstrip
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(ToggleRowStyle(isOn: isOn, height: 54))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// No border. Black background when the option is on, otherwise transparent.
struct ToggleRowStyle: ButtonStyle {
    let isOn: Bool
    var height: CGFloat = 42

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(Theme.TextStyle.body)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(background(pressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
    }

    private func background(pressed: Bool) -> Color {
        if pressed { return Theme.buttonPressed }
        return isOn ? Theme.button : Color.clear
    }
}

// MARK: - Sliding picker

/// Equal-width options on one row, no background. The black box slides to the selected option.
struct SlidingPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var height: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let count = CGFloat(max(options.count, 1))
            let segment = geo.size.width / count
            let index = CGFloat(options.firstIndex { $0.value == selection } ?? 0)

            ZStack(alignment: .leading) {
                // No inner padding: the box lines up edge to edge with the buttons below.
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(Theme.button)
                    .frame(width: segment, height: geo.size.height)
                    .offset(x: index * segment)
                    // Animated on the value itself – the selection is stored in @AppStorage, where
                    // withAnimation does not carry over, so the box jumped instead of sliding.
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)

                HStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        Button {
                            selection = options[i].value
                        } label: {
                            Text(options[i].title)
                                .font(Theme.TextStyle.secondary)
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .frame(width: segment, height: geo.size.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Accordion stack

struct SidebarSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    /// Short summary shown in the header when the section is collapsed.
    var summary: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: title, isExpanded: $isExpanded, summary: summary)

            Collapsible(isExpanded: isExpanded) {
                VStack(spacing: 0) {
                    SectionDivider()
                    content()
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .clipped()
        .panel()
    }
}

/// Expands and collapses in two steps:
/// collapse = fade out the content, then shrink. Expand = grow, then fade in the content.
struct Collapsible<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content

    /// The content takes up space in the layout.
    @State private var takesSpace: Bool
    /// The content is visible.
    @State private var isVisible: Bool
    /// Incremented on every click, so a stale step does not run after a newer click.
    @State private var generation = 0

    private let fade = 0.15
    private let resize = 0.22

    init(isExpanded: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isExpanded = isExpanded
        self.content = content
        _takesSpace = State(initialValue: isExpanded)
        _isVisible = State(initialValue: isExpanded)
    }

    var body: some View {
        Group {
            if takesSpace {
                content()
                    .opacity(isVisible ? 1 : 0)
                    .transition(.identity)
            }
        }
        .onChange(of: isExpanded) { expanded in
            generation += 1
            let current = generation
            if expanded {
                withAnimation(.easeInOut(duration: resize)) { takesSpace = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + resize) {
                    guard current == generation else { return }
                    withAnimation(.easeInOut(duration: fade)) { isVisible = true }
                }
            } else {
                withAnimation(.easeInOut(duration: fade)) { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + fade) {
                    guard current == generation else { return }
                    withAnimation(.easeInOut(duration: resize)) { takesSpace = false }
                }
            }
        }
    }
}

/// Light gray divider with the same side margin as the stack content.
struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

/// Clickable header with a chevron that expands and collapses a section.
struct SectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    var summary: String? = nil
    @State private var hovering = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(Theme.TextStyle.heading)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if !isExpanded, let summary {
                    Text(summary)
                        .font(Theme.TextStyle.secondary)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                AppIcon(kind: .chevron, hovered: hovering, expanded: isExpanded)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Hex colors

extension Color {
    /// `Color(hex: "#D13030")` or `Color(hex: "D13030")`, as written in the design file.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

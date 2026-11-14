import SwiftUI
import AppKit

// MARK: - Select all (menu commands)

struct SelectionActions {
    let selectAll: () -> Void
    let selectNone: () -> Void
}

private struct SelectionActionsKey: FocusedValueKey {
    typealias Value = SelectionActions
}

extension FocusedValues {
    var selectionActions: SelectionActions? {
        get { self[SelectionActionsKey.self] }
        set { self[SelectionActionsKey.self] = newValue }
    }
}

/// Replaces the Edit menu's cut/copy/paste (the app has no text fields) with
/// Select All ⌘A and Deselect All ⌥⌘A.
struct SelectionCommands: Commands {
    @FocusedValue(\.selectionActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Select All") { actions?.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(actions == nil)
            Button("Deselect All") { actions?.selectNone() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(actions == nil)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var camera: CameraService
    @StateObject private var windowRef = WindowRef()
    @State private var selection = Set<String>()
    /// The photo shown in the preview (the one clicked last).
    @State private var focusedID: String?
    /// Photos highlighted in the filmstrip (click, ⇧-click for a range, ⌘-click to add or remove).
    @State private var highlighted = Set<String>()
    /// Where a ⇧-click range starts.
    @State private var anchorID: String?
    @State private var hoverImportHeader = false
    @State private var hoverFolder = false
    @State private var hoverImport = false
    @AppStorage("importFolderPath") private var importFolderPath = ""
    @AppStorage("writeXMP") private var writeXMP = true
    @AppStorage("writeRRData") private var writeRRData = false
    @AppStorage("importFileTypes") private var fileTypes: ImportFileTypes = .both
    @AppStorage("showSettingsSection") private var showSettings = true
    @AppStorage("showImportSection") private var showImportOptions = true

    private let sidebarWidth: CGFloat = 340

    private var focusedShot: Shot? { camera.shots.first { $0.id == focusedID } }
    private var folderLabel: String {
        importFolderPath.isEmpty ? "Choose folder…" : (importFolderPath as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: Theme.gap) {
            // Traffic lights – full width
            TitleBar(windowRef: windowRef, status: camera.status)

            HStack(alignment: .top, spacing: Theme.gap) {
                // Left: preview and filmstrip
                VStack(spacing: Theme.gap) {
                    Group {
                        if let shot = focusedShot {
                            DetailView(shot: shot)
                        } else {
                            placeholder
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .panel()

                    Filmstrip(selection: $selection, focusedID: $focusedID,
                              highlighted: highlighted, onClick: click)
                        .frame(height: Filmstrip.height)
                        .panel()
                }

                // Right: settings, import options and import
                sidebar
                    .frame(width: sidebarWidth)
            }
        }
        .padding(Theme.gap)
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .background(WindowConfigurator(ref: windowRef))
        .foregroundStyle(Theme.text)
        .font(Theme.font(18))
        .preferredColorScheme(.dark)
        .focusedSceneValue(\.selectionActions, SelectionActions(selectAll: selectAll, selectNone: selectNone))
        .background(
            // Space checks or unchecks the highlighted photos for import.
            Button("", action: toggleChecksForHighlighted)
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
        .onAppear { focusFirstIfNeeded(camera.shots.map(\.id)) }
        .onChange(of: camera.shots.map(\.id)) { ids in focusFirstIfNeeded(ids) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: Theme.gap) {
            ScrollView(.vertical, showsIndicators: false) {
                settingsSection
            }

            importStack
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        if let shot = focusedShot {
            ShotSettingsSection(shot: shot, isExpanded: $showSettings)
        } else {
            SidebarSection(title: "Camera Settings", isExpanded: $showSettings) {
                Text("No photo selected.")
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }

    /// Import options (expand/collapse) and import in one stack.
    private var importStack: some View {
        VStack(spacing: 0) {
            importHeader
            Collapsible(isExpanded: showImportOptions) {
                VStack(spacing: 0) {
                    SectionDivider()
                    importOptions
                        .padding(14)
                }
            }
            SectionDivider()
            importActions
                .padding(14)
        }
        .clipped()
        .panel()
    }

    /// "Import Options" and the line "Save Lightroom, RapidRAW to [folder] path".
    /// Clicking the header expands/collapses, clicking the folder picks a new folder.
    private var importHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Options")
                    .font(Theme.font(18, bold: true))
                    .foregroundStyle(Theme.text)

                Text(saveLabel)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)

                // The folder on its own row
                Button(action: chooseFolder) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        AppIcon(kind: .folder, hovered: hoverFolder, textSize: 15)
                        if !importFolderPath.isEmpty {
                            Text((importFolderPath as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.text)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoverFolder = $0 }
                .help(importFolderPath.isEmpty ? "Choose a folder to import to" : "Change folder (\(importFolderPath))")
            }

            Spacer(minLength: 8)

            AppIcon(kind: .chevron, hovered: hoverImportHeader, expanded: showImportOptions)
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hoverImportHeader = $0 }
        .onTapGesture {
            showImportOptions.toggle()
        }
    }

    private var canImport: Bool {
        !selection.isEmpty && !importFolderPath.isEmpty && !camera.isBusy
    }

    /// "Save Lightroom, RapidRAW to" – depending on which sidecars are selected.
    private var saveLabel: String {
        var parts: [String] = []
        if fileTypes.includesRAW {
            if writeXMP { parts.append("Lightroom") }
            if writeRRData { parts.append("RapidRAW") }
        }
        return parts.isEmpty ? "Save to" : "Save \(parts.joined(separator: ", ")) to"
    }

    private var importOptions: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            SlidingPicker(
                options: ImportFileTypes.allCases.map { ($0, $0.title) },
                selection: $fileTypes
            )
            .padding(.bottom, 4)

            sidecarToggles
                .disabled(!fileTypes.includesRAW)
                .opacity(fileTypes.includesRAW ? 1 : 0.35)
                .help(fileTypes.includesRAW ? "" : "Sidecars are only created for RAW files")
        }
    }

    private var sidecarToggles: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            SidecarToggle(title: "Lightroom", isOn: $writeXMP,
                          fullWidth: true, fileExtension: ".xmp")
            SidecarToggle(title: "RapidRAW", isOn: $writeRRData,
                          fullWidth: true, fileExtension: ".rrdata")
        }
    }

    /// Always visible: number selected and the import button.
    private var importActions: some View {
        VStack(spacing: 12) {
            Text("\(selection.count) of \(camera.shots.count) selected")
                .font(Theme.font(18))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: startImport) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if camera.isBusy {
                        ProgressView().controlSize(.small)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
                    } else {
                        AppIcon(kind: .importArrow, hovered: hoverImport && canImport)
                    }
                    Text(camera.isBusy ? "Importing…" : "Import \(selection.count)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DarkButtonStyle())
            .disabled(!canImport)
            .onHover { hoverImport = $0 }
            .keyboardShortcut("i", modifiers: .command)
            .help(importFolderPath.isEmpty ? "Choose a folder under Import Options first" : "Import selected photos (⌘I)")
        }
    }


    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: camera.camera == nil ? "camera" : "photo.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(camera.camera == nil
                 ? "Connect your camera in USB CARD READER mode."
                 : "Pick a photo in the filmstrip below.")
                .font(Theme.font(18))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectAll() { selection = Set(camera.shots.map(\.id)) }
    private func selectNone() { selection.removeAll() }

    private func focusFirstIfNeeded(_ ids: [String]) {
        highlighted.formIntersection(ids)
        if let id = focusedID, ids.contains(id) { return }
        focusedID = ids.first
        anchorID = ids.first
        highlighted = Set(ids.prefix(1))
    }

    // MARK: Filmstrip selection

    /// Click: show and highlight one photo. ⇧-click: highlight the range from the last click.
    /// ⌘-click: add or remove a single photo (⇧⌘-click adds a range).
    private func click(_ id: String) {
        let flags = NSEvent.modifierFlags
        let ids = camera.shots.map(\.id)

        if flags.contains(.shift),
           let anchor = anchorID,
           let a = ids.firstIndex(of: anchor),
           let b = ids.firstIndex(of: id) {
            let range = Set(ids[min(a, b)...max(a, b)])
            if flags.contains(.command) { highlighted.formUnion(range) } else { highlighted = range }
            focusedID = id
        } else if flags.contains(.command) {
            if highlighted.contains(id) {
                highlighted.remove(id)
                if focusedID == id, let next = ids.first(where: highlighted.contains) { focusedID = next }
            } else {
                highlighted.insert(id)
                focusedID = id
            }
            anchorID = id
        } else {
            highlighted = [id]
            focusedID = id
            anchorID = id
        }
    }

    /// Checks all highlighted photos for import, or unchecks them if they are all checked already.
    private func toggleChecksForHighlighted() {
        let targets = highlighted.isEmpty ? Set([focusedID].compactMap { $0 }) : highlighted
        guard !targets.isEmpty else { return }
        if targets.isSubset(of: selection) {
            selection.subtract(targets)
        } else {
            selection.formUnion(targets)
        }
    }

    // MARK: Folder and import

    private func chooseFolder() {
        if let path = pickFolder() { importFolderPath = path }
    }

    private enum ExistingChoice { case overwrite, skip, cancel }

    private func askAboutExisting(_ names: [String], in folder: URL) -> ExistingChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = names.count == 1
            ? "\(names[0]) already exists in \(folder.lastPathComponent)."
            : "\(names.count) files already exist in \(folder.lastPathComponent)."
        let shown = names.prefix(8).joined(separator: "\n")
        let more = names.count > 8 ? "\n…and \(names.count - 8) more" : ""
        alert.informativeText = (names.count > 1 ? shown + more + "\n\n" : "")
            + "Do you want to replace them with the files from the camera? "
            + "Existing XMP and rrdata files are kept either way."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"   // Esc cancels
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skip
        default: return .cancel
        }
    }

    private func pickFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func startImport() {
        let selected = camera.shots.filter { selection.contains($0.id) }
        let folder = URL(fileURLWithPath: importFolderPath, isDirectory: true)
        var overwrite = false
        let existing = camera.existingFiles(for: selected, in: folder, fileTypes: fileTypes)
        if !existing.isEmpty {
            switch askAboutExisting(existing, in: folder) {
            case .overwrite: overwrite = true
            case .skip: overwrite = false
            case .cancel: return
            }
        }

        Task {
            await camera.importShots(selected, to: folder, overwrite: overwrite,
                                     fileTypes: fileTypes,
                                     writeXMP: writeXMP, writeRRData: writeRRData)
            selection.removeAll()
        }
    }
}

// MARK: - Camera settings (accordion)

struct ShotSettingsSection: View {
    @ObservedObject var shot: Shot
    @Binding var isExpanded: Bool

    var body: some View {
        SidebarSection(title: "Camera Settings",
                       isExpanded: $isExpanded,
                       summary: shot.settings?.filmSimulation) {
            if let rows = shot.settings?.rows, !rows.isEmpty {
                VStack(spacing: 9) {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .font(Theme.font(16))
                                .foregroundStyle(Theme.tertiaryText)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(Theme.font(18))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            } else {
                Text(shot.preview == nil ? "Reading settings…" : "No camera settings found.")
                    .font(Theme.font(16))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

// MARK: - Filmstrip

struct Filmstrip: View {
    @EnvironmentObject private var camera: CameraService
    @Binding var selection: Set<String>
    @Binding var focusedID: String?
    let highlighted: Set<String>
    let onClick: (String) -> Void

    /// The same spacing on all sides around the thumbnails.
    static let inset: CGFloat = 14
    static let height: CGFloat = ShotCell.totalHeight + 2 * inset

    var body: some View {
        if camera.shots.isEmpty {
            Text(camera.camera == nil ? "No camera connected" : "No photos on the card")
                .font(Theme.font(18))
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: Theme.gap) {
                        ForEach(camera.shots) { shot in
                            ShotCell(
                                shot: shot,
                                isSelected: selection.contains(shot.id),
                                isFocused: highlighted.contains(shot.id),
                                focus: { onClick(shot.id) },
                                toggle: { toggle(shot.id) }
                            )
                            .id(shot.id)
                            .onAppear { camera.loadThumbnail(for: shot) }
                        }
                    }
                    .padding(Self.inset)
                }
                .onChange(of: focusedID) { id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

struct ShotCell: View {
    @ObservedObject var shot: Shot
    let isSelected: Bool
    let isFocused: Bool
    let focus: () -> Void
    let toggle: () -> Void

    private let height: CGFloat = 109
    /// Follows the photo: wide for landscape, narrow for portrait.
    private var width: CGFloat { (height * aspectRatio).rounded() }

    /// Width / height of the photo, taken from its thumbnail only.
    /// The thumbnail is decoded with its rotation applied, so portrait photos come out tall.
    /// Using only the thumbnail keeps the filmstrip stable: nothing is re-measured when a
    /// photo is selected, and no size has to be asked from the camera for every cell.
    private var aspectRatio: CGFloat {
        if let aspect = shot.displayAspect { return aspect }
        guard let thumb = shot.thumbnail, thumb.width > 0, thumb.height > 0 else { return 3 / 2 }
        return CGFloat(thumb.width) / CGFloat(thumb.height)
    }
    private static let labelHeight: CGFloat = 19
    private static let labelSpacing: CGFloat = 5
    static let totalHeight: CGFloat = 109 + labelSpacing + labelHeight

    var body: some View {
        // Two separate buttons (not nested): the cell shows the photo, the checkbox selects it.
        ZStack(alignment: .topTrailing) {
            Button(action: focus) { cellContent }
                .buttonStyle(.plain)
                .help("Show \(shot.displayName)")

            Button(action: toggle) {
                GreenCheckbox(isOn: isSelected, color: .white, checkColor: .white, size: 18, filled: false)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Deselect" : "Select for import")
        }
    }

    private var cellContent: some View {
        VStack(alignment: .leading, spacing: Self.labelSpacing) {
            // The whole card – photo, rounded corners and selection stroke – turns when the
            // thumbnail gets its correct orientation. While turning, the card is laid out
            // sideways (width and height swapped) so that after 90° it fits the cell exactly.
            let turned = shot.thumbnailRotation != 0
            card
                .frame(width: turned ? height : width, height: turned ? width : height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.thumbCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.thumbCorner, style: .continuous)
                        .strokeBorder(isFocused ? Theme.text : Color.clear, lineWidth: 2)
                )
                .rotationEffect(.degrees(shot.thumbnailRotation))
                .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                FileTypeTag(shot: shot)
                    .padding(6)
            }

            // The file type is shown as a tag on the thumbnail, so the name always fits.
            fileName
                .frame(maxWidth: .infinity, alignment: .leading)
            // SF Mono: sans-serif, fixed width.
            .fontDesign(.monospaced)
            .lineLimit(1)
            .frame(width: width, height: Self.labelHeight)
        }
        .contentShape(Rectangle())
    }

    /// The photo itself. The black bars the camera adds are trimmed when the thumbnail loads;
    /// when the sharper preview replaces it, the new image fades in.
    private var card: some View {
        ZStack {
            Color.black
            if let thumb = shot.thumbnail {
                Image(decorative: thumb, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .id(ObjectIdentifier(thumb))
                    .transition(.opacity)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var fileName: some View {
        Text(shot.displayName)
            .font(.system(size: 14))
            .foregroundStyle(isFocused ? Theme.text : Theme.secondaryText)
    }
}

// MARK: - File type tag

/// Tiny file-type tag in the corner of a thumbnail. RAW + JPEG shows two stacked tags:
/// RAW on top, JPG peeking out below and to the right.
struct FileTypeTag: View {
    @ObservedObject var shot: Shot

    private let stackOffset: CGFloat = 3
    /// Solid dark gray with a thin light gray stroke – the same for both tags in a stack.
    private let fill = Color(white: 0.16)
    private let stroke = Color(white: 0.45)

    var body: some View {
        if shot.raw != nil && shot.jpeg != nil {
            ZStack(alignment: .topLeading) {
                tag("JPG", showsText: false)
                    .offset(x: stackOffset, y: stackOffset)
                tag("RAW")
            }
            // The offset does not take up layout space, so keep the stack inside the corner.
            .padding([.trailing, .bottom], stackOffset)
            .help("RAW + JPEG")
        } else if shot.raw != nil {
            tag("RAW").help("RAW")
        } else if shot.jpeg != nil {
            tag("JPG").help("JPEG")
        } else {
            tag(shot.kindLabel)
        }
    }

    private func tag(_ text: String, showsText: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(showsText ? Color.white : Color.clear)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: 0.75))
    }
}

// MARK: - Preview

struct DetailView: View {
    @EnvironmentObject private var camera: CameraService
    @ObservedObject var shot: Shot
    /// `nil` = fit to the stack. Otherwise zoom where 1.0 = one image pixel per screen pixel (100 %).
    @State private var fixedZoom: Double?
    /// How far the image center is offset from the viewport center (points).
    @State private var pan: CGSize = .zero
    /// The image viewport (the stack minus margins).
    @State private var viewport: CGSize = .zero
    @State private var loadingFull = false

    private let sidePadding: CGFloat = 14
    private let bottomPadding: CGFloat = 14
    private var backingScale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    /// E.g. "October 22, 2026 at 4:36 PM".
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(shot.displayName)
                            .font(Theme.font(19, bold: true))
                        Text(shot.kindLabel)
                            .font(Theme.font(16))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let date = shot.date {
                        Text(Self.dateFormatter.string(from: date))
                            .font(Theme.font(16))
                            .foregroundStyle(Theme.secondaryText)
                            .help("When the photo was taken")
                    }
                }
                Spacer()
                if pixelSize != nil {
                    ZoomControl(
                        zoom: zoom,
                        range: zoomRange,
                        onChange: { setZoom($0, around: viewportCenter) },
                        onFit: { fit() }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            imageArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { viewport = geo.size }
                            .onChange(of: geo.size) { size in
                                viewport = size
                                pan = clamped(pan, zoom: zoom)
                            }
                    }
                )
                .padding(.horizontal, sidePadding)
                .padding(.bottom, bottomPadding)
        }
        .task(id: shot.id) {
            fit()
            await camera.loadPreview(for: shot)
        }
        .onChange(of: zoom) { _ in loadFullIfNeeded() }
    }

    // MARK: Image

    @ViewBuilder
    private var imageArea: some View {
        if let image = shot.fullImage ?? shot.preview ?? shot.thumbnail, let size = displaySize(zoom: zoom) {
            // Color.clear takes exactly the space the stack offers. The image is an overlay,
            // so however large it gets when zooming, it never affects the rest of the UI.
            Color.clear
                .overlay(
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(zoom >= 1 ? .none : .high)
                        .frame(width: size.width, height: size.height)
                        .offset(fixedZoom == nil ? .zero : pan)
                        // clipped() only clips the drawing, not hit-testing: a zoomed-in image
                        // would otherwise catch clicks on the filmstrip below it.
                        // Mouse and trackpad input is handled by ZoomInputView instead.
                        .allowsHitTesting(false)
                )
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if loadingFull {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(Circle().fill(Theme.panel.opacity(0.8)))
                            .padding(8)
                            .help("Loading the original from the camera")
                    }
                }
                .overlay(
                    ZoomInputView(
                        onScroll: handleScroll,
                        onMagnify: { point, magnification in
                            setZoom(zoom * (1 + magnification), around: point)
                        },
                        onDrag: { delta in
                            guard fixedZoom != nil else { return }
                            pan = clamped(CGSize(width: pan.width + delta.width,
                                                 height: pan.height + delta.height), zoom: zoom)
                        }
                    )
                )
        } else {
            ProgressView()
        }
    }

    // MARK: Zoom

    /// The image size at full resolution. Before download: the preview's aspect ratio
    /// and the original's long edge as reported by the camera.
    private var pixelSize: CGSize? {
        if let full = shot.fullImage {
            return CGSize(width: full.width, height: full.height)
        }
        guard let base = shot.preview ?? shot.thumbnail, base.width > 0, base.height > 0 else { return nil }
        let aspect = CGFloat(base.width) / CGFloat(base.height)
        var long = CGFloat(max(base.width, base.height))
        if let file = shot.jpeg ?? shot.raw {
            long = max(long, CGFloat(max(file.width, file.height)))
        }
        return aspect >= 1
            ? CGSize(width: long, height: long / aspect)
            : CGSize(width: long * aspect, height: long)
    }

    /// The image size on screen (points) at a given zoom.
    private func displaySize(zoom z: Double) -> CGSize? {
        guard let px = pixelSize else { return nil }
        return CGSize(width: px.width / backingScale * z, height: px.height / backingScale * z)
    }

    /// Zoom that makes the image fill the stack. Changes when the window is resized.
    private var fitZoom: Double {
        guard let px = pixelSize, px.width > 0, px.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        return Double(min(viewport.width / (px.width / backingScale),
                          viewport.height / (px.height / backingScale)))
    }

    private var zoomRange: ClosedRange<Double> { min(0.05, fitZoom)...max(4.0, fitZoom) }
    private var zoom: Double { fixedZoom ?? fitZoom }
    private var viewportCenter: CGPoint { CGPoint(x: viewport.width / 2, y: viewport.height / 2) }

    private func fit() {
        fixedZoom = nil
        pan = .zero
    }

    /// Zooms so the point under the cursor (or the center) stays in place.
    private func setZoom(_ newZoom: Double, around point: CGPoint) {
        let old = zoom
        let z = min(max(newZoom, zoomRange.lowerBound), zoomRange.upperBound)
        // Close to "fit" – snap to it.
        if abs(z - fitZoom) / fitZoom < 0.015 {
            fit()
            return
        }
        let anchor = CGSize(width: point.x - viewport.width / 2, height: point.y - viewport.height / 2)
        let current = fixedZoom == nil ? .zero : pan
        let factor = CGFloat(z / old)
        let newPan = CGSize(width: anchor.width - (anchor.width - current.width) * factor,
                            height: anchor.height - (anchor.height - current.height) * factor)
        fixedZoom = z
        pan = clamped(newPan, zoom: z)
    }

    /// Keeps the image inside the viewport (centered if it is smaller).
    private func clamped(_ p: CGSize, zoom z: Double) -> CGSize {
        guard let size = displaySize(zoom: z) else { return .zero }
        let maxX = max(0, (size.width - viewport.width) / 2)
        let maxY = max(0, (size.height - viewport.height) / 2)
        return CGSize(width: min(max(p.width, -maxX), maxX),
                      height: min(max(p.height, -maxY), maxY))
    }

    /// Mouse wheel and two-finger swipe on the trackpad zoom around the cursor,
    /// regardless of the natural scrolling setting:
    /// - Trackpad: swipe down (towards you) zooms in, swipe up zooms out.
    /// - Mouse wheel: roll away from you zooms in, towards you zooms out.
    /// The image is moved by clicking and dragging.
    private func handleScroll(_ e: ScrollInput) {
        guard e.deltaY != 0 else { return }
        // Positive = the wheel or fingers moved away from you (up).
        var awayFromYou = e.deltaY
        if e.isInverted { awayFromYou = -awayFromYou }
        let zoomIn = e.isPrecise ? -awayFromYou : awayFromYou
        let step = e.isPrecise ? 0.01 : 0.12
        setZoom(zoom * exp(Double(zoomIn) * step), around: e.location)
    }

    /// Loads the original when the preview is not enough for the current zoom.
    private func loadFullIfNeeded() {
        guard fixedZoom != nil, shot.fullImage == nil, !loadingFull,
              let preview = shot.preview, let px = pixelSize else { return }
        let coverage = Double(max(preview.width, preview.height)) / Double(max(px.width, px.height))
        guard zoom > coverage else { return }
        loadingFull = true
        Task {
            await camera.loadFullResolution(for: shot)
            loadingFull = false
        }
    }
}

// MARK: - Mouse and trackpad

struct ScrollInput {
    let location: CGPoint
    let deltaX: CGFloat
    let deltaY: CGFloat
    /// Trackpad/Magic Mouse (`true`) or a regular mouse wheel (`false`).
    let isPrecise: Bool
    /// Natural scrolling enabled.
    let isInverted: Bool
    let command: Bool
}

/// Captures scroll, pinch and drag over the image (SwiftUI has no scroll wheel API on macOS 13).
struct ZoomInputView: NSViewRepresentable {
    var onScroll: (ScrollInput) -> Void
    var onMagnify: (CGPoint, CGFloat) -> Void
    var onDrag: (CGSize) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }

    func updateNSView(_ view: InputView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onDrag = onDrag
    }

    final class InputView: NSView {
        var onScroll: ((ScrollInput) -> Void)?
        var onMagnify: ((CGPoint, CGFloat) -> Void)?
        var onDrag: ((CGSize) -> Void)?

        override var isFlipped: Bool { true }   // y down, as in SwiftUI
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func point(_ event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(ScrollInput(
                location: point(event),
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                isPrecise: event.hasPreciseScrollingDeltas,
                isInverted: event.isDirectionInvertedFromDevice,
                command: event.modifierFlags.contains(.command)
            ))
        }

        override func magnify(with event: NSEvent) {
            onMagnify?(point(event), event.magnification)
        }

        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(CGSize(width: event.deltaX, height: event.deltaY))
        }

        override func mouseUp(with event: NSEvent) {
            NSCursor.pop()
        }
    }
}

/// "Zoom [slider] xx %". Double-clicking the handle fits the image to the stack.
struct ZoomControl: View {
    let zoom: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void
    let onFit: () -> Void

    private let trackWidth: CGFloat = 150
    private let handleSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            Text("Zoom")
                .font(Theme.font(16))
                .foregroundStyle(Theme.secondaryText)

            slider

            Text("\(Int((zoom * 100).rounded())) %")
                .font(Theme.font(16))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var slider: some View {
        let x = position(for: zoom)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.border)
                .frame(height: 3)
            Capsule()
                .fill(Theme.secondaryText)
                .frame(width: x + handleSize / 2, height: 3)
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .offset(x: x)
                .onTapGesture(count: 2, perform: onFit)
                .help("Double-click to fit the image")
        }
        .frame(width: trackWidth, height: 20)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { onChange(value(at: $0.location.x)) }
        )
    }

    // Logarithmic scale: 25→50 % is as far as 100→200 %.
    private func position(for z: Double) -> CGFloat {
        let lo = log(range.lowerBound), hi = log(range.upperBound)
        guard hi > lo else { return 0 }
        let clamped = min(max(z, range.lowerBound), range.upperBound)
        return CGFloat((log(clamped) - lo) / (hi - lo)) * (trackWidth - handleSize)
    }

    private func value(at x: CGFloat) -> Double {
        let t = Double(min(max((x - handleSize / 2) / (trackWidth - handleSize), 0), 1))
        let lo = log(range.lowerBound), hi = log(range.upperBound)
        return exp(lo + t * (hi - lo))
    }
}

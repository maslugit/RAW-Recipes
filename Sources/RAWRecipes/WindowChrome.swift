import SwiftUI
import AppKit

/// Keeps track of the window so our own traffic lights can close, minimize and toggle
/// full screen, and knows whether the window is active (gray lights when it is not).
final class WindowRef: ObservableObject {
    weak var window: NSWindow?
    @Published var isKey = true
    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        removeObservers()

        let nc = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(nc.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                self?.isKey = window?.isKeyWindow ?? false
            })
        }
        // SwiftUI and AppKit can restore the system title bar (and its buttons) when the window
        // becomes active, is resized or leaves full screen – so the chrome is re-applied then.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didExitFullScreenNotification, NSWindow.didResizeNotification] {
            observers.append(nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.applyChrome()
            })
        }
        isKey = window.isKeyWindow
        applyChrome()
    }

    /// Transparent, empty title bar and no system traffic lights – we draw our own in the title stack.
    func applyChrome() {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        if window.toolbar != nil { window.toolbar = nil }
        window.backgroundColor = Theme.nsBackground
        window.appearance = NSAppearance(named: .darkAqua)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    deinit { removeObservers() }
}

/// Makes the title bar transparent and hides the system traffic lights – we draw our own in the title stack.
struct WindowConfigurator: NSViewRepresentable {
    let ref: WindowRef

    func makeNSView(context: Context) -> NSView { ConfiguratorView(ref: ref) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ConfiguratorView: NSView {
        private let ref: WindowRef

        init(ref: WindowRef) {
            self.ref = ref
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            DispatchQueue.main.async { [ref, weak window] in
                if let window { ref.attach(window) }
            }
        }
    }
}

/// Area that moves the window when dragged and zooms on double-click – like a title bar.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

// MARK: - Title stack

struct TitleBar: View {
    @ObservedObject var windowRef: WindowRef
    let status: String

    var body: some View {
        HStack(spacing: 16) {
            TrafficLights(windowRef: windowRef)

            Text("RAW Recipes")
                .font(Theme.font(17, bold: true))
                .foregroundStyle(Theme.text)
                .allowsHitTesting(false)

            Text(status)
                .font(Theme.font(16))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .allowsHitTesting(false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(WindowDragArea())
        .panel()
    }
}

struct TrafficLights: View {
    @ObservedObject var windowRef: WindowRef
    @State private var hovering = false

    private enum Kind: CaseIterable {
        case close, minimize, zoom

        var color: Color {
            switch self {
            case .close: return Color(red: 1.00, green: 0.37, blue: 0.34)
            case .minimize: return Color(red: 1.00, green: 0.74, blue: 0.18)
            case .zoom: return Color(red: 0.16, green: 0.78, blue: 0.25)
            }
        }

        var symbol: String {
            switch self {
            case .close: return "xmark"
            case .minimize: return "minus"
            case .zoom: return "arrow.up.left.and.arrow.down.right"
            }
        }

        var help: String {
            switch self {
            case .close: return "Close"
            case .minimize: return "Minimize"
            case .zoom: return "Full Screen"
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Kind.allCases, id: \.self) { kind in
                Button { perform(kind) } label: {
                    ZStack {
                        Circle()
                            .fill(windowRef.isKey || hovering ? kind.color : Color(white: 0.30))
                        Circle()
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                        if hovering {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 6.5, weight: .black))
                                .foregroundStyle(Color.black.opacity(0.6))
                        }
                    }
                    .frame(width: 12, height: 12)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(kind.help)
            }
        }
        .onHover { hovering = $0 }
    }

    private func perform(_ kind: Kind) {
        guard let window = windowRef.window else { return }
        switch kind {
        case .close: window.performClose(nil)
        case .minimize: window.miniaturize(nil)
        case .zoom: window.toggleFullScreen(nil)
        }
    }
}

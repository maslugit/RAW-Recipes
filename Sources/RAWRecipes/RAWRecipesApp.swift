import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when running straight from the Swift package / Xcode without an .app bundle.
        NSApp.setActivationPolicy(.regular)
        // Dark mode first: alerts, menus and the folder picker are dark too.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // A built .app gets its icon from Info.plist. When running from Xcode there is
        // no .app bundle, so set the Dock icon from the package resources instead.
        if Bundle.main.url(forResource: "AppIcon", withExtension: "icns") == nil,
           let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct RAWRecipesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var camera = CameraService()

    init() {
        AppFont.register()
    }

    var body: some Scene {
        WindowGroup("RAW Recipes") {
            ContentView()
                .environmentObject(camera)
                .frame(minWidth: 960, minHeight: 720)
        }
        // No system title bar – the app draws its own title stack with traffic lights.
        .windowStyle(.hiddenTitleBar)
        .commands {
            SelectionCommands()
            CommandMenu("Camera") {
                Button("Test PTP Connection") {
                    Task { await camera.testPTPConnection() }
                }
            }
        }
    }
}

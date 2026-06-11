import SwiftUI
import AppKit

@main
struct ClipboardMgrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = ClipboardStore.shared

    var body: some Scene {
        MenuBarExtra("Clipboard Manager", systemImage: "doc.on.clipboard") {
            ContentView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }

    // "Opening" the already-running app (Quicksilver, Spotlight, `open -a`)
    // lands here — toggle the floating panel instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        FloatingPanelController.shared.toggle()
        return false
    }
}

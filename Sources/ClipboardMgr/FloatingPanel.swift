import AppKit
import SwiftUI

/// Borderless, non-activating panel (Spotlight-style). Because it never
/// activates the app, the window you were working in keeps focus — copy an
/// entry and Cmd-V pastes right where you were.
final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        FloatingPanelController.shared.hide()
    }

    override func resignKey() {
        super.resignKey()
        FloatingPanelController.shared.hide()
    }
}

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()
    private var panel: FloatingPanel?

    /// The last app the user was in before opening the panel. Tracked via
    /// NSWorkspace notifications so launchers (Quicksilver, Spotlight) that
    /// briefly become frontmost at invocation time don't overwrite it.
    var previousApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                // Don't overwrite while the panel is open (launcher firing mid-session).
                if FloatingPanelController.shared.panel == nil {
                    FloatingPanelController.shared.previousApp = app
                }
            }
        }
    }

    func toggle() {
        if panel != nil { hide() } else { show() }
    }

    func show() {
        hide()
        let root = ContentView(
            store: .shared,
            isFloating: true,
            onClose: { FloatingPanelController.shared.hide() }
        )
        let panel = FloatingPanel(contentView: NSHostingView(rootView: root))
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2 + frame.height * 0.12
            ))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
    }
}

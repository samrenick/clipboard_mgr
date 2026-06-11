import AppKit
import CoreGraphics
import ApplicationServices

enum PasteHelper {
    /// Returns the AX-focused UI element for the given app (e.g. URL bar).
    static func focusedElement(for app: NSRunningApplication?) -> AXUIElement? {
        guard AXIsProcessTrusted(), let pid = app?.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &element) == .success else {
            return nil
        }
        return (element as! AXUIElement)
    }

    /// Activates `app` and sends Cmd+V directly to its process.
    @MainActor
    static func paste(into app: NSRunningApplication?) {
        guard AXIsProcessTrusted(), let app else { return }
        let pid = app.processIdentifier
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sendCmdV(to: pid)
        }
    }

    private static func sendCmdV(to pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}

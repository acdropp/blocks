import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Closing the main window would normally quit a SwiftUI app. The
    // global quick-add hotkey needs Blocks running even with no window
    // open, so keep it alive; quit via Cmd-Q or the Dock menu instead.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

import SwiftUI
import AppKit

/// SwiftUI's List has no direct API on macOS to turn off the native
/// selection highlight while keeping selection itself (clicking, keyboard
/// nav, Delete key) working. This is an invisible helper, inserted once as
/// a List row, that walks up the view hierarchy to find the List's backing
/// NSTableView and disables its highlight drawing — so the card design can
/// paint its own selected-row color (Palette.selectedRow) with nothing
/// underneath fighting it.
struct SelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.disableSelectionHighlight(startingFrom: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func disableSelectionHighlight(startingFrom view: NSView) {
        var current: NSView? = view
        while let candidate = current {
            if let tableView = candidate as? NSTableView {
                tableView.selectionHighlightStyle = .none
                return
            }
            current = candidate.superview
        }
    }
}

/// SwiftUI has no API on macOS for coloring the title bar (the strip with
/// the traffic-light buttons) — it's owned by NSWindow, not the content
/// view. This invisible helper, inserted once as a List row, reaches the
/// enclosing NSWindow and makes its title bar transparent so the window's
/// own background color (set to Palette.titleBar) shows through there.
struct TitleBarColorizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TitleBarAccessorView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A one-shot .async dispatch (the technique SelectionHighlightRemover
/// uses to reach a nearby NSTableView ancestor) turned out too early to
/// reach all the way up to the actual NSWindow — .window was still nil
/// when it ran. viewDidMoveToWindow() is the AppKit lifecycle hook that
/// fires at the exact moment this view is actually attached to a window,
/// so it removes that timing guesswork entirely.
private final class TitleBarAccessorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // titlebarAppearsTransparent alone isn't enough — without
        // fullSizeContentView, the title bar isn't actually rendering the
        // window's background color at all, regardless of transparency.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Palette.titleBar)
    }
}

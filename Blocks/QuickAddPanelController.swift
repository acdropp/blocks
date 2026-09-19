import AppKit
import SwiftUI
import SwiftData
import Combine

/// Owns the small floating quick-add panel shown by the global hotkey.
/// Briefly activates Blocks so the panel can reliably receive keystrokes
/// (a non-activating panel looked right but never actually got keyboard
/// focus), then reactivates whatever app was frontmost before, once the
/// panel closes.
final class QuickAddPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let fieldModel = QuickAddFieldModel()
    private let modelContext: ModelContext
    private let tasksManager: GoogleTasksManager
    private var previousApp: NSRunningApplication?

    init(modelContext: ModelContext, tasksManager: GoogleTasksManager) {
        self.modelContext = modelContext
        self.tasksManager = tasksManager
    }

    /// Shows the panel, or closes it if it's already open.
    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = self.panel ?? makePanel()
        self.panel = panel

        if let screenFrame = NSScreen.main?.visibleFrame {
            let size = panel.frame.size
            let origin = CGPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2 + screenFrame.height * 0.15
            )
            panel.setFrameOrigin(origin)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        fieldModel.isFocused = true
    }

    private func hide() {
        fieldModel.title = ""
        panel?.orderOut(nil)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: QuickAddField(
            model: fieldModel,
            onSubmit: { [weak self] title in self?.createTask(title: title) },
            onCancel: { [weak self] in self?.hide() }
        ))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 56),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Add"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )

        return panel
    }

    @objc private func panelDidResignKey(_ notification: Notification) {
        hide()
    }

    // Route the red traffic-light button through the same hide() path
    // (hidden, not deallocated — isReleasedWhenClosed is false) instead
    // of letting AppKit actually close the window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func createTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hide()
            return
        }

        let item = TodoItem(title: trimmed)
        item.lastModified = Date()
        item.manualOrder = nextManualOrder()
        modelContext.insert(item)
        print("[Hotkey] Quick-added task: \"\(trimmed)\"")
        Task { await tasksManager.pushNewTask(item) }
        hide()
    }

    private func nextManualOrder() -> Double {
        let descriptor = FetchDescriptor<TodoItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return (items.compactMap(\.manualOrder).max() ?? -1) + 1
    }
}

private final class QuickAddFieldModel: ObservableObject {
    @Published var title = ""
    @Published var isFocused = false
}

private struct QuickAddField: View {
    @ObservedObject var model: QuickAddFieldModel
    @FocusState private var isFocused: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        TextField("Add a task", text: $model.title)
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .padding(16)
            .focused($isFocused)
            .onChange(of: model.isFocused) { _, newValue in
                if newValue {
                    isFocused = true
                    model.isFocused = false
                }
            }
            .onSubmit {
                onSubmit(model.title)
                model.title = ""
            }
            .background {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
    }
}

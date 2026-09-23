import SwiftUI
import SwiftData
import AppKit
import GoogleSignIn

extension Notification.Name {
    static let blocksRefresh = Notification.Name("blocksRefresh")
    static let blocksFind = Notification.Name("blocksFind")
    static let blocksMoveToTopPriorities = Notification.Name("blocksMoveToTopPriorities")
    static let blocksMoveToOther = Notification.Name("blocksMoveToOther")
    static let blocksTogglePersonalSection = Notification.Name("blocksTogglePersonalSection")
}

@main struct BlocksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var authManager: AuthManager
    @StateObject private var tasksManager: GoogleTasksManager
    @StateObject private var calendarManager: GoogleCalendarManager
    @StateObject private var fathomManager: FathomManager

    private let container: ModelContainer
    private let hotKeyManager: HotKeyManager
    private let quickAddController: QuickAddPanelController

    init() {
        let authManager = AuthManager()
        _authManager = StateObject(wrappedValue: authManager)
        let tasksManager = GoogleTasksManager(authManager: authManager)
        _tasksManager = StateObject(wrappedValue: tasksManager)
        _calendarManager = StateObject(wrappedValue: GoogleCalendarManager(authManager: authManager))
        _fathomManager = StateObject(wrappedValue: FathomManager())

        let container = try! ModelContainer(for: TodoItem.self, InboxItem.self, SeenFathomItem.self)
        self.container = container

        let quickAddController = QuickAddPanelController(modelContext: container.mainContext, tasksManager: tasksManager)
        self.quickAddController = quickAddController

        let hotKeyManager = HotKeyManager { quickAddController.toggle() }
        self.hotKeyManager = hotKeyManager
        if let registrationError = hotKeyManager.register() {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Quick-Add Hotkey Unavailable"
                alert.informativeText = registrationError
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(tasksManager)
                .environmentObject(calendarManager)
                .environmentObject(fathomManager)
                .onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Find") {
                    NotificationCenter.default.post(name: .blocksFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .blocksRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Task") {
                Button("Move to Top Priorities") {
                    NotificationCenter.default.post(name: .blocksMoveToTopPriorities, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Move to Other To-dos") {
                    NotificationCenter.default.post(name: .blocksMoveToOther, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button("Toggle Personal Section") {
                    NotificationCenter.default.post(name: .blocksTogglePersonalSection, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(tasksManager)
                .environmentObject(calendarManager)
                .environmentObject(fathomManager)
                // Settings is a separate Scene from the main window, so it
                // needs this too — without it, native controls (text
                // fields, pickers) follow the system's actual Dark Mode
                // setting regardless of our own light-only card design.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

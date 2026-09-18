import SwiftUI
import SwiftData
import GoogleSignIn

extension Notification.Name {
    static let blocksRefresh = Notification.Name("blocksRefresh")
    static let blocksFind = Notification.Name("blocksFind")
    static let blocksMoveToTopPriorities = Notification.Name("blocksMoveToTopPriorities")
    static let blocksMoveToOther = Notification.Name("blocksMoveToOther")
}

@main struct BlocksApp: App {
    @StateObject private var authManager: AuthManager
    @StateObject private var tasksManager: GoogleTasksManager
    @StateObject private var calendarManager: GoogleCalendarManager
    @StateObject private var fathomManager: FathomManager

    init() {
        let authManager = AuthManager()
        _authManager = StateObject(wrappedValue: authManager)
        _tasksManager = StateObject(wrappedValue: GoogleTasksManager(authManager: authManager))
        _calendarManager = StateObject(wrappedValue: GoogleCalendarManager(authManager: authManager))
        _fathomManager = StateObject(wrappedValue: FathomManager())
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
        .modelContainer(for: [TodoItem.self, InboxItem.self, SeenFathomItem.self])
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
            }
        }

        Settings {
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(tasksManager)
                .environmentObject(fathomManager)
        }
    }
}

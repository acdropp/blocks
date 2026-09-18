import SwiftUI
import SwiftData
import GoogleSignIn

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

        Settings {
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(tasksManager)
                .environmentObject(fathomManager)
        }
    }
}

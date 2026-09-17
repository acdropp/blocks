import SwiftUI
import SwiftData
import GoogleSignIn

@main struct BlocksApp: App {
    @StateObject private var authManager: AuthManager
    @StateObject private var tasksManager: GoogleTasksManager

    init() {
        let authManager = AuthManager()
        _authManager = StateObject(wrappedValue: authManager)
        _tasksManager = StateObject(wrappedValue: GoogleTasksManager(authManager: authManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(tasksManager)
                .onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }
        }
        .modelContainer(for: TodoItem.self)

        Settings {
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(tasksManager)
        }
    }
}

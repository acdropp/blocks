import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager

    var body: some View {
        VStack(spacing: 12) {
            if let email = authManager.email {
                Text(email)
                Button("Sign Out") {
                    authManager.signOut()
                }

                Picker("Task List", selection: $tasksManager.selectedTaskListID) {
                    Text("None").tag(String?.none)
                    ForEach(tasksManager.taskLists) { list in
                        Text(list.title).tag(Optional(list.id))
                    }
                }
                .task {
                    await tasksManager.loadTaskLists()
                }
            } else {
                Button("Sign in with Google") {
                    authManager.signIn()
                }
            }

            if let errorMessage = authManager.errorMessage ?? tasksManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .padding()
        .frame(width: 320, height: 180)
    }
}

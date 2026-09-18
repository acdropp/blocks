import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var fathomManager: FathomManager

    @State private var isEditingFathomKey = false
    @State private var fathomKeyInput = ""

    var body: some View {
        VStack(spacing: 12) {
            if let email = authManager.email {
                Text(email)
                Button("Sign Out") {
                    authManager.signOut()
                }

                Picker("New tasks go to", selection: $tasksManager.defaultTaskListID) {
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

            Divider()

            fathomSection

            if let fathomError = fathomManager.errorMessage {
                Text(fathomError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .padding()
        .frame(width: 320, height: 280)
    }

    @ViewBuilder
    private var fathomSection: some View {
        if fathomManager.hasAPIKey && !isEditingFathomKey {
            Text("Fathom API key is set")
            HStack {
                Button("Replace") {
                    fathomKeyInput = ""
                    isEditingFathomKey = true
                }
                Button("Remove") {
                    fathomManager.removeAPIKey()
                }
            }
        } else {
            SecureField("Fathom API key", text: $fathomKeyInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                if fathomManager.hasAPIKey {
                    Button("Cancel") {
                        isEditingFathomKey = false
                        fathomKeyInput = ""
                    }
                }
                Button("Save") {
                    fathomManager.saveAPIKey(fathomKeyInput)
                    fathomKeyInput = ""
                    isEditingFathomKey = false
                }
                .disabled(fathomKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

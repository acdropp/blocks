import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var fathomManager: FathomManager

    @State private var isEditingFathomKey = false
    @State private var fathomKeyInput = ""

    var body: some View {
        VStack(spacing: 0) {
            mainContent
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            Button("Close") {
                NSApplication.shared.keyWindow?.close()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
        .frame(width: 320, height: 410)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 12) {
            if let email = authManager.email {
                Text(email)
                Button("Sign Out") {
                    authManager.signOut()
                }

                Divider()

                Picker("New tasks go to", selection: $tasksManager.defaultTaskListID) {
                    Text("None").tag(String?.none)
                    ForEach(tasksManager.taskLists) { list in
                        Text(list.title).tag(Optional(list.id))
                    }
                }
                .task {
                    await tasksManager.loadTaskLists()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-move lists")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Scheduled list", selection: $tasksManager.scheduledListID) {
                        Text("None").tag(String?.none)
                        ForEach(tasksManager.taskLists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                    Picker("Opt-out list", selection: $tasksManager.optOutListID) {
                        Text("None").tag(String?.none)
                        ForEach(tasksManager.taskLists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                    Text("Used when a task's time block is added or removed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

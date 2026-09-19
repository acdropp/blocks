import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var fathomManager: FathomManager

    @State private var newAccountName = ""
    @State private var newAccountKey = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                mainContent
                    .padding()
            }
            .frame(maxHeight: .infinity)

            Divider()

            Button("Close") {
                NSApplication.shared.keyWindow?.close()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
        .frame(width: 340, height: 560)
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
        }
    }

    @ViewBuilder
    private var fathomSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fathom accounts")
                .font(.caption)
                .foregroundStyle(.secondary)

            if fathomManager.accounts.isEmpty {
                Text("No accounts added")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fathomManager.accounts) { account in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(account.name)
                            Spacer()
                            Button("Remove") {
                                fathomManager.removeAccount(account)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .font(.caption)
                        }
                        if let error = fathomManager.accountErrors[account.id] {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                TextField("Account name (e.g. Work)", text: $newAccountName)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key", text: $newAccountKey)
                    .textFieldStyle(.roundedBorder)
                Button("Add Account") {
                    fathomManager.addAccount(name: newAccountName, apiKey: newAccountKey)
                    newAccountName = ""
                    newAccountKey = ""
                }
                .disabled(
                    newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    newAccountKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }
}

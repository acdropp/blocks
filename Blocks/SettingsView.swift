import SwiftUI
import SwiftData
import AppKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var calendarManager: GoogleCalendarManager
    @EnvironmentObject private var fathomManager: FathomManager
    @StateObject private var loginItemManager = LoginItemManager()
    @Query(filter: #Predicate<TodoItem> { $0.calendarEventID != nil && $0.calendarID == nil })
    private var legacyPrimaryBlocks: [TodoItem]

    @State private var newAccountName = ""
    @State private var newAccountKey = ""
    @State private var isMigratingBlocks = false
    @State private var migrationResultMessage: String?

    @AppStorage("isTopPrioritiesSectionHidden") private var isTopPrioritiesSectionHidden = false
    @AppStorage("isWorkPrioritiesSectionHidden") private var isWorkPrioritiesSectionHidden = false
    @AppStorage("isChoresSectionHidden") private var isChoresSectionHidden = false
    @AppStorage("isOtherToDosSectionHidden") private var isOtherToDosSectionHidden = false
    @AppStorage("isCompletedSectionHidden") private var isCompletedSectionHidden = false

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
        .frame(width: 340, height: 620)
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

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Personal section")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Personal list", selection: $tasksManager.personalListID) {
                        Text("None").tag(String?.none)
                        ForEach(tasksManager.taskLists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                    if tasksManager.personalListID == nil {
                        Text("No personal list selected.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                sectionVisibilitySection

                Divider()

                calendarSection
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

            Divider()

            loginItemSection
        }
    }

    @ViewBuilder
    private var sectionVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sections")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Hide Top Priorities", isOn: $isTopPrioritiesSectionHidden)
                .toggleStyle(.checkbox)
            Toggle("Hide Work Priorities", isOn: $isWorkPrioritiesSectionHidden)
                .toggleStyle(.checkbox)
            Toggle("Hide Chores", isOn: $isChoresSectionHidden)
                .toggleStyle(.checkbox)
            Toggle("Hide Other To-dos", isOn: $isOtherToDosSectionHidden)
                .toggleStyle(.checkbox)
            Toggle("Hide Completed", isOn: $isCompletedSectionHidden)
                .toggleStyle(.checkbox)
            Toggle("Hide Personal Section", isOn: Binding(
                get: { !tasksManager.isPersonalSectionVisible },
                set: { tasksManager.isPersonalSectionVisible = !$0 }
            ))
                .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time blocks")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Blocks calendar")
                Spacer()
                Text(calendarManager.calendars.first(where: { $0.id == calendarManager.blocksCalendarID })?.summary ?? "Not set yet")
                    .foregroundStyle(.secondary)
            }

            if calendarManager.blocksCalendarID == nil {
                Text("Created automatically the first time you schedule a task.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = calendarManager.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if !legacyPrimaryBlocks.isEmpty {
                Text("\(legacyPrimaryBlocks.count) time block(s) are still on your primary calendar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(isMigratingBlocks ? "Moving…" : "Move to Blocks Calendar") {
                    migrateLegacyBlocks()
                }
                .disabled(isMigratingBlocks)
            }

            if let migrationResultMessage {
                Text(migrationResultMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func migrateLegacyBlocks() {
        let items = legacyPrimaryBlocks
        isMigratingBlocks = true
        migrationResultMessage = nil
        Task {
            let outcome = await calendarManager.migrateLegacyBlocksToBlocksCalendar(items: items)
            isMigratingBlocks = false
            migrationResultMessage = outcome.failed == 0
                ? "Moved \(outcome.moved) time block(s)."
                : "Moved \(outcome.moved), failed to move \(outcome.failed)."
        }
    }

    @ViewBuilder
    private var loginItemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch Blocks at login", isOn: loginItemBinding)

            if loginItemManager.needsApproval {
                Text("Enable Blocks in System Settings > General > Login Items & Extensions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = loginItemManager.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .task {
            loginItemManager.refreshStatus()
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemManager.isEnabled },
            set: { loginItemManager.setEnabled($0) }
        )
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

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

    @AppStorage("topPrioritiesTitle") private var topPrioritiesTitle = "TOP PRIORITIES"
    @AppStorage("workPrioritiesTitle") private var workPrioritiesTitle = "WORK PRIORITIES"
    @AppStorage("choresTitle") private var choresTitle = "CHORES"
    @AppStorage("otherToDosTitle") private var otherToDosTitle = "OTHER TO-DOS"
    @AppStorage("completedTitle") private var completedTitle = "COMPLETED"
    @AppStorage("personalSectionTitle") private var personalSectionTitle = "PERSONAL"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                mainContent
                    .padding()
            }
            .frame(maxHeight: .infinity)
            .scrollContentBackground(.hidden)

            Divider()

            Button("Close") {
                NSApplication.shared.keyWindow?.close()
            }
            .tint(Palette.accent)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .background(Palette.cardBackground)
        }
        .frame(width: 340, height: 620)
        .background(Palette.background)
    }

    /// A white rounded card matching the main app's task cards, used to
    /// group each settings block instead of plain Divider()-separated rows.
    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.cardBackground)
        )
    }

    private func cardLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.accent)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 12) {
            if let email = authManager.email {
                settingsCard {
                    Text(email)
                    Button("Sign Out") {
                        authManager.signOut()
                    }
                    .tint(Palette.accent)
                }

                settingsCard {
                    Picker("New tasks go to", selection: $tasksManager.defaultTaskListID) {
                        Text("None").tag(String?.none)
                        ForEach(tasksManager.taskLists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                    .task {
                        await tasksManager.loadTaskLists()
                    }
                }

                settingsCard {
                    cardLabel("Auto-move lists")

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

                settingsCard {
                    cardLabel("Personal section")

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

                settingsCard {
                    sectionVisibilitySection
                }

                settingsCard {
                    calendarSection
                }
            } else {
                settingsCard {
                    Button("Sign in with Google") {
                        authManager.signIn()
                    }
                    .tint(Palette.accent)
                }
            }

            if let errorMessage = authManager.errorMessage ?? tasksManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            settingsCard {
                fathomSection
            }

            settingsCard {
                loginItemSection
            }
        }
    }

    @ViewBuilder
    private var sectionVisibilitySection: some View {
        cardLabel("Sections")
        Text("Check the box to hide a section. Rename it in the field next to it.")
            .font(.caption2)
            .foregroundStyle(.secondary)

        sectionRow(isHidden: $isTopPrioritiesSectionHidden, title: $topPrioritiesTitle)
        sectionRow(isHidden: $isWorkPrioritiesSectionHidden, title: $workPrioritiesTitle)
        sectionRow(isHidden: $isChoresSectionHidden, title: $choresTitle)
        sectionRow(isHidden: $isOtherToDosSectionHidden, title: $otherToDosTitle)
        sectionRow(isHidden: $isCompletedSectionHidden, title: $completedTitle)
        sectionRow(
            isHidden: Binding(
                get: { !tasksManager.isPersonalSectionVisible },
                set: { tasksManager.isPersonalSectionVisible = !$0 }
            ),
            title: $personalSectionTitle
        )
    }

    @ViewBuilder
    private func sectionRow(isHidden: Binding<Bool>, title: Binding<String>) -> some View {
        HStack {
            Toggle("", isOn: isHidden)
                .toggleStyle(.checkbox)
                .labelsHidden()
            TextField("Section name", text: title)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        cardLabel("Time blocks")

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
            .tint(Palette.accent)
            .disabled(isMigratingBlocks)
        }

        if let migrationResultMessage {
            Text(migrationResultMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
        Toggle("Launch Blocks at login", isOn: loginItemBinding)
            .task {
                loginItemManager.refreshStatus()
            }

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

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemManager.isEnabled },
            set: { loginItemManager.setEnabled($0) }
        )
    }

    @ViewBuilder
    private var fathomSection: some View {
        cardLabel("Fathom accounts")

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
            .tint(Palette.accent)
            .disabled(
                newAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                newAccountKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }
}

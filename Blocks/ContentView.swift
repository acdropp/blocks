import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var items: [TodoItem]
    @Query(sort: \InboxItem.createdAt, order: .reverse) private var inboxItems: [InboxItem]
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var calendarManager: GoogleCalendarManager
    @EnvironmentObject private var fathomManager: FathomManager

    @State private var newTitle = ""
    @State private var isCompletedExpanded = false
    @State private var selection: PersistentIdentifier?
    @State private var editingItemID: PersistentIdentifier?

    @State private var isFindBarVisible = false
    @State private var searchQuery = ""
    @State private var currentMatchIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

    @AppStorage("sortColumn") private var sortColumn: SortColumn = .manual
    @AppStorage("sortDirection") private var sortDirection: SortDirection = .ascending

    private let autoSyncTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit(addTask)

            if isFindBarVisible {
                HStack {
                    Spacer()
                    FindBar(
                        searchQuery: $searchQuery,
                        isFocused: $isSearchFieldFocused,
                        matchCount: searchMatches.count,
                        currentMatchNumber: currentMatchIndex + 1,
                        onNext: goToNextMatch,
                        onPrevious: goToPreviousMatch
                    )
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background {
                    Button("Close Find") { closeFindBar() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .hidden()
                }
            }

            SortHeaderRow(sortColumn: $sortColumn, sortDirection: $sortDirection)

            ScrollViewReader { proxy in
                List(selection: $selection) {
                    if !inboxItems.isEmpty {
                        Section("From meetings") {
                            ForEach(inboxItems) { item in
                                inboxRow(for: item)
                            }
                        }
                    }

                    Section("Top priorities") {
                        ForEach(topPriorities) { item in
                            row(for: item)
                        }
                    }

                    Section("Other to-dos") {
                        ForEach(otherToDos) { item in
                            row(for: item)
                        }
                    }

                    DisclosureGroup("Completed", isExpanded: $isCompletedExpanded) {
                        ForEach(completed) { item in
                            row(for: item)
                        }
                    }
                }
                .onDeleteCommand {
                    deleteSelected()
                }
                .background {
                    Button("Move to Top Priorities") { moveSelected(to: .topPriority) }
                        .keyboardShortcut("1", modifiers: .command)
                        .hidden()
                    Button("Move to Other To-dos") { moveSelected(to: .other) }
                        .keyboardShortcut("2", modifiers: .command)
                        .hidden()
                    Button("Refresh") { Task { await refresh() } }
                        .keyboardShortcut("r", modifiers: .command)
                        .hidden()
                    Button("Find") {
                        isFindBarVisible = true
                        isSearchFieldFocused = true
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                }
                .onChange(of: currentMatchIndex) { _, _ in
                    scrollToCurrentMatch(using: proxy)
                }
                .onChange(of: searchQuery) { _, _ in
                    currentMatchIndex = 0
                    scrollToCurrentMatch(using: proxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 320, minHeight: 400)
        .task {
            ensureManualOrderAssigned()
            await authManager.restorePreviousSignIn()
            await refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh() }
            }
        }
        .onReceive(autoSyncTimer) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        await tasksManager.sync(context: modelContext)
        await fathomManager.fetchNewActionItems(context: modelContext)
    }

    @ViewBuilder
    private func inboxRow(for item: InboxItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                Text(item.meetingName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu("Accept") {
                Button("Top Priorities") { acceptInboxItem(item, to: .topPriority) }
                Button("Other To-dos") { acceptInboxItem(item, to: .other) }
            }
            .fixedSize()

            Button("Dismiss") { dismissInboxItem(item) }
        }
    }

    private func acceptInboxItem(_ item: InboxItem, to section: TodoSection) {
        let newItem = TodoItem(title: item.text, section: section)
        newItem.lastModified = Date()
        newItem.manualOrder = nextManualOrder()
        modelContext.insert(newItem)
        modelContext.delete(item)
        Task { await tasksManager.pushNewTask(newItem) }
    }

    private func dismissInboxItem(_ item: InboxItem) {
        modelContext.delete(item)
    }

    @ViewBuilder
    private func row(for item: TodoItem) -> some View {
        let currentMatchRange: Range<String.Index>? = (currentMatch?.itemID == item.id) ? currentMatch?.range : nil
        let isEditingBinding = Binding<Bool>(
            get: { editingItemID == item.id },
            set: { editingItemID = $0 ? item.id : nil }
        )

        TodoRow(item: item, isEditing: isEditingBinding, searchQuery: searchQuery, currentMatchRange: currentMatchRange)
            .tag(item.id)
            .contextMenu {
                Button("Move to Top Priorities") { move(item, to: .topPriority) }
                Button("Move to Other To-dos") { move(item, to: .other) }
                if item.googleListID != nil && !tasksManager.taskLists.isEmpty {
                    Divider()
                    Menu("Move to List") {
                        ForEach(tasksManager.taskLists) { list in
                            let isCurrent = list.id == item.googleListID
                            Button {
                                moveToGoogleList(item, to: list.id)
                            } label: {
                                if isCurrent {
                                    Label(list.title, systemImage: "checkmark")
                                } else {
                                    Text(list.title)
                                }
                            }
                            .disabled(isCurrent)
                        }
                    }
                }
                Divider()
                Button("Rename") { editingItemID = item.id }
                Divider()
                Button("Delete", role: .destructive) { delete(item) }
            }
    }

    private var topPriorities: [TodoItem] {
        sorted(items.filter { $0.section == .topPriority && !$0.isCompleted })
    }

    private var otherToDos: [TodoItem] {
        sorted(items.filter { $0.section == .other && !$0.isCompleted })
    }

    private var completed: [TodoItem] {
        sorted(items.filter { $0.isCompleted })
    }

    // MARK: - Sort

    private var listNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: tasksManager.taskLists.map { ($0.id, $0.title) })
    }

    private func sorted(_ tasks: [TodoItem]) -> [TodoItem] {
        switch sortColumn {
        case .manual:
            return tasks.sorted { ($0.manualOrder ?? 0) < ($1.manualOrder ?? 0) }
        case .task:
            let ordered = tasks.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return sortDirection == .ascending ? ordered : ordered.reversed()
        case .due:
            return tasks.sorted { compareDue($0, $1) }
        case .list:
            return tasks.sorted { compareList($0, $1) }
        }
    }

    private func compareDue(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (l?, r?):
            return sortDirection == .ascending ? l < r : l > r
        }
    }

    private func compareList(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        let names = listNamesByID
        let lhsName = lhs.googleListID.flatMap { names[$0] }
        let rhsName = rhs.googleListID.flatMap { names[$0] }
        switch (lhsName, rhsName) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (l?, r?):
            let comparison = l.localizedCaseInsensitiveCompare(r)
            return sortDirection == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TodoItem(title: trimmed)
        item.lastModified = Date()
        item.manualOrder = nextManualOrder()
        modelContext.insert(item)
        newTitle = ""
        Task { await tasksManager.pushNewTask(item) }
    }

    // MARK: - Manual order & drag to reorder

    private func ensureManualOrderAssigned() {
        guard items.contains(where: { $0.manualOrder == nil }) else { return }
        let byCreation = items.sorted { $0.createdAt < $1.createdAt }
        for (index, item) in byCreation.enumerated() where item.manualOrder == nil {
            item.manualOrder = Double(index)
        }
    }

    private func nextManualOrder() -> Double {
        (items.compactMap(\.manualOrder).max() ?? -1) + 1
    }

    private func move(_ item: TodoItem, to section: TodoSection) {
        item.section = section
    }

    private func moveSelected(to section: TodoSection) {
        guard let item = items.first(where: { $0.id == selection }) else { return }
        move(item, to: section)
    }

    private func delete(_ item: TodoItem) {
        if selection == item.id { selection = nil }
        let taskID = item.googleTaskID
        let listID = item.googleListID
        let eventID = item.calendarEventID
        modelContext.delete(item)
        if let taskID, let listID {
            Task { await tasksManager.pushDelete(taskID: taskID, listID: listID) }
        }
        if let eventID {
            Task { await calendarManager.deleteBlock(eventID: eventID) }
        }
    }

    private func deleteSelected() {
        guard let item = items.first(where: { $0.id == selection }) else { return }
        delete(item)
    }

    private func moveToGoogleList(_ item: TodoItem, to destinationListID: String) {
        guard let taskID = item.googleTaskID,
              let currentListID = item.googleListID,
              destinationListID != currentListID else { return }

        item.googleListID = destinationListID
        Task {
            if let errorMessage = await tasksManager.moveTask(taskID: taskID, from: currentListID, to: destinationListID) {
                item.googleListID = currentListID
                print("[Tasks] Reverted list label after failed move: \(errorMessage)")
            }
        }
    }

    // MARK: - Find

    private var orderedItems: [TodoItem] {
        topPriorities + otherToDos + completed
    }

    private var searchMatches: [SearchMatch] {
        guard !searchQuery.isEmpty else { return [] }
        var matches: [SearchMatch] = []
        for item in orderedItems {
            let title = item.title
            var searchStart = title.startIndex
            while let range = title.range(of: searchQuery, options: .caseInsensitive, range: searchStart..<title.endIndex) {
                matches.append(SearchMatch(itemID: item.id, range: range))
                searchStart = range.upperBound
            }
        }
        return matches
    }

    private var currentMatch: SearchMatch? {
        guard searchMatches.indices.contains(currentMatchIndex) else { return nil }
        return searchMatches[currentMatchIndex]
    }

    private func goToNextMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
    }

    private func goToPreviousMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
    }

    private func closeFindBar() {
        isFindBarVisible = false
        searchQuery = ""
        currentMatchIndex = 0
        isSearchFieldFocused = false
    }

    private func scrollToCurrentMatch(using proxy: ScrollViewProxy) {
        guard let match = currentMatch else { return }
        if completed.contains(where: { $0.id == match.itemID }) {
            isCompletedExpanded = true
        }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(match.itemID, anchor: .center)
            }
        }
    }
}

private struct SearchMatch {
    let itemID: PersistentIdentifier
    let range: Range<String.Index>
}

/// Shared column widths so the header row and every task row line up
/// exactly, regardless of how long the due/list text is on any given row.
private enum RowLayout {
    static let leadingSpacerWidth: CGFloat = 18
    static let dueColumnWidth: CGFloat = 150
    static let listColumnWidth: CGFloat = 90
}

private enum SortColumn: String {
    case manual, task, due, list
}

private enum SortDirection: String {
    case ascending, descending
}

private struct SortHeaderRow: View {
    @Binding var sortColumn: SortColumn
    @Binding var sortDirection: SortDirection

    var body: some View {
        HStack {
            Color.clear.frame(width: RowLayout.leadingSpacerWidth, height: 1)

            headerButton("Task Name", column: .task)

            Spacer()

            headerButton("Scheduled Time", column: .due)
                .frame(width: RowLayout.dueColumnWidth, alignment: .trailing)

            headerButton("List Name", column: .list)
                .frame(width: RowLayout.listColumnWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func headerButton(_ title: String, column: SortColumn) -> some View {
        Button {
            toggle(column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ column: SortColumn) {
        if sortColumn != column {
            sortColumn = column
            sortDirection = .ascending
        } else if sortDirection == .ascending {
            sortDirection = .descending
        } else {
            sortColumn = .manual
        }
    }
}

private struct FindBar: View {
    @Binding var searchQuery: String
    var isFocused: FocusState<Bool>.Binding
    let matchCount: Int
    let currentMatchNumber: Int
    let onNext: () -> Void
    let onPrevious: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("Find", text: $searchQuery)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(onNext)
                .frame(width: 120)

            Text(matchCount == 0 ? "0/0" : "\(currentMatchNumber)/\(matchCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
        .background {
            Button("Previous Match") { onPrevious() }
                .keyboardShortcut(.return, modifiers: .shift)
                .hidden()
        }
    }
}

private struct TimeBlockPopover: View {
    let durationName: String
    @Binding var startTime: Date
    let onConfirm: () -> Void
    let onRemove: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(durationName)
                .font(.headline)
            DatePicker("Start", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
            if let onRemove {
                Button("Remove", role: .destructive, action: onRemove)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Confirm", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 240)
    }
}

private struct TodoRow: View {
    @Bindable var item: TodoItem
    @Binding var isEditing: Bool
    let searchQuery: String
    let currentMatchRange: Range<String.Index>?
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var calendarManager: GoogleCalendarManager
    @FocusState private var isTitleFocused: Bool
    @State private var draftTitle = ""
    @State private var isHovering = false
    @State private var activeDurationPopover: TimeInterval?
    @State private var pendingStartTime = Date()

    private static let blockDurations: [(label: String, name: String, seconds: TimeInterval)] = [
        ("15m", "15 minutes", 900),
        ("30m", "30 minutes", 1800),
        ("1h", "1 hour", 3600),
        ("2h", "2 hours", 7200),
    ]

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { item.isCompleted },
                set: { newValue in
                    item.isCompleted = newValue
                    item.lastModified = Date()
                    print("[Tasks] Toggled completion for \"\(item.title)\": task=\(item.googleTaskID ?? "nil") list=\(item.googleListID ?? "nil") completed=\(newValue)")
                    Task { await tasksManager.pushUpdate(item) }
                }
            ))
                .labelsHidden()
                .toggleStyle(.checkbox)

            if isEditing {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .onSubmit(commit)
            } else {
                Text(highlightedTitle)
                    .onTapGesture(count: 2) { isEditing = true }

                Spacer()

                Group {
                    if item.calendarEventID != nil {
                        if let scheduledLabel {
                            Text(scheduledLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .onTapGesture { openBlockEditor() }
                        }
                    } else if isHovering {
                        HStack(spacing: 4) {
                            ForEach(Self.blockDurations, id: \.seconds) { block in
                                Button(block.label) {
                                    pendingStartTime = Self.nextQuarterHour()
                                    activeDurationPopover = block.seconds
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                }
                .frame(width: RowLayout.dueColumnWidth, alignment: .trailing)

                Group {
                    if let listName {
                        Text(listName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: RowLayout.listColumnWidth, alignment: .trailing)
            }
        }
        .onHover { hovering in isHovering = hovering }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftTitle = item.title
                isTitleFocused = true
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused && isEditing { commit() }
        }
        .sheet(isPresented: Binding(
            get: { activeDurationPopover != nil },
            set: { if !$0 { activeDurationPopover = nil } }
        )) {
            if let duration = activeDurationPopover,
               let block = Self.blockDurations.first(where: { $0.seconds == duration }) {
                TimeBlockPopover(
                    durationName: block.name,
                    startTime: $pendingStartTime,
                    onConfirm: {
                        confirmBlock(duration: duration)
                        activeDurationPopover = nil
                    },
                    onRemove: item.calendarEventID != nil ? {
                        removeBlock()
                        activeDurationPopover = nil
                    } : nil
                )
            }
        }
    }

    private var listName: String? {
        guard let listID = item.googleListID else { return nil }
        return tasksManager.taskLists.first(where: { $0.id == listID })?.title
    }

    private var scheduledLabel: String? {
        guard item.calendarEventID != nil, let dueDate = item.dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy EEE h:mm a"
        return formatter.string(from: dueDate).uppercased()
    }

    private static func nextQuarterHour() -> Date {
        let interval: TimeInterval = 15 * 60
        let now = Date()
        let remainder = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: interval)
        return remainder == 0 ? now : now.addingTimeInterval(interval - remainder)
    }

    private func openBlockEditor() {
        pendingStartTime = item.dueDate ?? Self.nextQuarterHour()
        activeDurationPopover = item.blockDurationSeconds ?? Self.blockDurations[2].seconds
    }

    private func confirmBlock(duration: TimeInterval) {
        let startTime = pendingStartTime
        Task {
            let success = await calendarManager.scheduleBlock(for: item, duration: duration, startTime: startTime)
            if success {
                await tasksManager.pushUpdate(item)
            }
        }
    }

    private func removeBlock() {
        guard let eventID = item.calendarEventID else { return }
        item.calendarEventID = nil
        item.dueDate = nil
        item.blockDurationSeconds = nil
        item.lastModified = Date()
        Task {
            await calendarManager.deleteBlock(eventID: eventID)
            await tasksManager.clearDueDate(item)
        }
    }

    private var highlightedTitle: AttributedString {
        var attributed = AttributedString(item.title)
        guard !searchQuery.isEmpty else { return attributed }

        let title = item.title
        var searchStart = title.startIndex
        while let range = title.range(of: searchQuery, options: .caseInsensitive, range: searchStart..<title.endIndex) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = (range == currentMatchRange) ? .orange : .yellow
            }
            searchStart = range.upperBound
        }
        return attributed
    }

    private func commit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != item.title {
            item.title = trimmed
            item.lastModified = Date()
            Task { await tasksManager.pushUpdate(item) }
        }
        isEditing = false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}

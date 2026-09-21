import SwiftUI
import SwiftData
import Combine
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager
    @Query private var items: [TodoItem]
    @Query(sort: \InboxItem.createdAt, order: .reverse) private var inboxItems: [InboxItem]
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @EnvironmentObject private var calendarManager: GoogleCalendarManager
    @EnvironmentObject private var fathomManager: FathomManager

    @State private var newTitle = ""
    @State private var isFromMeetingsExpanded = true
    @State private var isTopPrioritiesExpanded = true
    @State private var isWorkPrioritiesExpanded = true
    @State private var isChoresExpanded = true
    @State private var isOtherToDosExpanded = true
    @State private var isCompletedExpanded = false
    @AppStorage("isPersonalExpanded") private var isPersonalExpanded = false
    @AppStorage("isTopPrioritiesSectionHidden") private var isTopPrioritiesSectionHidden = false
    @AppStorage("isWorkPrioritiesSectionHidden") private var isWorkPrioritiesSectionHidden = false
    @AppStorage("isChoresSectionHidden") private var isChoresSectionHidden = false
    @AppStorage("isOtherToDosSectionHidden") private var isOtherToDosSectionHidden = false
    @AppStorage("isCompletedSectionHidden") private var isCompletedSectionHidden = false
    @State private var selection: PersistentIdentifier?
    @State private var editingItemID: PersistentIdentifier?

    @State private var isFindBarVisible = false
    @State private var searchQuery = ""
    @State private var currentMatchIndex = 0
    @FocusState private var isSearchFieldFocused: Bool

    @AppStorage("sortColumn") private var sortColumn: SortColumn = .manual
    @AppStorage("sortDirection") private var sortDirection: SortDirection = .ascending

    // Bumped whenever refresh() runs (launch, Refresh, window-active, the
    // 5-minute auto-sync timer) so late-task coloring re-evaluates without
    // needing a restart, including across a midnight date rollover while
    // the app is left open.
    @State private var lateCheckAnchor = Date()

    private let autoSyncTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                quickAddBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                sectionHeaderRow("FROM MEETINGS", isExpanded: $isFromMeetingsExpanded)
                if isFromMeetingsExpanded {
                    Divider()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    ForEach(inboxItems) { item in
                        inboxRow(for: item)
                    }
                }

                SortHeaderRow(sortColumn: $sortColumn, sortDirection: $sortDirection)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                if !isTopPrioritiesSectionHidden {
                    sectionHeaderRow("TOP PRIORITIES", isExpanded: $isTopPrioritiesExpanded)
                    if isTopPrioritiesExpanded {
                        ForEach(topPriorities) { item in
                            row(for: item)
                        }
                    }
                }

                if !isWorkPrioritiesSectionHidden {
                    sectionHeaderRow("WORK PRIORITIES", isExpanded: $isWorkPrioritiesExpanded)
                    if isWorkPrioritiesExpanded {
                        ForEach(workPriorities) { item in
                            row(for: item)
                        }
                    }
                }

                if !isChoresSectionHidden {
                    sectionHeaderRow("CHORES", isExpanded: $isChoresExpanded)
                    if isChoresExpanded {
                        ForEach(chores) { item in
                            row(for: item)
                        }
                    }
                }

                if !isOtherToDosSectionHidden {
                    sectionHeaderRow("OTHER TO-DOS", isExpanded: $isOtherToDosExpanded)
                    if isOtherToDosExpanded {
                        ForEach(otherToDos) { item in
                            row(for: item)
                        }
                    }
                }

                if !isCompletedSectionHidden {
                    sectionHeaderRow("COMPLETED", isExpanded: $isCompletedExpanded)
                    if isCompletedExpanded {
                        ForEach(completed) { item in
                            row(for: item)
                        }
                    }
                }

                if tasksManager.isPersonalSectionVisible, tasksManager.personalListID != nil {
                    sectionHeaderRow("PERSONAL", isExpanded: $isPersonalExpanded)
                    if isPersonalExpanded {
                        ForEach(personalItems) { item in
                            row(for: item)
                        }
                    }
                }
            }
            .onDeleteCommand {
                deleteSelected()
            }
            .onChange(of: currentMatchIndex) { _, _ in
                scrollToCurrentMatch(using: proxy)
            }
            .onChange(of: searchQuery) { _, _ in
                currentMatchIndex = 0
                scrollToCurrentMatch(using: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .blocksRefresh)) { _ in
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .blocksFind)) { _ in
                isFindBarVisible = true
                isSearchFieldFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .blocksMoveToTopPriorities)) { _ in
                moveSelected(to: .topPriority)
            }
            .onReceive(NotificationCenter.default.publisher(for: .blocksMoveToOther)) { _ in
                moveSelected(to: .other)
            }
            .onReceive(NotificationCenter.default.publisher(for: .blocksTogglePersonalSection)) { _ in
                tasksManager.isPersonalSectionVisible.toggle()
            }
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

    /// A plain (non-DisclosureGroup) collapsible section header: a button
    /// with our own chevron, positioned to line up with row checkboxes.
    /// Kept out of DisclosureGroup entirely — wrapping ForEach content
    /// inside a DisclosureGroupStyle's own container view was found to
    /// strip the List's native row separators and default row height from
    /// each child row. Sibling rows below (in an `if isExpanded { ForEach }`
    /// right after this) stay genuine top-level List rows instead.
    private func sectionHeaderRow(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .frame(width: RowLayout.leadingSpacerWidth, height: 20, alignment: .center)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var quickAddBar: some View {
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
        }
    }


    private func refresh() async {
        lateCheckAnchor = Date()
        let syncOutcome = await tasksManager.sync(context: modelContext)

        for item in syncOutcome.completionChanged {
            await calendarManager.updateEventCompletionMark(for: item, listName: listName(for: item))
        }
        for ref in syncOutcome.deletedEventRefs {
            await calendarManager.deleteBlock(calendarID: ref.calendarID, eventID: ref.eventID)
        }

        let calendarChanges = await calendarManager.pullChanges(context: modelContext)
        for item in calendarChanges.updated {
            await tasksManager.pushUpdate(item)
        }
        for item in calendarChanges.cleared {
            await tasksManager.clearDueDate(item)
            if let optOutListID = tasksManager.optOutListID {
                moveToGoogleList(item, to: optOutListID)
            }
        }

        await fathomManager.fetchNewActionItems(context: modelContext)
    }

    private func listName(for item: TodoItem) -> String? {
        tasksManager.taskLists.first(where: { $0.id == item.googleListID })?.title
    }

    @ViewBuilder
    private func inboxRow(for item: InboxItem) -> some View {
        HStack {
            Color.clear.frame(width: RowLayout.inboxRowIndent, height: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                Text(inboxSubtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu("Accept") {
                Button("Top Priorities") { acceptInboxItem(item, to: .topPriority) }
                Button("Work Priorities") { acceptInboxItem(item, to: .workPriority) }
                Button("Chores") { acceptInboxItem(item, to: .chores) }
                Button("Other To-dos") { acceptInboxItem(item, to: .other) }
            }
            .fixedSize()

            Button("Dismiss") { dismissInboxItem(item) }
        }
    }

    private func inboxSubtitle(for item: InboxItem) -> String {
        var subtitle = "\(item.meetingName) · \(item.accountName)"
        if let assigneeName = item.assigneeName, !assigneeName.isEmpty {
            subtitle += " · \(assigneeName)"
        }
        return subtitle
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

        TodoRow(item: item, isEditing: isEditingBinding, searchQuery: searchQuery, currentMatchRange: currentMatchRange, isLate: isLate(item))
            .tag(item.id)
            .contextMenu {
                Button("Move to Top Priorities") { move(item, to: .topPriority) }
                Button("Move to Work Priorities") { move(item, to: .workPriority) }
                Button("Move to Chores") { move(item, to: .chores) }
                Button("Move to Other To-dos") { move(item, to: .other) }
                Button("Move to Completed") { completeTask(item) }
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
        sorted(items.filter { $0.section == .topPriority && !$0.isCompleted && !isPersonalListItem($0) })
    }

    private var workPriorities: [TodoItem] {
        sorted(items.filter { $0.section == .workPriority && !$0.isCompleted && !isPersonalListItem($0) })
    }

    private var chores: [TodoItem] {
        sorted(items.filter { $0.section == .chores && !$0.isCompleted && !isPersonalListItem($0) })
    }

    private var otherToDos: [TodoItem] {
        sorted(items.filter { $0.section == .other && !$0.isCompleted && !isPersonalListItem($0) })
    }

    private var completed: [TodoItem] {
        sorted(items.filter { $0.isCompleted && !isPersonalListItem($0) })
    }

    private var personalItems: [TodoItem] {
        guard let personalListID = tasksManager.personalListID else { return [] }
        return sorted(items.filter { $0.googleListID == personalListID })
    }

    private func isPersonalListItem(_ item: TodoItem) -> Bool {
        guard let personalListID = tasksManager.personalListID else { return false }
        return item.googleListID == personalListID
    }

    // A task is late once the calendar day after its due date begins —
    // a task due any time Monday becomes late at midnight Monday night.
    // Applies to any due date, whether or not it has a scheduled time.
    private func isLate(_ item: TodoItem) -> Bool {
        guard !item.isCompleted, let dueDate = item.dueDate else { return false }
        let calendar = Calendar.current
        let dueDay = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: lateCheckAnchor)
        return today > dueDay
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
        let oldSection = item.section
        guard oldSection != section else { return }
        item.section = section

        undoManager?.registerUndo(withTarget: item) { [self] target in
            move(target, to: oldSection)
        }
        undoManager?.setActionName("Move Task")
    }

    private func completeTask(_ item: TodoItem) {
        item.isCompleted = true
        item.lastModified = Date()
        print("[Tasks] Completed via context menu for \"\(item.title)\": task=\(item.googleTaskID ?? "nil") list=\(item.googleListID ?? "nil")")
        let name = listName(for: item)
        Task {
            await tasksManager.pushUpdate(item)
            await calendarManager.updateEventCompletionMark(for: item, listName: name)
        }
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
        let calendarID = item.calendarID
        let snapshot = DeletedTaskSnapshot(item: item)
        modelContext.delete(item)
        if let taskID, let listID {
            Task { await tasksManager.pushDelete(taskID: taskID, listID: listID) }
        }
        if let eventID {
            Task { await calendarManager.deleteBlock(calendarID: calendarID, eventID: eventID) }
        }

        undoManager?.registerUndo(withTarget: modelContext) { [self] _ in
            restore(snapshot)
        }
        undoManager?.setActionName("Delete Task")
    }

    private func restore(_ snapshot: DeletedTaskSnapshot) {
        let restored = TodoItem(title: snapshot.title, section: snapshot.section)
        restored.isCompleted = snapshot.isCompleted
        restored.manualOrder = snapshot.manualOrder ?? nextManualOrder()
        restored.lastModified = Date()
        modelContext.insert(restored)
        print("[Tasks] Undo delete: restored \"\(snapshot.title)\"")

        Task {
            await tasksManager.pushNewTask(restored)
            if let originalListID = snapshot.googleListID, restored.googleListID != originalListID {
                moveToGoogleList(restored, to: originalListID)
            }
            if snapshot.hadCalendarBlock, let dueDate = snapshot.dueDate, let duration = snapshot.blockDurationSeconds {
                let listName = tasksManager.taskLists.first(where: { $0.id == (snapshot.googleListID ?? restored.googleListID) })?.title
                let success = await calendarManager.scheduleBlock(for: restored, duration: duration, startTime: dueDate, listName: listName)
                if success {
                    await tasksManager.pushUpdate(restored)
                }
            }
        }

        undoManager?.registerUndo(withTarget: modelContext) { [self] _ in
            delete(restored)
        }
        undoManager?.setActionName("Delete Task")
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

        undoManager?.registerUndo(withTarget: item) { [self] target in
            moveToGoogleList(target, to: currentListID)
        }
        undoManager?.setActionName("Move Task")
    }

    // MARK: - Find

    private var orderedItems: [TodoItem] {
        var all: [TodoItem] = []
        if !isTopPrioritiesSectionHidden { all += topPriorities }
        if !isWorkPrioritiesSectionHidden { all += workPriorities }
        if !isChoresSectionHidden { all += chores }
        if !isOtherToDosSectionHidden { all += otherToDos }
        if !isCompletedSectionHidden { all += completed }
        if tasksManager.isPersonalSectionVisible {
            all += personalItems
        }
        return all
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
        if personalItems.contains(where: { $0.id == match.itemID }) {
            isPersonalExpanded = true
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

/// Captures what's needed to recreate a task after it's deleted, for Undo.
/// The restored task gets fresh IDs on Google's side — the originals are
/// gone once deleted there, so this isn't a byte-for-byte restore, just an
/// equivalent task with the same content.
private struct DeletedTaskSnapshot {
    let title: String
    let section: TodoSection
    let isCompleted: Bool
    let dueDate: Date?
    let googleListID: String?
    let manualOrder: Double?
    let blockDurationSeconds: Double?
    let hadCalendarBlock: Bool

    init(item: TodoItem) {
        title = item.title
        section = item.section
        isCompleted = item.isCompleted
        dueDate = item.dueDate
        googleListID = item.googleListID
        manualOrder = item.manualOrder
        blockDurationSeconds = item.blockDurationSeconds
        hadCalendarBlock = item.calendarEventID != nil
    }
}

/// Shared column widths so the header row and every task row line up
/// exactly, regardless of how long the due/list text is on any given row.
extension Color {
    /// Flags a late task's title, scheduled time, and list name. Tuned
    /// separately for light and dark mode so it stays readable against
    /// either background.
    static let lateTask = Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 1.00, green: 0.45, blue: 0.55, alpha: 1.0)
            : NSColor(red: 0.80, green: 0.20, blue: 0.32, alpha: 1.0)
    })
}

private enum RowLayout {
    static let leadingSpacerWidth: CGFloat = 18
    static let dueColumnWidth: CGFloat = 150
    static let listColumnWidth: CGFloat = 90
    // Rows nested inside a DisclosureGroup's content (like inbox rows under
    // FROM MEETINGS) sit further right than the DisclosureGroup's own label
    // by AppKit's built-in outline indent; this offsets that so inbox row
    // text lines up with a sibling section's label text (e.g. TOP PRIORITIES).
    static let inboxRowIndent: CGFloat = 14
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

            headerButton("TASK NAME", column: .task)

            Spacer()

            headerButton("SCHEDULED TIME", column: .due)
                .frame(width: RowLayout.dueColumnWidth, alignment: .trailing)

            headerButton("LIST NAME", column: .list)
                .frame(width: RowLayout.listColumnWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func headerButton(_ title: String, column: SortColumn) -> some View {
        Button {
            toggle(column)
        } label: {
            HStack(spacing: 2) {
                if sortColumn == column {
                    Image(systemName: sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
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
    let isLate: Bool
    @Environment(\.undoManager) private var undoManager
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
                    let name = tasksManager.taskLists.first(where: { $0.id == item.googleListID })?.title
                    Task {
                        await tasksManager.pushUpdate(item)
                        await calendarManager.updateEventCompletionMark(for: item, listName: name)
                    }
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
                    .foregroundStyle(isLate ? Color.lateTask : Color.primary)
                    .onTapGesture(count: 2) { isEditing = true }

                Spacer()

                Group {
                    if let scheduledLabel {
                        Text(scheduledLabel)
                            .font(.caption)
                            .foregroundStyle(isLate ? Color.lateTask : Color.secondary)
                            .onTapGesture { openBlockEditor() }
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
                            .foregroundStyle(isLate ? Color.lateTask : Color.secondary)
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
        let listName = tasksManager.taskLists.first(where: { $0.id == item.googleListID })?.title
        Task {
            let success = await calendarManager.scheduleBlock(for: item, duration: duration, startTime: startTime, listName: listName)
            if success {
                await tasksManager.pushUpdate(item)
                moveToList(id: tasksManager.scheduledListID, settingName: "Scheduled list")
            }
        }
    }

    private func removeBlock() {
        guard let eventID = item.calendarEventID else { return }
        let calendarID = item.calendarID
        let wasInScheduled = isInList(id: tasksManager.scheduledListID)
        item.calendarEventID = nil
        item.calendarID = nil
        item.dueDate = nil
        item.blockDurationSeconds = nil
        item.lastModified = Date()
        Task {
            await calendarManager.deleteBlock(calendarID: calendarID, eventID: eventID)
            await tasksManager.clearDueDate(item)
        }
        if wasInScheduled {
            moveToList(id: tasksManager.optOutListID, settingName: "Opt-out list")
        }
    }

    private func isInList(id targetListID: String?) -> Bool {
        guard let targetListID, let listID = item.googleListID else { return false }
        return listID == targetListID
    }

    private func moveToList(id destinationID: String?, settingName: String) {
        guard let destinationID else {
            print("[Tasks] moveToList(\(settingName)) skipped for \"\(item.title)\": not set in Settings")
            return
        }
        guard let taskID = item.googleTaskID else {
            print("[Tasks] moveToList(\(settingName)) skipped for \"\(item.title)\": no googleTaskID")
            return
        }
        guard let currentListID = item.googleListID else {
            print("[Tasks] moveToList(\(settingName)) skipped for \"\(item.title)\": no googleListID")
            return
        }
        guard destinationID != currentListID else {
            print("[Tasks] moveToList(\(settingName)) skipped for \"\(item.title)\": already in that list")
            return
        }
        guard let destination = tasksManager.taskLists.first(where: { $0.id == destinationID }) else {
            print("[Tasks] moveToList(\(settingName)) skipped for \"\(item.title)\": that list no longer exists")
            return
        }

        print("[Tasks] Auto-moving \"\(item.title)\" to \"\(destination.title)\" (\(destination.id))")
        item.googleListID = destination.id
        Task {
            if let errorMessage = await tasksManager.moveTask(taskID: taskID, from: currentListID, to: destination.id) {
                item.googleListID = currentListID
                print("[Tasks] Reverted auto-move to \"\(destination.title)\": \(errorMessage)")
            }
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
            rename(item, to: trimmed)
        }
        isEditing = false
    }

    private func rename(_ item: TodoItem, to newTitle: String) {
        let oldTitle = item.title
        guard oldTitle != newTitle else { return }
        item.title = newTitle
        item.lastModified = Date()
        Task { await tasksManager.pushUpdate(item) }

        undoManager?.registerUndo(withTarget: item) { [self] target in
            rename(target, to: oldTitle)
        }
        undoManager?.setActionName("Rename Task")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}

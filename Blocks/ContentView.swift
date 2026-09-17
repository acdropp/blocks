import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var items: [TodoItem]
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var tasksManager: GoogleTasksManager

    @State private var newTitle = ""
    @State private var isCompletedExpanded = false
    @State private var selection: PersistentIdentifier?
    @State private var editingItemID: PersistentIdentifier?

    private let autoSyncTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit(addTask)

            List(selection: $selection) {
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
            }
        }
        .frame(minWidth: 320, minHeight: 400)
        .task {
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
    }

    @ViewBuilder
    private func row(for item: TodoItem) -> some View {
        TodoRow(item: item, isEditing: Binding(
            get: { editingItemID == item.id },
            set: { editingItemID = $0 ? item.id : nil }
        ))
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
        items.filter { $0.section == .topPriority && !$0.isCompleted }
    }

    private var otherToDos: [TodoItem] {
        items.filter { $0.section == .other && !$0.isCompleted }
    }

    private var completed: [TodoItem] {
        items.filter { $0.isCompleted }
    }

    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TodoItem(title: trimmed)
        item.lastModified = Date()
        modelContext.insert(item)
        newTitle = ""
        Task { await tasksManager.pushNewTask(item) }
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
        modelContext.delete(item)
        if let taskID, let listID {
            Task { await tasksManager.pushDelete(taskID: taskID, listID: listID) }
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
}

private struct TodoRow: View {
    @Bindable var item: TodoItem
    @Binding var isEditing: Bool
    @EnvironmentObject private var tasksManager: GoogleTasksManager
    @FocusState private var isTitleFocused: Bool
    @State private var draftTitle = ""

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
                Text(item.title)
                    .onTapGesture(count: 2) { isEditing = true }

                Spacer()

                if let listName {
                    Text(listName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                draftTitle = item.title
                isTitleFocused = true
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused && isEditing { commit() }
        }
    }

    private var listName: String? {
        guard let listID = item.googleListID else { return nil }
        return tasksManager.taskLists.first(where: { $0.id == listID })?.title
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

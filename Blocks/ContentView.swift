import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [TodoItem]

    @State private var newTitle = ""
    @State private var isCompletedExpanded = false
    @State private var selection: PersistentIdentifier?

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
            }
        }
        .frame(minWidth: 320, minHeight: 400)
    }

    @ViewBuilder
    private func row(for item: TodoItem) -> some View {
        TodoRow(item: item)
            .tag(item.id)
            .contextMenu {
                Button("Move to Top Priorities") { move(item, to: .topPriority) }
                Button("Move to Other To-dos") { move(item, to: .other) }
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
        modelContext.insert(TodoItem(title: trimmed))
        newTitle = ""
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
        modelContext.delete(item)
    }

    private func deleteSelected() {
        guard let item = items.first(where: { $0.id == selection }) else { return }
        delete(item)
    }
}

private struct TodoRow: View {
    @Bindable var item: TodoItem
    @FocusState private var isTitleFocused: Bool
    @State private var isEditing = false
    @State private var draftTitle = ""

    var body: some View {
        HStack {
            Toggle("", isOn: $item.isCompleted)
                .labelsHidden()
                .toggleStyle(.checkbox)

            if isEditing {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .onSubmit(commit)
            } else {
                Text(item.title)
                    .onTapGesture(count: 2) { beginEditing() }
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused && isEditing { commit() }
        }
    }

    private func beginEditing() {
        draftTitle = item.title
        isEditing = true
        isTitleFocused = true
    }

    private func commit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.title = trimmed
        }
        isEditing = false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}

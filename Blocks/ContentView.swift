import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [TodoItem]

    @State private var newTitle = ""
    @State private var isCompletedExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Add a task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit(addTask)

            List {
                Section("Top priorities") {
                    ForEach(topPriorities) { item in
                        TodoRow(item: item)
                    }
                }

                Section("Other to-dos") {
                    ForEach(otherToDos) { item in
                        TodoRow(item: item)
                    }
                }

                DisclosureGroup("Completed", isExpanded: $isCompletedExpanded) {
                    ForEach(completed) { item in
                        TodoRow(item: item)
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 400)
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
}

private struct TodoRow: View {
    @Bindable var item: TodoItem

    var body: some View {
        Toggle(isOn: $item.isCompleted) {
            Text(item.title)
        }
        .toggleStyle(.checkbox)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TodoItem.self, inMemory: true)
}

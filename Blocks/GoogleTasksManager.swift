import Foundation
import Combine
import SwiftData

@MainActor
final class GoogleTasksManager: ObservableObject {
    private static let selectedTaskListIDKey = "selectedGoogleTaskListID"

    @Published private(set) var taskLists: [GoogleTaskList] = []
    @Published private(set) var errorMessage: String?
    @Published var selectedTaskListID: String? {
        didSet {
            UserDefaults.standard.set(selectedTaskListID, forKey: Self.selectedTaskListIDKey)
        }
    }

    private let service = GoogleTasksService()
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.selectedTaskListID = UserDefaults.standard.string(forKey: Self.selectedTaskListIDKey)
    }

    func loadTaskLists() async {
        print("[Tasks] Loading task lists")
        do {
            let token = try await authManager.validAccessToken()
            taskLists = try await service.fetchTaskLists(accessToken: token)
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to load task lists: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func sync(context: ModelContext) async {
        guard let listID = selectedTaskListID else {
            print("[Tasks] Sync skipped: no task list selected")
            return
        }

        print("[Tasks] Syncing with list \(listID)")
        do {
            let token = try await authManager.validAccessToken()
            let remoteTasks = try await service.fetchTasks(listID: listID, accessToken: token)

            let localItems = try context.fetch(FetchDescriptor<TodoItem>())
            var localByGoogleID: [String: TodoItem] = [:]
            for item in localItems {
                if let googleID = item.googleTaskID {
                    localByGoogleID[googleID] = item
                }
            }

            var importedCount = 0
            var updatedCount = 0

            for remote in remoteTasks where remote.deleted != true {
                let remoteUpdated = remote.updatedDate ?? Date()

                if let existing = localByGoogleID[remote.id] {
                    let localModified = existing.lastModified ?? .distantPast
                    guard remoteUpdated > localModified else { continue }
                    existing.title = remote.title ?? ""
                    existing.isCompleted = remote.isCompleted
                    existing.dueDate = remote.dueDate
                    existing.lastModified = remoteUpdated
                    updatedCount += 1
                } else {
                    let newItem = TodoItem(title: remote.title ?? "")
                    newItem.isCompleted = remote.isCompleted
                    newItem.dueDate = remote.dueDate
                    newItem.googleTaskID = remote.id
                    newItem.lastModified = remoteUpdated
                    context.insert(newItem)
                    importedCount += 1
                }
            }

            print("[Tasks] Sync complete: \(importedCount) new, \(updatedCount) updated")
            errorMessage = nil
        } catch {
            print("[Tasks] Sync failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func pushNewTask(_ item: TodoItem) async {
        guard let listID = selectedTaskListID else { return }
        print("[Tasks] Pushing new task: \(item.title)")
        do {
            let token = try await authManager.validAccessToken()
            let remote = try await service.insertTask(listID: listID, title: item.title, accessToken: token)
            item.googleTaskID = remote.id
            item.lastModified = remote.updatedDate ?? Date()
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to push new task: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func pushUpdate(_ item: TodoItem) async {
        guard let listID = selectedTaskListID else { return }
        guard let taskID = item.googleTaskID else {
            await pushNewTask(item)
            return
        }
        print("[Tasks] Pushing update for task: \(item.title)")
        do {
            let token = try await authManager.validAccessToken()
            let remote = try await service.patchTask(
                listID: listID,
                taskID: taskID,
                title: item.title,
                isCompleted: item.isCompleted,
                accessToken: token
            )
            item.lastModified = remote.updatedDate ?? Date()
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to push update: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func pushDelete(taskID: String) async {
        guard let listID = selectedTaskListID else { return }
        print("[Tasks] Pushing delete for task \(taskID)")
        do {
            let token = try await authManager.validAccessToken()
            try await service.deleteTask(listID: listID, taskID: taskID, accessToken: token)
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to push delete: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

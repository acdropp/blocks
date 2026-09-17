import Foundation
import Combine
import SwiftData

@MainActor
final class GoogleTasksManager: ObservableObject {
    private static let defaultTaskListIDKey = "selectedGoogleTaskListID"

    @Published private(set) var taskLists: [GoogleTaskList] = []
    @Published private(set) var errorMessage: String?
    @Published var defaultTaskListID: String? {
        didSet {
            UserDefaults.standard.set(defaultTaskListID, forKey: Self.defaultTaskListIDKey)
        }
    }

    private let service = GoogleTasksService()
    private let authManager: AuthManager
    private var isSyncing = false

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.defaultTaskListID = UserDefaults.standard.string(forKey: Self.defaultTaskListIDKey)
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
        guard !isSyncing else {
            print("[Tasks] Sync already in progress, skipping")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        print("[Tasks] Syncing all task lists")
        do {
            let token = try await authManager.validAccessToken()
            let remoteLists = try await service.fetchTaskLists(accessToken: token)
            taskLists = remoteLists

            let localItems = try context.fetch(FetchDescriptor<TodoItem>())

            // Existing tasks synced before per-task list tracking belong to
            // whatever list was previously the single mirrored list.
            if let fallbackListID = defaultTaskListID {
                for item in localItems where item.googleTaskID != nil && item.googleListID == nil {
                    item.googleListID = fallbackListID
                }
            }

            var localByGoogleID: [String: TodoItem] = [:]
            for item in localItems {
                if let googleID = item.googleTaskID {
                    localByGoogleID[googleID] = item
                }
            }

            var importedCount = 0
            var updatedCount = 0

            for list in remoteLists {
                let remoteTasks = try await service.fetchTasks(listID: list.id, accessToken: token)

                for remote in remoteTasks where remote.deleted != true {
                    let remoteUpdated = remote.updatedDate ?? Date()

                    if let existing = localByGoogleID[remote.id] {
                        existing.googleListID = list.id
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
                        newItem.googleListID = list.id
                        newItem.lastModified = remoteUpdated
                        context.insert(newItem)
                        localByGoogleID[remote.id] = newItem
                        importedCount += 1
                    }
                }
            }

            // A task whose list no longer appears among the lists we just
            // fetched means that list was deleted on Google — drop it locally.
            let validListIDs = Set(remoteLists.map(\.id))
            var removedCount = 0
            for item in localItems {
                guard let listID = item.googleListID, !validListIDs.contains(listID) else { continue }
                context.delete(item)
                removedCount += 1
            }

            print("[Tasks] Sync complete: \(importedCount) new, \(updatedCount) updated, \(removedCount) removed")
            errorMessage = nil
        } catch {
            print("[Tasks] Sync failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func pushNewTask(_ item: TodoItem) async {
        guard let listID = defaultTaskListID else { return }
        print("[Tasks] Pushing new task: \(item.title)")
        do {
            let token = try await authManager.validAccessToken()
            let remote = try await service.insertTask(listID: listID, title: item.title, accessToken: token)
            item.googleTaskID = remote.id
            item.googleListID = listID
            item.lastModified = remote.updatedDate ?? Date()
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to push new task: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func pushUpdate(_ item: TodoItem) async {
        guard let taskID = item.googleTaskID else {
            await pushNewTask(item)
            return
        }
        guard let listID = item.googleListID else {
            print("[Tasks] Can't push update: task \(taskID) has no known list")
            errorMessage = "Can't sync \"\(item.title)\": unknown list."
            return
        }
        print("[Tasks] Pushing update for task \(taskID) in list \(listID): \"\(item.title)\" completed=\(item.isCompleted)")
        do {
            let token = try await authManager.validAccessToken()
            let remote = try await service.patchTask(
                listID: listID,
                taskID: taskID,
                title: item.title,
                isCompleted: item.isCompleted,
                due: item.dueDate,
                accessToken: token
            )
            print("[Tasks] Update confirmed for task \(taskID): status=\(remote.status ?? "nil")")
            item.lastModified = remote.updatedDate ?? Date()
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to push update for task \(taskID) in list \(listID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func clearDueDate(_ item: TodoItem) async {
        guard let taskID = item.googleTaskID, let listID = item.googleListID else { return }
        print("[Tasks] Clearing due date for task \(taskID)")
        do {
            let token = try await authManager.validAccessToken()
            let remote = try await service.clearDueDate(listID: listID, taskID: taskID, accessToken: token)
            item.lastModified = remote.updatedDate ?? Date()
            errorMessage = nil
        } catch {
            print("[Tasks] Failed to clear due date for task \(taskID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func pushDelete(taskID: String, listID: String) async {
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

    /// Attempts to move a task to a different list. Returns nil on success,
    /// or a short user-facing message if the move failed.
    func moveTask(taskID: String, from listID: String, to destinationListID: String) async -> String? {
        print("[Tasks] Moving task \(taskID) from list \(listID) to \(destinationListID)")
        do {
            let token = try await authManager.validAccessToken()
            _ = try await service.moveTask(listID: listID, taskID: taskID, destinationListID: destinationListID, accessToken: token)
            print("[Tasks] Move confirmed for task \(taskID)")
            errorMessage = nil
            return nil
        } catch GoogleTasksError.requestFailed(let status, let body) {
            print("[Tasks] Move failed for task \(taskID): HTTP \(status) \(body)")
            let message = body.lowercased().contains("recurring")
                ? "Recurring tasks can't be moved between lists."
                : "Couldn't move task (HTTP \(status))."
            errorMessage = message
            return message
        } catch {
            print("[Tasks] Move failed for task \(taskID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }
}

import Foundation
import Combine
import SwiftData

@MainActor
final class GoogleTasksManager: ObservableObject {
    private static let defaultTaskListIDKey = "selectedGoogleTaskListID"
    private static let scheduledListIDKey = "scheduledListID"
    private static let optOutListIDKey = "optOutListID"
    private static let personalListIDKey = "personalListID"
    private static let isPersonalSectionVisibleKey = "isPersonalSectionVisible"
    private static let fallbackScheduledListName = "SCHEDULED"
    private static let fallbackOptOutListName = "OPT-OUT"
    private static let fallbackPersonalListName = "(0) PERSONAL"

    @Published private(set) var taskLists: [GoogleTaskList] = []
    @Published private(set) var errorMessage: String?
    @Published var defaultTaskListID: String? {
        didSet {
            UserDefaults.standard.set(defaultTaskListID, forKey: Self.defaultTaskListIDKey)
        }
    }
    // The Google Tasks lists the auto-move feature moves tasks between
    // when a time block is added or removed, chosen in Settings the same
    // way "New tasks go to" is. Stored by list ID rather than name, so
    // renaming the list in Google Tasks never breaks this — only deleting
    // it does.
    @Published var scheduledListID: String? {
        didSet {
            UserDefaults.standard.set(scheduledListID, forKey: Self.scheduledListIDKey)
        }
    }
    @Published var optOutListID: String? {
        didSet {
            UserDefaults.standard.set(optOutListID, forKey: Self.optOutListIDKey)
        }
    }
    // The Google Tasks list treated as the Personal section. Stored by ID
    // (not name) so renaming the list never breaks this — only deleting it
    // does, at which point it's cleared back to nil automatically.
    @Published var personalListID: String? {
        didSet {
            UserDefaults.standard.set(personalListID, forKey: Self.personalListIDKey)
        }
    }
    @Published var isPersonalSectionVisible: Bool {
        didSet {
            UserDefaults.standard.set(isPersonalSectionVisible, forKey: Self.isPersonalSectionVisibleKey)
        }
    }

    private let service = GoogleTasksService()
    private let authManager: AuthManager
    private var isSyncing = false

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.defaultTaskListID = UserDefaults.standard.string(forKey: Self.defaultTaskListIDKey)
        self.scheduledListID = UserDefaults.standard.string(forKey: Self.scheduledListIDKey)
        self.optOutListID = UserDefaults.standard.string(forKey: Self.optOutListIDKey)
        self.personalListID = UserDefaults.standard.string(forKey: Self.personalListIDKey)
        self.isPersonalSectionVisible = UserDefaults.standard.object(forKey: Self.isPersonalSectionVisibleKey) as? Bool ?? true
    }

    // The first time real task lists come back and no Scheduled/Opt-out/
    // Personal list has been chosen yet, default to whichever list is
    // named "SCHEDULED"/"OPT-OUT"/"(0) PERSONAL" (case-insensitive) so
    // existing users don't have to visit Settings just to restore prior
    // behavior.
    private func backfillAutoMoveListIDsIfNeeded() {
        if scheduledListID == nil {
            scheduledListID = taskLists.first(where: { $0.title.caseInsensitiveCompare(Self.fallbackScheduledListName) == .orderedSame })?.id
        }
        if optOutListID == nil {
            optOutListID = taskLists.first(where: { $0.title.caseInsensitiveCompare(Self.fallbackOptOutListName) == .orderedSame })?.id
        }
        if personalListID == nil {
            personalListID = taskLists.first(where: { $0.title.caseInsensitiveCompare(Self.fallbackPersonalListName) == .orderedSame })?.id
        }
    }

    // If the chosen personal list was deleted on Google's side, clear the
    // selection rather than silently pointing at a list that no longer
    // exists.
    private func clearPersonalListIfDeleted() {
        guard let personalListID, !taskLists.contains(where: { $0.id == personalListID }) else { return }
        print("[Tasks] Personal list \(personalListID) no longer exists — clearing selection")
        self.personalListID = nil
    }

    func loadTaskLists() async {
        print("[Tasks] Loading task lists")
        do {
            let token = try await authManager.validAccessToken()
            taskLists = try await service.fetchTaskLists(accessToken: token)
            clearPersonalListIfDeleted()
            backfillAutoMoveListIDsIfNeeded()
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
            clearPersonalListIfDeleted()
            backfillAutoMoveListIDsIfNeeded()

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
            var seenTaskIDs: Set<String> = []

            for list in remoteLists {
                let remoteTasks = try await service.fetchTasks(listID: list.id, accessToken: token)

                for remote in remoteTasks where remote.deleted != true {
                    seenTaskIDs.insert(remote.id)
                    let remoteUpdated = remote.updatedDate ?? Date()

                    if let existing = localByGoogleID[remote.id] {
                        existing.googleListID = list.id
                        let localModified = existing.lastModified ?? .distantPast
                        guard remoteUpdated > localModified else { continue }
                        existing.title = remote.title ?? ""
                        existing.isCompleted = remote.isCompleted
                        // Google Tasks only stores a date, not a time. A task
                        // with a linked calendar event uses dueDate to hold
                        // that event's precise start time, so leave it alone
                        // here — Calendar owns the time, not Tasks.
                        if existing.calendarEventID == nil {
                            existing.dueDate = remote.dueDate
                        }
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
            // A task whose list still exists but whose own ID never showed up
            // in that list's fetch means the task itself was deleted on
            // Google (e.g. from another device) — drop it locally too.
            let validListIDs = Set(remoteLists.map(\.id))
            var removedCount = 0
            for item in localItems {
                guard let listID = item.googleListID else { continue }
                let listGone = !validListIDs.contains(listID)
                let taskGone = !listGone && item.googleTaskID != nil && !seenTaskIDs.contains(item.googleTaskID!)
                guard listGone || taskGone else { continue }
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

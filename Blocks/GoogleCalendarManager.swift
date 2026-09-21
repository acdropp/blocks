import Foundation
import Combine
import SwiftData

struct CalendarPullOutcome {
    let updated: [TodoItem]
    let cleared: [TodoItem]
}

struct LegacyBlockMigrationOutcome {
    let moved: Int
    let failed: Int
}

private enum CalendarEventFetchResult {
    case found(GoogleCalendarEvent)
    case deleted
    case failed
}

/// Fetches the given events concurrently rather than one at a time. Takes
/// `service` and `accessToken` as plain values (not `self`) so each fetch
/// can run off the main actor without capturing MainActor-isolated state.
private func fetchCalendarEvents(requests: [(eventID: String, calendarID: String)], accessToken: String, service: GoogleCalendarService) async -> [String: CalendarEventFetchResult] {
    await withTaskGroup(of: (String, CalendarEventFetchResult).self) { group in
        for request in requests {
            group.addTask {
                do {
                    if let event = try await service.fetchEvent(calendarID: request.calendarID, eventID: request.eventID, accessToken: accessToken) {
                        return (request.eventID, .found(event))
                    } else {
                        return (request.eventID, .deleted)
                    }
                } catch {
                    print("[Calendar] Failed to fetch event \(request.eventID): \(error.localizedDescription)")
                    return (request.eventID, .failed)
                }
            }
        }
        var results: [String: CalendarEventFetchResult] = [:]
        for await (eventID, result) in group {
            results[eventID] = result
        }
        return results
    }
}

@MainActor
final class GoogleCalendarManager: ObservableObject {
    private static let blocksCalendarIDKey = "blocksCalendarID"
    static let blocksCalendarName = "Blocks"

    @Published private(set) var errorMessage: String?
    @Published private(set) var calendars: [GoogleCalendarListEntry] = []
    @Published var blocksCalendarID: String? {
        didSet {
            UserDefaults.standard.set(blocksCalendarID, forKey: Self.blocksCalendarIDKey)
        }
    }

    private let service = GoogleCalendarService()
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.blocksCalendarID = UserDefaults.standard.string(forKey: Self.blocksCalendarIDKey)
    }

    /// Creates the "Blocks" calendar the first time it's needed and
    /// remembers its ID locally from then on. Deliberately does NOT list
    /// existing calendars first to check for one already named "Blocks" —
    /// the calendar.app.created scope only covers creating/managing
    /// calendars this app made, not listing the user's full calendar list
    /// (that's a separate, broader scope), so listing would always fail.
    func ensureBlocksCalendar() async -> String? {
        if let blocksCalendarID { return blocksCalendarID }
        do {
            let token = try await authManager.validAccessToken()
            let created = try await service.insertCalendar(summary: Self.blocksCalendarName, accessToken: token)
            calendars.append(created)
            blocksCalendarID = created.id
            return created.id
        } catch {
            print("[Calendar] Failed to set up the \"\(Self.blocksCalendarName)\" calendar: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Creates a new time block, or updates the task's existing one if it
    /// already has a linked event. New blocks go on the Blocks calendar
    /// (created on first use); updates to an existing block stay on
    /// whatever calendar it's already on. Returns true on success.
    @discardableResult
    func scheduleBlock(for item: TodoItem, duration: TimeInterval, startTime: Date, listName: String?) async -> Bool {
        if item.blocksTaskID == nil {
            item.blocksTaskID = UUID().uuidString
        }
        let endTime = startTime.addingTimeInterval(duration)

        print("[Calendar] Scheduling block for \"\(item.title)\": \(startTime) for \(Int(duration / 60))m")
        do {
            let token = try await authManager.validAccessToken()
            let event: GoogleCalendarEvent
            if let eventID = item.calendarEventID {
                let calendarID = item.calendarID ?? "primary"
                event = try await service.updateEvent(calendarID: calendarID, eventID: eventID, title: Self.eventTitle(for: item), start: startTime, end: endTime, description: listName, accessToken: token)
            } else {
                guard let calendarID = await ensureBlocksCalendar() else {
                    errorMessage = "Couldn't set up the Blocks calendar."
                    return false
                }
                event = try await service.insertEvent(calendarID: calendarID, title: Self.eventTitle(for: item), start: startTime, end: endTime, description: listName, blocksTaskID: item.blocksTaskID!, accessToken: token)
                item.calendarID = calendarID
            }
            item.calendarEventID = event.id
            item.dueDate = startTime
            item.blockDurationSeconds = duration
            item.lastModified = Date()
            errorMessage = nil
            print("[Calendar] Block confirmed for \"\(item.title)\": event \(event.id) on calendar \(item.calendarID ?? "primary")")
            return true
        } catch {
            print("[Calendar] Failed to schedule block for \"\(item.title)\": \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Reconciles every scheduled task's block with its linked calendar
    /// event. If the event's time changed on Google's side, updates the
    /// task to match — Calendar always wins over what Blocks/Tasks has,
    /// since editing the event directly is how a block gets moved. If the
    /// event was deleted, clears the task's block; the task itself is
    /// never deleted. Only checks tasks that have a block, and fetches
    /// all their events concurrently.
    func pullChanges(context: ModelContext) async -> CalendarPullOutcome {
        let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate<TodoItem> { $0.calendarEventID != nil })
        guard let items = try? context.fetch(descriptor), !items.isEmpty else {
            return CalendarPullOutcome(updated: [], cleared: [])
        }

        let requests = items.compactMap { item -> (eventID: String, calendarID: String)? in
            guard let eventID = item.calendarEventID else { return nil }
            return (eventID, item.calendarID ?? "primary")
        }
        print("[Calendar] Pulling changes for \(requests.count) linked event(s)")

        var updated: [TodoItem] = []
        var cleared: [TodoItem] = []
        do {
            let token = try await authManager.validAccessToken()
            let results = await fetchCalendarEvents(requests: requests, accessToken: token, service: service)

            for item in items {
                guard let eventID = item.calendarEventID, let result = results[eventID] else { continue }
                switch result {
                case .failed:
                    continue

                case .deleted:
                    print("[Calendar] Event \(eventID) for \"\(item.title)\" was deleted on Google — clearing block")
                    item.calendarEventID = nil
                    item.calendarID = nil
                    item.dueDate = nil
                    item.blockDurationSeconds = nil
                    item.lastModified = Date()
                    cleared.append(item)

                case .found(let event):
                    guard let start = event.startDate, let end = event.endDate else { continue }
                    let duration = end.timeIntervalSince(start)
                    let startChanged = item.dueDate.map { abs($0.timeIntervalSince(start)) > 1 } ?? true
                    let durationChanged = item.blockDurationSeconds.map { abs($0 - duration) > 1 } ?? true
                    guard startChanged || durationChanged else { continue }

                    print("[Calendar] Event \(eventID) for \"\(item.title)\" changed on Google — updating block to \(start) for \(Int(duration / 60))m")
                    item.dueDate = start
                    item.blockDurationSeconds = duration
                    item.lastModified = Date()
                    updated.append(item)
                }
            }
            errorMessage = nil
        } catch {
            print("[Calendar] Pull failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        return CalendarPullOutcome(updated: updated, cleared: cleared)
    }

    /// The calendar event title for a task: "✓ <title>" when complete,
    /// plain <title> otherwise. Always computed fresh from the task's own
    /// title and completion state — never by editing whatever string is
    /// already on the event — so it can never end up with two checkmarks.
    private static func eventTitle(for item: TodoItem) -> String {
        item.isCompleted ? "✓ \(item.title)" : item.title
    }

    /// Renames the task's calendar event to reflect its current completion
    /// state (adds/removes the "✓ " prefix). No-op if the task has no
    /// block. Safe to call any time completion changes, from either side.
    func updateEventCompletionMark(for item: TodoItem, listName: String?) async {
        guard let eventID = item.calendarEventID, let dueDate = item.dueDate, let duration = item.blockDurationSeconds else { return }
        let calendarID = item.calendarID ?? "primary"
        let title = Self.eventTitle(for: item)
        print("[Calendar] Updating completion mark for \"\(item.title)\": \(item.isCompleted ? "checked" : "unchecked")")
        do {
            let token = try await authManager.validAccessToken()
            let endTime = dueDate.addingTimeInterval(duration)
            _ = try await service.updateEvent(calendarID: calendarID, eventID: eventID, title: title, start: dueDate, end: endTime, description: listName, accessToken: token)
            errorMessage = nil
        } catch {
            print("[Calendar] Failed to update completion mark for \"\(item.title)\": \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a calendar event, retrying a couple of times on HTTP 412
    /// (conditionNotMet). Google Calendar returns that intermittently when
    /// a calendar gets rapid back-to-back writes (e.g. quickly removing and
    /// rescheduling a block several times in a row) — it's usually transient.
    /// Retrying here matters: once this returns, the caller forgets the
    /// event's ID, so a failure that isn't retried leaves the event
    /// orphaned on Google Calendar forever with no way to clean it up later.
    func deleteBlock(calendarID: String?, eventID: String) async {
        print("[Calendar] Deleting event \(eventID)")
        let resolvedCalendarID = calendarID ?? "primary"
        var attempt = 1
        while true {
            do {
                let token = try await authManager.validAccessToken()
                try await service.deleteEvent(calendarID: resolvedCalendarID, eventID: eventID, accessToken: token)
                errorMessage = nil
                return
            } catch let error as GoogleCalendarError {
                if case .requestFailed(let status, _) = error, status == 412, attempt < 3 {
                    print("[Calendar] Delete of \(eventID) hit a transient conflict (HTTP 412) — retrying (attempt \(attempt + 1))")
                    attempt += 1
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    continue
                }
                print("[Calendar] Failed to delete event \(eventID): \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                return
            } catch {
                print("[Calendar] Failed to delete event \(eventID): \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    /// Moves every block still on the primary calendar (created before the
    /// Blocks calendar existed) over to it: inserts a fresh event there
    /// with the same details, then deletes the original.
    func migrateLegacyBlocksToBlocksCalendar(items: [TodoItem], listNamesByID: [String: String]) async -> LegacyBlockMigrationOutcome {
        guard !items.isEmpty else { return LegacyBlockMigrationOutcome(moved: 0, failed: 0) }
        guard let calendarID = await ensureBlocksCalendar() else {
            return LegacyBlockMigrationOutcome(moved: 0, failed: items.count)
        }

        var moved = 0
        var failed = 0
        do {
            let token = try await authManager.validAccessToken()
            for item in items {
                guard let oldEventID = item.calendarEventID, let dueDate = item.dueDate, let duration = item.blockDurationSeconds else {
                    failed += 1
                    continue
                }
                let endTime = dueDate.addingTimeInterval(duration)
                let listName = item.googleListID.flatMap { listNamesByID[$0] }
                do {
                    let newEvent = try await service.insertEvent(
                        calendarID: calendarID,
                        title: Self.eventTitle(for: item),
                        start: dueDate,
                        end: endTime,
                        description: listName,
                        blocksTaskID: item.blocksTaskID ?? UUID().uuidString,
                        accessToken: token
                    )
                    try await service.deleteEvent(calendarID: "primary", eventID: oldEventID, accessToken: token)
                    item.calendarEventID = newEvent.id
                    item.calendarID = calendarID
                    item.lastModified = Date()
                    moved += 1
                    print("[Calendar] Moved block for \"\(item.title)\" to Blocks calendar: \(newEvent.id)")
                } catch {
                    print("[Calendar] Failed to move block for \"\(item.title)\": \(error.localizedDescription)")
                    failed += 1
                }
            }
            errorMessage = nil
        } catch {
            print("[Calendar] Migration failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            failed += items.count - moved
        }
        return LegacyBlockMigrationOutcome(moved: moved, failed: failed)
    }
}

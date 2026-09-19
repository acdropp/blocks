import Foundation
import Combine
import SwiftData

struct CalendarPullOutcome {
    let updated: [TodoItem]
    let cleared: [TodoItem]
}

private enum CalendarEventFetchResult {
    case found(GoogleCalendarEvent)
    case deleted
    case failed
}

/// Fetches the given events concurrently rather than one at a time. Takes
/// `service` and `accessToken` as plain values (not `self`) so each fetch
/// can run off the main actor without capturing MainActor-isolated state.
private func fetchCalendarEvents(eventIDs: [String], accessToken: String, service: GoogleCalendarService) async -> [String: CalendarEventFetchResult] {
    await withTaskGroup(of: (String, CalendarEventFetchResult).self) { group in
        for eventID in eventIDs {
            group.addTask {
                do {
                    if let event = try await service.fetchEvent(eventID: eventID, accessToken: accessToken) {
                        return (eventID, .found(event))
                    } else {
                        return (eventID, .deleted)
                    }
                } catch {
                    print("[Calendar] Failed to fetch event \(eventID): \(error.localizedDescription)")
                    return (eventID, .failed)
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
    @Published private(set) var errorMessage: String?

    private let service = GoogleCalendarService()
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    /// Creates a new time block, or updates the task's existing one if it
    /// already has a linked event. Returns true on success.
    @discardableResult
    func scheduleBlock(for item: TodoItem, duration: TimeInterval, startTime: Date) async -> Bool {
        if item.blocksTaskID == nil {
            item.blocksTaskID = UUID().uuidString
        }
        let endTime = startTime.addingTimeInterval(duration)

        print("[Calendar] Scheduling block for \"\(item.title)\": \(startTime) for \(Int(duration / 60))m")
        do {
            let token = try await authManager.validAccessToken()
            let event: GoogleCalendarEvent
            if let eventID = item.calendarEventID {
                event = try await service.updateEvent(eventID: eventID, title: item.title, start: startTime, end: endTime, accessToken: token)
            } else {
                event = try await service.insertEvent(title: item.title, start: startTime, end: endTime, blocksTaskID: item.blocksTaskID!, accessToken: token)
            }
            item.calendarEventID = event.id
            item.dueDate = startTime
            item.blockDurationSeconds = duration
            item.lastModified = Date()
            errorMessage = nil
            print("[Calendar] Block confirmed for \"\(item.title)\": event \(event.id)")
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

        let eventIDs = items.compactMap(\.calendarEventID)
        print("[Calendar] Pulling changes for \(eventIDs.count) linked event(s)")

        var updated: [TodoItem] = []
        var cleared: [TodoItem] = []
        do {
            let token = try await authManager.validAccessToken()
            let results = await fetchCalendarEvents(eventIDs: eventIDs, accessToken: token, service: service)

            for item in items {
                guard let eventID = item.calendarEventID, let result = results[eventID] else { continue }
                switch result {
                case .failed:
                    continue

                case .deleted:
                    print("[Calendar] Event \(eventID) for \"\(item.title)\" was deleted on Google — clearing block")
                    item.calendarEventID = nil
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

    func deleteBlock(eventID: String) async {
        print("[Calendar] Deleting event \(eventID)")
        do {
            let token = try await authManager.validAccessToken()
            try await service.deleteEvent(eventID: eventID, accessToken: token)
            errorMessage = nil
        } catch {
            print("[Calendar] Failed to delete event \(eventID): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

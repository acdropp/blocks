import Foundation
import Combine

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

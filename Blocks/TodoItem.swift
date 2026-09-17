import Foundation
import SwiftData

enum TodoSection: String, Codable {
    case topPriority
    case other
}

@Model
final class TodoItem {
    var title: String
    var isCompleted: Bool
    var section: TodoSection
    var dueDate: Date?
    var createdAt: Date
    var googleTaskID: String?
    var googleListID: String?
    var lastModified: Date?
    var blocksTaskID: String?
    var calendarEventID: String?
    var blockDurationSeconds: Double?

    init(title: String, section: TodoSection = .other) {
        self.title = title
        self.isCompleted = false
        self.section = section
        self.dueDate = nil
        self.createdAt = Date()
        self.googleTaskID = nil
        self.googleListID = nil
        self.lastModified = nil
        self.blocksTaskID = nil
        self.calendarEventID = nil
        self.blockDurationSeconds = nil
    }
}

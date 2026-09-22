import Foundation
import SwiftData

enum TodoSection: String, Codable {
    case topPriority
    case workPriority
    case chores
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
    // Which calendar calendarEventID lives on. nil means "primary" — every
    // block created before the Blocks calendar existed has no value here.
    var calendarID: String?
    var blockDurationSeconds: Double?
    var manualOrder: Double?
    // A lightweight markdown-ish note: **bold**, *italic*, _underline_,
    // [text](url) links, and lines starting "- " or "1. " for lists. Synced
    // both ways with Google Tasks' plain-text `notes` field, and pushed
    // (one-way only) into the Calendar event's description.
    var notes: String?

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
        self.calendarID = nil
        self.blockDurationSeconds = nil
        self.manualOrder = nil
        self.notes = nil
    }
}

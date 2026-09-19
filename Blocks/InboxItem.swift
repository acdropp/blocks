import Foundation
import SwiftData

@Model
final class InboxItem {
    var text: String
    var meetingName: String
    var accountName: String = ""
    var dedupKey: String
    var createdAt: Date

    init(text: String, meetingName: String, accountName: String, dedupKey: String) {
        self.text = text
        self.meetingName = meetingName
        self.accountName = accountName
        self.dedupKey = dedupKey
        self.createdAt = Date()
    }
}

/// Permanent record that an action item's de-dup key has been imported
/// before. Rows here are never deleted, even after the matching InboxItem
/// is accepted or dismissed, so a dismissed item never comes back.
@Model
final class SeenFathomItem {
    var key: String

    init(key: String) {
        self.key = key
    }
}

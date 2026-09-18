import Foundation
import Combine
import SwiftData

@MainActor
final class FathomManager: ObservableObject {
    private static let lastFetchKey = "fathomLastFetchDate"

    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var errorMessage: String?

    private let service = FathomService()
    private var isFetching = false
    private var isRejected = false

    init() {
        self.hasAPIKey = FathomKeychain.load() != nil
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard FathomKeychain.save(trimmed) else {
            errorMessage = "Couldn't save the key to Keychain."
            return
        }
        hasAPIKey = true
        isRejected = false
        errorMessage = nil
        print("[Fathom] API key saved")
    }

    func removeAPIKey() {
        FathomKeychain.delete()
        hasAPIKey = false
        isRejected = false
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: Self.lastFetchKey)
        print("[Fathom] API key removed")
    }

    func fetchNewActionItems(context: ModelContext) async {
        guard hasAPIKey else { return }
        guard !isRejected else {
            print("[Fathom] Skipping fetch: key was previously rejected")
            return
        }
        guard !isFetching else {
            print("[Fathom] Fetch already in progress, skipping")
            return
        }
        guard let apiKey = FathomKeychain.load() else {
            hasAPIKey = false
            return
        }

        isFetching = true
        defer { isFetching = false }

        let lastFetch = (UserDefaults.standard.object(forKey: Self.lastFetchKey) as? Date) ?? Date()
        let fetchStarted = Date()

        print("[Fathom] Fetching meetings created after \(lastFetch)")
        do {
            let meetings = try await service.fetchMeetings(createdAfter: lastFetch, apiKey: apiKey)

            let seenKeys = Set(try context.fetch(FetchDescriptor<SeenFathomItem>()).map(\.key))
            var importedCount = 0

            for meeting in meetings {
                for actionItem in meeting.actionItems ?? [] {
                    let key = Self.dedupKey(recordingId: meeting.recordingId, item: actionItem)
                    guard !seenKeys.contains(key) else { continue }

                    let inboxItem = InboxItem(text: actionItem.description, meetingName: meeting.displayName, dedupKey: key)
                    context.insert(inboxItem)
                    context.insert(SeenFathomItem(key: key))
                    importedCount += 1
                }
            }

            UserDefaults.standard.set(fetchStarted, forKey: Self.lastFetchKey)
            errorMessage = nil
            print("[Fathom] Imported \(importedCount) new action item(s)")
        } catch FathomError.requestFailed(let status) where status == 401 || status == 403 {
            print("[Fathom] API key rejected: HTTP \(status)")
            isRejected = true
            errorMessage = "Fathom API key was rejected."
        } catch {
            print("[Fathom] Fetch failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private static func dedupKey(recordingId: Int?, item: FathomActionItem) -> String {
        "\(recordingId ?? 0)|\(item.recordingTimestamp ?? "")|\(item.description)"
    }
}

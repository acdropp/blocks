import Foundation
import Combine
import SwiftData

/// A configured Fathom account. Only the name and a generated ID are stored
/// here (UserDefaults); the API key itself lives only in the Keychain.
struct FathomAccount: Identifiable, Codable {
    let id: String
    var name: String
}

@MainActor
final class FathomManager: ObservableObject {
    private static let accountsKey = "fathomAccounts"
    private static let legacyLastFetchKey = "fathomLastFetchDate"
    private static let defaultAccountName = "Fathom Work Email"

    @Published private(set) var accounts: [FathomAccount] = []
    @Published private(set) var accountErrors: [String: String] = [:]

    private let service = FathomService()
    private var isFetching = false
    private var rejectedAccountIDs: Set<String> = []

    init() {
        accounts = Self.loadAccounts()
        migrateLegacyAccountIfNeeded()
        renameDefaultAccountIfNeeded()
    }

    // MARK: - Account management

    func addAccount(name: String, apiKey: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedKey.isEmpty else { return }

        let id = UUID().uuidString
        guard FathomKeychain.save(trimmedKey, accountID: id) else {
            accountErrors[id] = "Couldn't save the key to Keychain."
            return
        }
        accounts.append(FathomAccount(id: id, name: trimmedName))
        persistAccounts()
        print("[Fathom] Added account \"\(trimmedName)\"")
    }

    func removeAccount(_ account: FathomAccount) {
        FathomKeychain.delete(accountID: account.id)
        UserDefaults.standard.removeObject(forKey: lastFetchKey(for: account.id))
        accounts.removeAll { $0.id == account.id }
        accountErrors[account.id] = nil
        rejectedAccountIDs.remove(account.id)
        persistAccounts()
        print("[Fathom] Removed account \"\(account.name)\"")
    }

    // MARK: - Fetching

    func fetchNewActionItems(context: ModelContext) async {
        guard !accounts.isEmpty else { return }
        guard !isFetching else {
            print("[Fathom] Fetch already in progress, skipping")
            return
        }
        isFetching = true
        defer { isFetching = false }

        for account in accounts {
            await fetch(for: account, context: context)
        }
    }

    private func fetch(for account: FathomAccount, context: ModelContext) async {
        guard !rejectedAccountIDs.contains(account.id) else {
            print("[Fathom] Skipping \"\(account.name)\": key was previously rejected")
            return
        }
        guard let apiKey = FathomKeychain.load(accountID: account.id) else {
            accountErrors[account.id] = "No key saved for this account."
            return
        }

        let fetchKey = lastFetchKey(for: account.id)
        let lastFetch = (UserDefaults.standard.object(forKey: fetchKey) as? Date) ?? Date()
        let fetchStarted = Date()

        print("[Fathom] Fetching meetings for \"\(account.name)\" created after \(lastFetch)")
        do {
            let meetings = try await service.fetchMeetings(createdAfter: lastFetch, apiKey: apiKey)

            let seenKeys = Set(try context.fetch(FetchDescriptor<SeenFathomItem>()).map(\.key))
            var importedCount = 0

            for meeting in meetings {
                for actionItem in meeting.actionItems ?? [] {
                    let dedupKey = Self.dedupKey(accountID: account.id, recordingId: meeting.recordingId, item: actionItem)
                    guard !seenKeys.contains(dedupKey) else { continue }

                    let inboxItem = InboxItem(text: actionItem.description, meetingName: meeting.displayName, accountName: account.name, assigneeName: actionItem.assignee?.name, dedupKey: dedupKey)
                    context.insert(inboxItem)
                    context.insert(SeenFathomItem(key: dedupKey))
                    importedCount += 1
                }
            }

            UserDefaults.standard.set(fetchStarted, forKey: fetchKey)
            accountErrors[account.id] = nil
            print("[Fathom] Imported \(importedCount) new action item(s) for \"\(account.name)\"")
        } catch FathomError.requestFailed(let status) where status == 401 || status == 403 {
            print("[Fathom] API key rejected for \"\(account.name)\": HTTP \(status)")
            rejectedAccountIDs.insert(account.id)
            accountErrors[account.id] = "API key was rejected."
        } catch {
            print("[Fathom] Fetch failed for \"\(account.name)\": \(error.localizedDescription)")
            accountErrors[account.id] = error.localizedDescription
        }
    }

    private func lastFetchKey(for accountID: String) -> String {
        "fathomLastFetchDate.\(accountID)"
    }

    private static func dedupKey(accountID: String, recordingId: Int?, item: FathomActionItem) -> String {
        "\(accountID)|\(recordingId ?? 0)|\(item.recordingTimestamp ?? "")|\(item.description)"
    }

    // MARK: - Persistence

    private static func loadAccounts() -> [FathomAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else { return [] }
        return (try? JSONDecoder().decode([FathomAccount].self, from: data)) ?? []
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.accountsKey)
    }

    /// Existing single-key installs get one account named "Fathom Work
    /// Email", carrying over its saved key and fetch history so nothing
    /// re-imports.
    private func migrateLegacyAccountIfNeeded() {
        guard accounts.isEmpty, let legacyKey = FathomKeychain.loadLegacyKey() else { return }

        let id = UUID().uuidString
        guard FathomKeychain.save(legacyKey, accountID: id) else {
            print("[Fathom] Failed to migrate existing key to per-account storage")
            return
        }
        FathomKeychain.deleteLegacyKey()

        accounts = [FathomAccount(id: id, name: Self.defaultAccountName)]
        persistAccounts()

        if let legacyLastFetch = UserDefaults.standard.object(forKey: Self.legacyLastFetchKey) as? Date {
            UserDefaults.standard.set(legacyLastFetch, forKey: lastFetchKey(for: id))
            UserDefaults.standard.removeObject(forKey: Self.legacyLastFetchKey)
        }

        print("[Fathom] Migrated existing Fathom key to account \"\(Self.defaultAccountName)\"")
    }

    /// One-time fixup for installs that already migrated under the old
    /// default name "Work" before it was renamed.
    private func renameDefaultAccountIfNeeded() {
        guard let index = accounts.firstIndex(where: { $0.name == "Work" }) else { return }
        accounts[index].name = Self.defaultAccountName
        persistAccounts()
        print("[Fathom] Renamed default account to \"\(Self.defaultAccountName)\"")
    }
}

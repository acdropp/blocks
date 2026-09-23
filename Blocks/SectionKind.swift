import Foundation

/// The six sections whose show/hide, name, and display order are all
/// customizable from Settings. "From Meetings" isn't included — it has no
/// show/hide toggle either, and always sits above the sort header, first.
enum SectionKind: String, CaseIterable, Identifiable {
    case topPriorities, workPriorities, chores, otherToDos, completed, personal

    var id: String { rawValue }

    static let defaultOrder: [SectionKind] = allCases
    static let defaultOrderString = defaultOrder.map(\.rawValue).joined(separator: ",")

    /// Parses the "a,b,c" string ContentView and SettingsView both store
    /// under the shared "sectionOrder" AppStorage key. Any section missing
    /// from a stale/partial saved string (e.g. after an app update adds a
    /// new one) is appended at the end, in its default position, so it's
    /// never silently dropped from the list.
    static func parseOrder(_ raw: String) -> [SectionKind] {
        let saved = raw.split(separator: ",").compactMap { SectionKind(rawValue: String($0)) }
        let missing = defaultOrder.filter { !saved.contains($0) }
        return saved + missing
    }
}

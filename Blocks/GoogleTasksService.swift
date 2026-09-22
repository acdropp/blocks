import Foundation

struct GoogleTaskList: Identifiable, Codable {
    let id: String
    let title: String
}

struct GoogleTask: Codable {
    let id: String
    let title: String?
    let status: String?
    let due: String?
    let updated: String?
    let deleted: Bool?
    let notes: String?

    var isCompleted: Bool { status == "completed" }
    var updatedDate: Date? { Self.parseDate(updated) }
    var dueDate: Date? { Self.parseDate(due) }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }
}

private struct PatchTaskBody: Encodable {
    let title: String
    let status: String
    let due: String?
    // Always sent, even when empty — unlike `due`, there's no separate
    // "clear notes" endpoint, so an empty string is how a cleared note is
    // represented on Google's side too.
    let notes: String

    private enum CodingKeys: String, CodingKey {
        case title, status, due, notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(status, forKey: .status)
        if let due {
            try container.encode(due, forKey: .due)
        }
        try container.encode(notes, forKey: .notes)
    }
}

/// Explicitly sends `"due": null` to clear a task's due date — unlike
/// PatchTaskBody, this intentionally does NOT omit the key when nil.
private struct ClearDueBody: Encodable {
    let due: String? = nil
}

enum GoogleTasksError: LocalizedError {
    case requestFailed(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status, _):
            return "Google Tasks request failed (HTTP \(status))."
        }
    }
}

struct GoogleTasksService {
    private let baseURL = URL(string: "https://tasks.googleapis.com/tasks/v1")!

    func fetchTaskLists(accessToken: String) async throws -> [GoogleTaskList] {
        var allLists: [GoogleTaskList] = []
        var pageToken: String?

        repeat {
            var queryItems = [URLQueryItem(name: "maxResults", value: "100")]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var components = URLComponents(url: baseURL.appendingPathComponent("users/@me/lists"), resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            let url = components.url!

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            print("[Tasks] GET \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkResponse(response, data: data, context: "fetch task lists")

            let decoded = try JSONDecoder().decode(TaskListsResponse.self, from: data)
            allLists.append(contentsOf: decoded.items ?? [])
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        print("[Tasks] Fetched \(allLists.count) task list(s) total")
        return allLists
    }

    private struct TaskListsResponse: Codable {
        let items: [GoogleTaskList]?
        let nextPageToken: String?
    }

    func fetchTasks(listID: String, accessToken: String) async throws -> [GoogleTask] {
        var allTasks: [GoogleTask] = []
        var pageToken: String?

        repeat {
            var queryItems = [
                URLQueryItem(name: "maxResults", value: "100"),
                URLQueryItem(name: "showCompleted", value: "true"),
                URLQueryItem(name: "showHidden", value: "true"),
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var components = URLComponents(url: baseURL.appendingPathComponent("lists/\(listID)/tasks"), resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            let url = components.url!

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            print("[Tasks] GET \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkResponse(response, data: data, context: "fetch tasks")

            let decoded = try JSONDecoder().decode(TasksResponse.self, from: data)
            allTasks.append(contentsOf: decoded.items ?? [])
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        print("[Tasks] Fetched \(allTasks.count) task(s) total for list \(listID)")
        return allTasks
    }

    private struct TasksResponse: Codable {
        let items: [GoogleTask]?
        let nextPageToken: String?
    }

    func insertTask(listID: String, title: String, accessToken: String) async throws -> GoogleTask {
        let url = baseURL.appendingPathComponent("lists/\(listID)/tasks")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title])

        print("[Tasks] POST \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "insert task")

        let task = try JSONDecoder().decode(GoogleTask.self, from: data)
        print("[Tasks] Inserted task \(task.id)")
        return task
    }

    func patchTask(listID: String, taskID: String, title: String, isCompleted: Bool, due: Date? = nil, notes: String = "", accessToken: String) async throws -> GoogleTask {
        let url = baseURL.appendingPathComponent("lists/\(listID)/tasks/\(taskID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PatchTaskBody(
            title: title,
            status: isCompleted ? "completed" : "needsAction",
            due: due.map(Self.formatDueDate),
            notes: notes
        ))

        print("[Tasks] PATCH \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "update task")

        let task = try JSONDecoder().decode(GoogleTask.self, from: data)
        print("[Tasks] Updated task \(task.id)")
        return task
    }

    func clearDueDate(listID: String, taskID: String, accessToken: String) async throws -> GoogleTask {
        let url = baseURL.appendingPathComponent("lists/\(listID)/tasks/\(taskID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ClearDueBody())

        print("[Tasks] PATCH \(url.absoluteString) (clear due date)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "clear due date")

        let task = try JSONDecoder().decode(GoogleTask.self, from: data)
        print("[Tasks] Cleared due date for task \(task.id)")
        return task
    }

    func moveTask(listID: String, taskID: String, destinationListID: String, accessToken: String) async throws -> GoogleTask {
        var components = URLComponents(url: baseURL.appendingPathComponent("lists/\(listID)/tasks/\(taskID)/move"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "destinationTasklist", value: destinationListID)]
        let url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("[Tasks] POST \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "move task")

        let task = try JSONDecoder().decode(GoogleTask.self, from: data)
        print("[Tasks] Moved task \(task.id) to list \(destinationListID)")
        return task
    }

    func deleteTask(listID: String, taskID: String, accessToken: String) async throws {
        let url = baseURL.appendingPathComponent("lists/\(listID)/tasks/\(taskID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("[Tasks] DELETE \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "delete task")
        print("[Tasks] Deleted task \(taskID)")
    }

    private static func formatDueDate(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02dT00:00:00.000Z", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    private static func checkResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Tasks] \(context) failed: HTTP \(httpResponse.statusCode) \(body)")
            throw GoogleTasksError.requestFailed(status: httpResponse.statusCode, body: body)
        }
    }
}

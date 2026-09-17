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
        let url = baseURL.appendingPathComponent("users/@me/lists")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("[Tasks] GET \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "fetch task lists")

        let decoded = try JSONDecoder().decode(TaskListsResponse.self, from: data)
        print("[Tasks] Fetched \(decoded.items?.count ?? 0) task list(s)")
        return decoded.items ?? []
    }

    private struct TaskListsResponse: Codable {
        let items: [GoogleTaskList]?
    }

    func fetchTasks(listID: String, accessToken: String) async throws -> [GoogleTask] {
        let url = baseURL.appendingPathComponent("lists/\(listID)/tasks")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("[Tasks] GET \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "fetch tasks")

        let decoded = try JSONDecoder().decode(TasksResponse.self, from: data)
        print("[Tasks] Fetched \(decoded.items?.count ?? 0) task(s)")
        return decoded.items ?? []
    }

    private struct TasksResponse: Codable {
        let items: [GoogleTask]?
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

    func patchTask(listID: String, taskID: String, title: String, isCompleted: Bool, accessToken: String) async throws -> GoogleTask {
        let url = baseURL.appendingPathComponent("lists/\(listID)/tasks/\(taskID)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "title": title,
            "status": isCompleted ? "completed" : "needsAction",
        ])

        print("[Tasks] PATCH \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "update task")

        let task = try JSONDecoder().decode(GoogleTask.self, from: data)
        print("[Tasks] Updated task \(task.id)")
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

    private static func checkResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Tasks] \(context) failed: HTTP \(httpResponse.statusCode) \(body)")
            throw GoogleTasksError.requestFailed(status: httpResponse.statusCode, body: body)
        }
    }
}

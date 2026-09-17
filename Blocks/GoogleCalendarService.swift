import Foundation

struct GoogleCalendarEvent: Codable {
    let id: String
}

enum GoogleCalendarError: LocalizedError {
    case requestFailed(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status, _):
            return "Google Calendar request failed (HTTP \(status))."
        }
    }
}

private struct EventDateTime: Encodable {
    let dateTime: String
    let timeZone: String
}

private struct ExtendedProperties: Encodable {
    let `private`: [String: String]
}

private struct InsertEventBody: Encodable {
    let summary: String
    let start: EventDateTime
    let end: EventDateTime
    let extendedProperties: ExtendedProperties
}

private struct UpdateEventBody: Encodable {
    let summary: String
    let start: EventDateTime
    let end: EventDateTime
}

struct GoogleCalendarService {
    private let baseURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!

    func insertEvent(title: String, start: Date, end: Date, blocksTaskID: String, accessToken: String) async throws -> GoogleCalendarEvent {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(InsertEventBody(
            summary: title,
            start: Self.eventDateTime(start),
            end: Self.eventDateTime(end),
            extendedProperties: ExtendedProperties(private: ["blocksTaskID": blocksTaskID])
        ))

        print("[Calendar] POST \(baseURL.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "insert event")

        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        print("[Calendar] Inserted event \(event.id)")
        return event
    }

    func updateEvent(eventID: String, title: String, start: Date, end: Date, accessToken: String) async throws -> GoogleCalendarEvent {
        let url = baseURL.appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(UpdateEventBody(
            summary: title,
            start: Self.eventDateTime(start),
            end: Self.eventDateTime(end)
        ))

        print("[Calendar] PATCH \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "update event")

        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        print("[Calendar] Updated event \(event.id)")
        return event
    }

    func deleteEvent(eventID: String, accessToken: String) async throws {
        let url = baseURL.appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("[Calendar] DELETE \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "delete event")
        print("[Calendar] Deleted event \(eventID)")
    }

    private static func eventDateTime(_ date: Date) -> EventDateTime {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return EventDateTime(dateTime: formatter.string(from: date), timeZone: TimeZone.current.identifier)
    }

    private static func checkResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[Calendar] \(context) failed: HTTP \(httpResponse.statusCode) \(body)")
            throw GoogleCalendarError.requestFailed(status: httpResponse.statusCode, body: body)
        }
    }
}

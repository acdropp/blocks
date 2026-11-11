import Foundation

struct GoogleCalendarEvent: Codable {
    let id: String
    let status: String?
    let summary: String?
    let start: EventDateTimeResponse?
    let end: EventDateTimeResponse?
    let extendedProperties: ExtendedProperties?

    /// The Google Tasks ID this event is linked to, if any app (Blocks or
    /// Make It So) stored one on it.
    var googleTaskID: String? { extendedProperties?.private?["googleTaskID"] }

    var startDate: Date? { start?.dateTime.flatMap(GoogleCalendarService.parseDate) }
    var endDate: Date? { end?.dateTime.flatMap(GoogleCalendarService.parseDate) }
}

struct EventDateTimeResponse: Codable {
    let dateTime: String?
    let date: String?
}

struct GoogleCalendarListEntry: Codable, Identifiable {
    let id: String
    let summary: String
}

private struct InsertCalendarBody: Encodable {
    let summary: String
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

struct ExtendedProperties: Codable {
    let `private`: [String: String]?
}

private struct InsertEventBody: Encodable {
    let summary: String
    let description: String?
    let start: EventDateTime
    let end: EventDateTime
    let extendedProperties: ExtendedProperties
}

private struct UpdateEventBody: Encodable {
    let summary: String
    let description: String?
    let start: EventDateTime
    let end: EventDateTime
    // Optional so it's left out of the JSON when nil. On PATCH, Google
    // merges these keys into the event's existing private properties
    // rather than replacing them, so blocksTaskID is kept.
    let extendedProperties: ExtendedProperties?
}

private struct PatchPropertiesBody: Encodable {
    let extendedProperties: ExtendedProperties
}

struct GoogleCalendarService: Sendable {
    private static let calendarsBase = "https://www.googleapis.com/calendar/v3/calendars"

    private func eventsURL(calendarID: String) -> URL {
        URL(string: "\(Self.calendarsBase)/\(Self.encode(calendarID))/events")!
    }

    private static func encode(_ calendarID: String) -> String {
        calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
    }

    /// Creates a new secondary calendar. Requires the calendar.app.created
    /// (or full calendar) scope.
    func insertCalendar(summary: String, accessToken: String) async throws -> GoogleCalendarListEntry {
        let url = URL(string: Self.calendarsBase)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(InsertCalendarBody(summary: summary))

        print("[Calendar] POST \(url.absoluteString) (creating calendar \"\(summary)\")")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "create calendar")

        let created = try JSONDecoder().decode(GoogleCalendarListEntry.self, from: data)
        print("[Calendar] Created calendar \"\(summary)\": \(created.id)")
        return created
    }

    /// Fetches a single event by ID. Returns nil if the event was deleted
    /// (HTTP 404/410, or a "cancelled" status still visible for a while
    /// after deletion).
    func fetchEvent(calendarID: String, eventID: String, accessToken: String) async throws -> GoogleCalendarEvent? {
        let url = eventsURL(calendarID: calendarID).appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("[Calendar] GET \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 || httpResponse.statusCode == 410 {
            print("[Calendar] Event \(eventID) not found (HTTP \(httpResponse.statusCode))")
            return nil
        }
        try Self.checkResponse(response, data: data, context: "fetch event \(eventID)")

        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        if event.status == "cancelled" {
            print("[Calendar] Event \(eventID) is cancelled")
            return nil
        }
        print("[Calendar] Fetched event \(eventID), summary: \"\(event.summary ?? "nil")\", private properties: \(event.extendedProperties?.private ?? [:])")
        return event
    }

    func insertEvent(calendarID: String, title: String, start: Date, end: Date, description: String?, blocksTaskID: String, googleTaskID: String?, accessToken: String) async throws -> GoogleCalendarEvent {
        let url = eventsURL(calendarID: calendarID)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(InsertEventBody(
            summary: title,
            description: description,
            start: Self.eventDateTime(start),
            end: Self.eventDateTime(end),
            extendedProperties: ExtendedProperties(private: Self.privateProperties(blocksTaskID: blocksTaskID, googleTaskID: googleTaskID))
        ))

        print("[Calendar] POST \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "insert event")

        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        print("[Calendar] Inserted event \(event.id)")
        return event
    }

    func updateEvent(calendarID: String, eventID: String, title: String, start: Date, end: Date, description: String?, googleTaskID: String?, accessToken: String) async throws -> GoogleCalendarEvent {
        let url = eventsURL(calendarID: calendarID).appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(UpdateEventBody(
            summary: title,
            description: description,
            start: Self.eventDateTime(start),
            end: Self.eventDateTime(end),
            extendedProperties: googleTaskID.map { ExtendedProperties(private: ["googleTaskID": $0]) }
        ))

        print("[Calendar] PATCH \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "update event")

        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: data)
        print("[Calendar] Updated event \(event.id), Google now reports summary: \"\(event.summary ?? "nil")\"")
        return event
    }

    /// Adds/overwrites only the given private properties on an event,
    /// leaving everything else (including other private keys) untouched.
    func patchPrivateProperties(calendarID: String, eventID: String, properties: [String: String], accessToken: String) async throws {
        let url = eventsURL(calendarID: calendarID).appendingPathComponent(eventID)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PatchPropertiesBody(extendedProperties: ExtendedProperties(private: properties)))

        print("[Calendar] PATCH \(url.absoluteString) (private properties \(properties))")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkResponse(response, data: data, context: "patch event properties")
    }

    private static func privateProperties(blocksTaskID: String, googleTaskID: String?) -> [String: String] {
        var properties = ["blocksTaskID": blocksTaskID]
        properties["googleTaskID"] = googleTaskID
        return properties
    }

    func deleteEvent(calendarID: String, eventID: String, accessToken: String) async throws {
        let url = eventsURL(calendarID: calendarID).appendingPathComponent(eventID)
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

    static func parseDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
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

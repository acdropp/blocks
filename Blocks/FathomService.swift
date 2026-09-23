import Foundation

struct FathomAssignee: Codable {
    let name: String?
}



struct FathomActionItem: Codable {
    let description: String
    let completed: Bool?
    let recordingTimestamp: String?
    let assignee: FathomAssignee?

    enum CodingKeys: String, CodingKey {
        case description, completed
        case recordingTimestamp = "recording_timestamp"
        case assignee
    }
}

struct FathomMeeting: Codable {
    let title: String?
    let meetingTitle: String?
    let recordingId: Int?
    let createdAt: String?
    let actionItems: [FathomActionItem]?

    enum CodingKeys: String, CodingKey {
        case title
        case meetingTitle = "meeting_title"
        case recordingId = "recording_id"
        case createdAt = "created_at"
        case actionItems = "action_items"
    }

    var displayName: String {
        meetingTitle ?? title ?? "Meeting"
    }
}

private struct MeetingsResponse: Codable {
    let items: [FathomMeeting]?
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

enum FathomError: LocalizedError {
    case requestFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            return "Fathom request failed (HTTP \(status))."
        }
    }
}

struct FathomService {
    private let baseURL = URL(string: "https://api.fathom.ai/external/v1/meetings")!

    /// Fathom sometimes returns an empty string rather than omitting
    /// next_cursor when there are no more pages, so an empty string must be
    /// treated the same as nil to avoid looping forever on the same page.
    private static let maxPages = 20

    func fetchMeetings(createdAfter: Date, apiKey: String) async throws -> [FathomMeeting] {
        var allMeetings: [FathomMeeting] = []
        var cursor: String?
        var pageCount = 0

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        repeat {
            pageCount += 1
            guard pageCount <= Self.maxPages else {
                print("[Fathom] Stopping after \(Self.maxPages) pages — pagination did not terminate as expected")
                break
            }

            var queryItems = [
                URLQueryItem(name: "include_action_items", value: "true"),
                URLQueryItem(name: "created_after", value: dateFormatter.string(from: createdAfter)),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            let url = components.url!

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

            print("[Fathom] GET \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FathomError.requestFailed(status: -1)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                print("[Fathom] Request failed: HTTP \(httpResponse.statusCode)")
                throw FathomError.requestFailed(status: httpResponse.statusCode)
            }

            let decoded = try JSONDecoder().decode(MeetingsResponse.self, from: data)
            allMeetings.append(contentsOf: decoded.items ?? [])
            cursor = (decoded.nextCursor?.isEmpty ?? true) ? nil : decoded.nextCursor
        } while cursor != nil

        print("[Fathom] Fetched \(allMeetings.count) meeting(s)")
        return allMeetings
    }
}

import Foundation

enum CalendarAPIError: Error, Equatable {
    case http(Int, String)
    case network(String)
}

/// Google Calendar REST reads. Every request carries a fresh access token; a 401 refreshes once, and rate limits and 5xx back off
/// (1, 2, 4 s plus jitter, three tries).
struct GoogleCalendarClient: Sendable {
    let auth: GoogleAuth
    var transport: HTTPTransport = HTTP.live
    var pause: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }

    private static let base = "https://www.googleapis.com/calendar/v3"
    private static let pathCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@")
    /// What Google Calendar's own popup shows beyond what the list carries.
    private static let detailFields = "description,location,hangoutLink,conferenceData(entryPoints(entryPointType,uri,label,pin),conferenceSolution(name)),"
        + "attendees(email,displayName,responseStatus,organizer,optional,resource,self),attendeesOmitted,guestsCanSeeOtherGuests,"
        + "organizer(email,displayName,self),reminders,attachments(title,fileUrl),htmlLink,transparency,visibility,recurringEventId"

    /// A calendar or event id as one URL path segment (`#` and friends in holiday calendar ids must not end the path).
    private static func segment(_ id: String) -> String { id.addingPercentEncoding(withAllowedCharacters: pathCharacters) ?? id }
    /// Everything but `workingLocation`: Workspace users get one per day and Google shows those in the day header, not as events.
    private static let eventTypes = ["default", "outOfOffice", "focusTime", "birthday", "fromGmail"]

    func calendars() async throws -> [CalendarInfo] {
        struct Page: Decodable {
            struct Entry: Decodable {
                var id: String
                var summary: String?
                var summaryOverride: String?
                var backgroundColor: String?
                var selected: Bool?
                var accessRole: String?
                var defaultReminders: [Reminder]?
            }

            struct Reminder: Decodable { var minutes: Int? }

            var items: [Entry]?
            var nextPageToken: String?
        }
        var result: [CalendarInfo] = []
        var pageToken: String?
        repeat {
            var query = [("minAccessRole", "freeBusyReader"), ("maxResults", "250"),
                         ("fields", "nextPageToken,items(id,summary,summaryOverride,backgroundColor,selected,accessRole,defaultReminders(minutes))")]
            if let pageToken { query.append(("pageToken", pageToken)) }
            let page = try decode(Page.self, try await get("\(Self.base)/users/me/calendarList?\(HTTP.form(query))"))
            result += (page.items ?? []).map {
                CalendarInfo(id: $0.id, name: $0.summaryOverride ?? $0.summary ?? $0.id, color: EventParser.hex($0.backgroundColor) ?? 0x4285F4,
                             selected: $0.selected ?? false, busyOnly: $0.accessRole == "freeBusyReader",
                             defaultReminders: ($0.defaultReminders ?? []).compactMap(\.minutes))
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }

    /// Every event of `calendar` that touches `from..<to`, recurring series already expanded by Google. Only returns once the
    /// last page is in, so a half-loaded range is never cached.
    func events(in calendar: CalendarInfo, from: Date, to: Date, cal: Calendar) async throws -> [CalendarEvent] {
        struct Page: Decodable {
            var items: [RawEvent]?
            var nextPageToken: String?
        }
        // UTC "Z": a "+" in an offset would be read as a space.
        let utc = ISO8601DateFormatter()
        let id = Self.segment(calendar.id)
        var result: [CalendarEvent] = []
        var pageToken: String?
        repeat {
            var query = [("singleEvents", "true"), ("orderBy", "startTime"), ("timeMin", utc.string(from: from)), ("timeMax", utc.string(from: to)),
                         ("maxResults", "2500"), ("timeZone", cal.timeZone.identifier),
                         ("fields", "nextPageToken,items(id,status,summary,start,end,colorId,attendees(email,responseStatus,self))")]
            query += Self.eventTypes.map { ("eventTypes", $0) }
            if let pageToken { query.append(("pageToken", pageToken)) }
            let page = try decode(Page.self, try await get("\(Self.base)/calendars/\(id)/events?\(HTTP.form(query))"))
            result += (page.items ?? []).compactMap { EventParser.parse($0, in: calendar, cal: cal) }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }

    /// The popup's content for one event, fetched when the event is clicked.
    func details(of event: CalendarEvent, in calendar: CalendarInfo) async throws -> EventDetails {
        let query = HTTP.form([("fields", Self.detailFields)])
        let data = try await get("\(Self.base)/calendars/\(Self.segment(calendar.id))/events/\(Self.segment(event.eventID))?\(query)")
        return EventDetails.make(try decode(RawDetails.self, data), calendar: calendar)
    }

    /// The rule lines (`RRULE:FREQ=WEEKLY;BYDAY=WE`) of a recurring series, for "Weekly on Wednesday".
    func recurrence(ofSeries masterID: String, in calendar: CalendarInfo) async throws -> [String] {
        struct Master: Decodable { var recurrence: [String]? }
        let query = HTTP.form([("fields", "recurrence")])
        let data = try await get("\(Self.base)/calendars/\(Self.segment(calendar.id))/events/\(Self.segment(masterID))?\(query)")
        return try decode(Master.self, data).recurrence ?? []
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw CalendarAPIError.http(200, "Google sent something unexpected.") }
    }

    private func get(_ address: String) async throws -> Data {
        guard let url = URL(string: address) else { throw CalendarAPIError.network("bad address") }
        var backoffs = 0
        var refreshed = false
        while true {
            let token = try await auth.accessToken()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let data: Data
            let http: HTTPURLResponse
            do {
                (data, http) = try await transport(request)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                throw CalendarAPIError.network(error.localizedDescription)
            }
            let busy = http.statusCode == 429 || (500...599).contains(http.statusCode) || (http.statusCode == 403 && Self.isRateLimit(data))
            switch http.statusCode {
            case 200:
                return data
            case 401 where !refreshed:
                refreshed = true
                await auth.invalidate(token)
            case _ where busy:
                backoffs += 1
                guard backoffs <= 3 else { throw CalendarAPIError.http(http.statusCode, HTTP.apiMessage(data) ?? "Google is busy. Try again in a minute.") }
                await pause(Double(1 << (backoffs - 1)) + Double.random(in: 0..<0.5))
            default:
                throw CalendarAPIError.http(http.statusCode, HTTP.apiMessage(data) ?? "Google answered HTTP \(http.statusCode).")
            }
        }
    }

    private static func isRateLimit(_ data: Data) -> Bool {
        struct Body: Decodable {
            struct Failure: Decodable {
                struct Reason: Decodable { var reason: String? }
                var errors: [Reason]?
            }

            var error: Failure?
        }
        let reasons = (try? JSONDecoder().decode(Body.self, from: data))?.error?.errors?.compactMap(\.reason) ?? []
        return reasons.contains { $0 == "rateLimitExceeded" || $0 == "userRateLimitExceeded" }
    }
}

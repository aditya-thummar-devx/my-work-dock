import Foundation

/// The extra fields of one event (`events.get`) that Google Calendar's own popup shows.
struct RawDetails: Decodable {
    struct Person: Decodable {
        var email: String?
        var displayName: String?
        var isSelf: Bool?

        enum CodingKeys: String, CodingKey {
            case email, displayName
            case isSelf = "self"
        }
    }

    struct Attendee: Decodable {
        var email: String?
        var displayName: String?
        var responseStatus: String?
        var organizer: Bool?
        var optional: Bool?
        var resource: Bool?
        var isSelf: Bool?

        enum CodingKeys: String, CodingKey {
            case email, displayName, responseStatus, organizer, optional, resource
            case isSelf = "self"
        }
    }

    struct Entry: Decodable {
        var entryPointType: String?
        var uri: String?
        var label: String?
        var pin: String?
    }

    struct Conference: Decodable {
        struct Solution: Decodable { var name: String? }
        var entryPoints: [Entry]?
        var conferenceSolution: Solution?
    }

    struct Reminders: Decodable {
        struct Override: Decodable {
            var method: String?
            var minutes: Int?
        }

        var useDefault: Bool?
        var overrides: [Override]?
    }

    struct Attachment: Decodable {
        var title: String?
        var fileUrl: String?
    }

    var description: String?
    var location: String?
    var hangoutLink: String?
    var conferenceData: Conference?
    var attendees: [Attendee]?
    var attendeesOmitted: Bool?
    var guestsCanSeeOtherGuests: Bool?
    var organizer: Person?
    var reminders: Reminders?
    var attachments: [Attachment]?
    var htmlLink: String?
    var transparency: String?
    var visibility: String?
    var recurringEventId: String?
}

/// What the event sheet shows beyond the title and time, ready to draw.
struct EventDetails: Equatable {
    enum Response: String {
        case accepted, declined, tentative, needsAction
    }

    struct Guest: Equatable, Identifiable {
        var id: String
        var name: String
        var response: Response
        var organizer: Bool
        var optional: Bool
        var isMe: Bool
    }

    struct Phone: Equatable {
        var number: String
        var pin: String?
    }

    struct Attachment: Equatable, Identifiable {
        var title: String
        var url: URL
        var id: String { url.absoluteString }
    }

    var location: String?
    /// As Google sends it: HTML when the event was made in the Calendar UI, plain text from other tools.
    var description: String?
    var meetURL: URL?
    /// "Google Meet", or the conference solution's own name.
    var meetName: String?
    var phones: [Phone] = []
    var guests: [Guest] = []
    /// Why the guest list is missing or cut short.
    var guestsNote: String?
    /// The organizer's name, when it is not the viewer.
    var organizer: String?
    var reminders: [String] = []
    var attachments: [Attachment] = []
    var link: URL?
    var busy = true
    var visibility: String?
    var recurringEventID: String?
    /// "Weekly on Wednesday": set once the series' rule has been fetched.
    var recurrence: String?

    static func make(_ raw: RawDetails, calendar: CalendarInfo) -> EventDetails {
        var details = EventDetails()
        details.location = raw.location.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        details.description = raw.description.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let entries = raw.conferenceData?.entryPoints ?? []
        details.meetURL = (raw.hangoutLink ?? entries.first { $0.entryPointType == "video" }?.uri).flatMap(web)
        details.meetName = raw.conferenceData?.conferenceSolution?.name ?? (raw.hangoutLink != nil ? "Google Meet" : nil)
        details.phones = entries.filter { $0.entryPointType == "phone" }.compactMap { entry in
            guard let uri = entry.uri else { return nil }
            return Phone(number: entry.label ?? uri.replacingOccurrences(of: "tel:", with: ""), pin: entry.pin)
        }

        // Rooms are resources, not guests; being alone on the invite is not a guest list either.
        let people = (raw.attendees ?? []).filter { $0.resource != true }
        let guests = people.map {
            Guest(id: $0.email ?? $0.displayName ?? UUID().uuidString, name: $0.displayName ?? $0.email ?? "Guest",
                  response: Response(rawValue: $0.responseStatus ?? "") ?? .needsAction, organizer: $0.organizer == true,
                  optional: $0.optional == true, isMe: $0.isSelf == true)
        }
        details.guests = guests.count > 1 ? guests.sorted { ($0.organizer ? 0 : 1, $0.name.lowercased()) < ($1.organizer ? 0 : 1, $1.name.lowercased()) } : []
        if raw.guestsCanSeeOtherGuests == false {
            details.guestsNote = "The organizer keeps the guest list private."
        } else if raw.attendeesOmitted == true {
            details.guestsNote = "Google cut the guest list short."
        }
        if raw.organizer?.isSelf != true { details.organizer = raw.organizer?.displayName ?? raw.organizer?.email }

        let minutes = raw.reminders.map { $0.useDefault == true ? calendar.defaultReminders : ($0.overrides ?? []).compactMap(\.minutes) } ?? []
        details.reminders = Array(Set(minutes)).sorted().map(reminderText)

        details.attachments = (raw.attachments ?? []).compactMap { attachment in
            attachment.fileUrl.flatMap(web).map { Attachment(title: attachment.title ?? $0.lastPathComponent, url: $0) }
        }
        details.link = raw.htmlLink.flatMap(web)
        details.busy = raw.transparency != "transparent"
        switch raw.visibility {
        case "private", "confidential": details.visibility = "Private"
        case "public": details.visibility = "Public"
        default: break
        }
        details.recurringEventID = raw.recurringEventId
        return details
    }

    /// `6 guests · 3 yes · 1 no · 1 maybe · 1 awaiting`.
    static func summary(_ guests: [Guest]) -> String {
        let counts = Dictionary(grouping: guests, by: \.response).mapValues(\.count)
        var parts = ["\(guests.count) guest\(guests.count == 1 ? "" : "s")"]
        if let n = counts[.accepted] { parts.append("\(n) yes") }
        if let n = counts[.declined] { parts.append("\(n) no") }
        if let n = counts[.tentative] { parts.append("\(n) maybe") }
        if let n = counts[.needsAction] { parts.append("\(n) awaiting") }
        return parts.joined(separator: " · ")
    }

    /// Only web links leave the app: a `javascript:` or `file:` URL in an event never gets opened.
    static func web(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    static func reminderText(_ minutes: Int) -> String {
        func unit(_ n: Int, _ name: String) -> String { "\(n) \(name)\(n == 1 ? "" : "s") before" }
        if minutes == 0 { return "When it starts" }
        if minutes % 10_080 == 0 { return unit(minutes / 10_080, "week") }
        if minutes % 1_440 == 0 { return unit(minutes / 1_440, "day") }
        if minutes % 60 == 0 { return unit(minutes / 60, "hour") }
        return unit(minutes, "minute")
    }
}

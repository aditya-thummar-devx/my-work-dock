import SwiftUI

extension Geo.Cal {
    static let sheetTop: CGFloat = 44
    static let sheetInset: CGFloat = 12
    static let sheetPad: CGFloat = 18
    static let rowIcon: CGFloat = 15
    static let rowGap: CGFloat = 14
    static let columnGap: CGFloat = 28
    static let guestsShown = 8
    /// How long after the panel appears its sheet may be drawn: the panel's entrance animation plus a margin.
    static let sheetAfterOpen = Geo.fadeOpen.delay + Geo.fadeOpen.duration + 0.15
}

/// Over the whole panel: a scrim and, once an event is clicked, its sheet (same place and shape as claudex's member details).
struct CalendarEventOverlay: View {
    var store: CalendarStore
    /// False while the panel is still fading in (`Entrance`). A sheet created during that animation never gets its buttons drawn:
    /// the close cross and the footer stay missing. A click on an event in the peek opens the panel and selects the event in the
    /// same moment, so `selected` is set at once and the sheet waits. Snapshots run no animation (`entrance` is off): no wait.
    @State private var ready = false
    @Environment(\.entrance) private var entrance

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0).task {
                try? await Task.sleep(for: .seconds(Geo.Cal.sheetAfterOpen))
                ready = true
            }
            if let event = store.selected, ready || !entrance {
                ZStack(alignment: .top) {
                    Scrim().contentShape(Rectangle()).onTapGesture(perform: store.closeDetail)
                    CalendarEventSheet(store: store, event: event)
                        .padding(.top, Geo.Cal.sheetTop)
                        .padding(.horizontal, Geo.Cal.sheetInset)
                        .padding(.bottom, Geo.Cal.sheetInset)
                }
                .transition(.opacity)
            }
        }
    }
}

/// What Google Calendar's own popup shows for an event: when, the series' rule, the Meet link and dial-in, where, the guests
/// and who said what, reminders, the calendar, the description and attachments. Title and time are on screen at once; the rest
/// fills in when `events.get` answers.
private struct CalendarEventSheet: View {
    var store: CalendarStore
    var event: CalendarEvent
    @Environment(\.tokens) private var t

    private var calendarInfo: CalendarInfo? { store.calendars.first { $0.id == event.calendarID } }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 22)
        VStack(spacing: 0) {
            header
            DockScroll {
                VStack(alignment: .leading, spacing: 0) { rows }
                    .padding(.horizontal, Geo.Cal.sheetPad)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { shape.fill(t.pop).shadow(color: t.popShadow, radius: Geo.Chrome.popoverShadow.blur / 2, y: Geo.Chrome.popoverShadow.y) }
        .overlay(shape.strokeBorder(t.border, lineWidth: 1))
        .clipShape(shape)
        // Every link in the sheet, the description's too, goes through the store: the panel closes before the browser opens.
        .environment(\.openURL, OpenURLAction { url in
            store.open(url)
            return .handled
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event details")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: event.color)).frame(width: 14, height: 14).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(Typo.ui(16, .bold)).lineLimit(2).strikethrough(event.declined)
                Text(EventText.when(event, cal: store.cal)).font(Typo.ui(12.5)).foregroundStyle(t.text2)
            }
            Spacer(minLength: 0)
            // Esc closes the sheet first; the panel's own Esc would close the whole panel.
            IconButton(glyph: .close, label: "Close details", size: 30, iconSize: 11, stroke: 2.8, fill: t.border, fg: t.text, action: store.closeDetail)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
    }

    @ViewBuilder private var rows: some View {
        switch store.detail {
        case .loading:
            HStack(spacing: 8) {
                Spinner(size: 13).foregroundStyle(t.muted)
                Text("Loading details…").font(Typo.ui(12.5)).foregroundStyle(t.faint)
            }
            .padding(.vertical, 10)
            calendarRow(nil)
        case .failed(let why):
            Text(why).font(Typo.ui(12.5, .semibold)).foregroundStyle(t.orange).padding(.vertical, 10)
            calendarRow(nil)
        case .loaded(let details):
            loaded(details)
        }
    }

    @ViewBuilder private func loaded(_ details: EventDetails) -> some View {
        // The sheet is wide and the guest list is its tallest block: the facts go left, the guests right. The description and
        // attachments keep the full width below. Without guests the facts take the whole row.
        HStack(alignment: .top, spacing: Geo.Cal.columnGap) {
            VStack(alignment: .leading, spacing: 0) {
                if let recurrence = details.recurrence { InfoRow(.recur) { line(recurrence) } }
                if let meet = details.meetURL { InfoRow(.video) { meetRow(meet, details) } }
                if let place = details.location { InfoRow(.mapPin) { locationRow(place) } }
                if !details.reminders.isEmpty {
                    InfoRow(.bell) {
                        VStack(alignment: .leading, spacing: 2) { ForEach(details.reminders, id: \.self) { line($0) } }
                    }
                }
                calendarRow(details)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            if !details.guests.isEmpty || details.guestsNote != nil {
                InfoRow(.users) { guestsRow(details) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        if let description = details.description {
            InfoRow(.text) {
                Text(RichText.attributed(html: description))
                    .font(Typo.ui(12.5))
                    .foregroundStyle(t.text2)
                    .tint(t.isDark ? t.accent : Color(hex: 0x0B57D0))
                    .lineSpacing(Typo.lineSpacing(size: 12.5, lineHeight: 1.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if !details.attachments.isEmpty {
            InfoRow(.paperclip) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(details.attachments) { attachment in
                        Button { store.open(attachment.url) } label: {
                            Text(attachment.title).font(Typo.ui(12.5)).underline().foregroundStyle(t.text).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in the browser")
                    }
                }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(Typo.ui(12.5)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true)
    }

    private func meetRow(_ url: URL, _ details: EventDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                DockButton(title: "Join with \(details.meetName ?? "video call")", glyph: .video, iconSize: 13, metrics: .sheet, tone: .tint) { store.open(url) }
                RowIconButton(glyph: store.copied ? .check : .copy, label: "Copy meeting link", fg: store.copied ? t.green : t.text2) { store.copyMeetLink(url) }
            }
            Text((url.host ?? "") + url.path).font(Typo.ui(11.5)).foregroundStyle(t.faint).lineLimit(1).truncationMode(.middle)
            ForEach(details.phones, id: \.number) { phone in
                Text("Join by phone: \(phone.number)" + (phone.pin.map { " · PIN \($0)" } ?? "")).font(Typo.ui(11.5)).foregroundStyle(t.faint)
            }
        }
    }

    private func locationRow(_ place: String) -> some View {
        let url = EventDetails.web(place) ?? URL(string: "https://www.google.com/maps/search/?api=1&" + HTTP.form([("query", place)]))
        return Button { if let url { store.open(url) } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(place).font(Typo.ui(12.5)).foregroundStyle(t.text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Icon(.link, size: 11).foregroundStyle(t.faint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in the browser")
    }

    private func guestsRow(_ details: EventDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !details.guests.isEmpty {
                Text(EventDetails.summary(details.guests)).font(Typo.ui(12.5, .semibold)).foregroundStyle(t.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(store.guestsExpanded ? details.guests : Array(details.guests.prefix(Geo.Cal.guestsShown))) { guest in
                HStack(spacing: 8) {
                    responseIcon(guest.response)
                    Text(guest.name + (guest.isMe ? " (you)" : "")).font(Typo.ui(12.5)).foregroundStyle(t.text).lineLimit(1)
                    // The labels win over a long address: it is the address that gets cut.
                    if guest.organizer { Text("Organizer").font(Typo.ui(10.5, .semibold)).foregroundStyle(t.faint).layoutPriority(1) }
                    if guest.optional { Text("Optional").font(Typo.ui(10.5, .semibold)).foregroundStyle(t.faint).layoutPriority(1) }
                }
                .accessibilityElement(children: .combine)
            }
            if !store.guestsExpanded, details.guests.count > Geo.Cal.guestsShown {
                Button(action: store.showAllGuests) {
                    Text("+\(details.guests.count - Geo.Cal.guestsShown) more").font(Typo.ui(11.5, .semibold)).foregroundStyle(t.text2)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows every guest")
            }
            if let note = details.guestsNote { Text(note).font(Typo.ui(11.5)).foregroundStyle(t.faint) }
        }
    }

    private func responseIcon(_ response: EventDetails.Response) -> some View {
        let (glyph, color): (Glyph, Color) = switch response {
        case .accepted: (.check, t.green)
        case .declined: (.close, t.red)
        case .tentative: (.question, t.orange)
        case .needsAction: (.ring, t.faint)
        }
        return Icon(glyph, size: 12, stroke: 2.8).foregroundStyle(color).frame(width: 16, height: 16)
    }

    /// The calendar the event is on, and once known whether it shows busy, how private it is and who organizes it.
    private func calendarRow(_ details: EventDetails?) -> some View {
        InfoRow(.calendar) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Circle().fill(Color(hex: calendarInfo?.color ?? event.color)).frame(width: 8, height: 8)
                    line(calendarInfo?.name ?? "Calendar")
                }
                if let details {
                    let facts = [details.busy ? "Busy" : "Free", details.visibility, details.organizer.map { "Organizer: \($0)" }].compactMap { $0 }
                    Text(facts.joined(separator: " · ")).font(Typo.ui(11.5)).foregroundStyle(t.faint)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if case .loaded(let details) = store.detail, let link = details.link {
                DockButton(title: "Open in Google Calendar", glyph: .link, iconSize: 13, metrics: .sheet, tone: .outline(nil)) { store.open(link) }
            }
            if case .failed = store.detail {
                DockButton(title: "Retry", glyph: .refresh, iconSize: 13, metrics: .sheet, tone: .outline(nil), action: store.retryDetail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
    }
}

/// One line of the sheet: a glyph, then its content.
private struct InfoRow<Content: View>: View {
    var glyph: Glyph
    var content: Content
    @Environment(\.tokens) private var t

    init(_ glyph: Glyph, @ViewBuilder content: () -> Content) {
        self.glyph = glyph
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Geo.Cal.rowGap) {
            Icon(glyph, size: Geo.Cal.rowIcon).foregroundStyle(t.muted).frame(width: 20).padding(.top, 2)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }
}

import EventKit
import Foundation

struct CalendarCLIError: Error, CustomStringConvertible {
    let description: String
}

let localFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter
}()

var codexOutputPath: String?
var codexErrorPath: String?

func write(_ string: String, to path: String?, fallback: FileHandle) {
    guard let path else {
        fallback.write(string.data(using: .utf8)!)
        return
    }
    do {
        try string.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        fallback.write(string.data(using: .utf8)!)
    }
}

func fail(_ message: String) -> Never {
    write(message + "\n", to: codexErrorPath, fallback: FileHandle.standardError)
    exit(1)
}

func jsonPrint(_ object: Any) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let output = String(data: data, encoding: .utf8)! + "\n"
        write(output, to: codexOutputPath, fallback: FileHandle.standardOutput)
    } catch {
        fail("Could not encode JSON: \(error)")
    }
}

func calendarFor(timeZone: TimeZone?) -> Calendar {
    var calendar = Calendar.current
    if let timeZone {
        calendar.timeZone = timeZone
    }
    return calendar
}

func formatterFor(timeZone: TimeZone?) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone ?? TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter
}

func parseTimeZone(_ raw: String?) throws -> TimeZone? {
    guard let raw, !raw.isEmpty else {
        return nil
    }
    if let timeZone = TimeZone(identifier: raw) {
        return timeZone
    }
    throw CalendarCLIError(description: "Unknown time zone identifier: \(raw)")
}

func parseDate(_ raw: String, endOfDay: Bool = false, timeZone: TimeZone? = nil) throws -> Date {
    let now = Date()
    let calendar = calendarFor(timeZone: timeZone)
    let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if lower == "now" {
        return calendar.date(bySetting: .second, value: 0, of: now) ?? now
    }

    let baseDate: Date?
    if lower == "today" {
        baseDate = calendar.startOfDay(for: now)
    } else if lower == "tomorrow" {
        baseDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    } else {
        baseDate = nil
    }
    if let baseDate {
        if endOfDay {
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: baseDate) ?? baseDate
        }
        return baseDate
    }

    let normalized = raw.replacingOccurrences(of: "T", with: " ")
    let formats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd"
    ]
    for format in formats {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? TimeZone.current
        formatter.dateFormat = format
        if let date = formatter.date(from: normalized) {
            if format == "yyyy-MM-dd", endOfDay {
                return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: date) ?? date
            }
            return date
        }
    }

    throw CalendarCLIError(description: "Use YYYY-MM-DD, YYYY-MM-DD HH:MM, today, tomorrow, or now: \(raw)")
}

func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

func has(_ flag: String, in args: [String]) -> Bool {
    args.contains(flag)
}

func positionalArgs(_ args: [String]) -> [String] {
    var output: [String] = []
    var skip = false
    let flagsWithValues: Set<String> = [
        "--from", "--to", "--days", "--calendar", "--start", "--end",
        "--duration-minutes", "--duration-days", "--location", "--notes",
        "--url", "--title", "--time-zone", "--repeat", "--repeat-days",
        "--repeat-until", "--repeat-interval", "--span"
    ]
    for arg in args {
        if skip {
            skip = false
            continue
        }
        if flagsWithValues.contains(arg) {
            skip = true
            continue
        }
        if arg.hasPrefix("--") {
            continue
        }
        output.append(arg)
    }
    return output
}

func requestAccess(_ store: EKEventStore) throws {
    var granted = false
    var requestError: Error?
    var finished = false

    if #available(macOS 14.0, *) {
        store.requestFullAccessToEvents { result, error in
            granted = result
            requestError = error
            finished = true
        }
    } else {
        store.requestAccess(to: .event) { result, error in
            granted = result
            requestError = error
            finished = true
        }
    }

    while !finished {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    if let requestError {
        throw requestError
    }
    if !granted {
        throw CalendarCLIError(
            description: "Calendar access was not granted. Enable access for Codex Apple Calendar Helper in System Settings > Privacy & Security > Calendars."
        )
    }
}

func calendarPayload(_ calendar: EKCalendar) -> [String: Any] {
    [
        "id": calendar.calendarIdentifier,
        "name": calendar.title,
        "source": calendar.source.title,
        "type": "\(calendar.type)",
        "writable": calendar.allowsContentModifications
    ]
}

func eventPayload(_ event: EKEvent) -> [String: Any] {
    let eventFormatter = formatterFor(timeZone: event.timeZone)
    var payload: [String: Any] = [
        "id": event.eventIdentifier ?? "",
        "calendarItemId": event.calendarItemIdentifier,
        "externalId": event.calendarItemExternalIdentifier ?? "",
        "title": event.title ?? "",
        "start": localFormatter.string(from: event.startDate),
        "end": localFormatter.string(from: event.endDate),
        "startInTimeZone": eventFormatter.string(from: event.startDate),
        "endInTimeZone": eventFormatter.string(from: event.endDate),
        "timeZone": event.timeZone?.identifier ?? TimeZone.current.identifier,
        "allDay": event.isAllDay,
        "calendarName": event.calendar.title,
        "calendarId": event.calendar.calendarIdentifier,
        "calendarWritable": event.calendar.allowsContentModifications,
        "availability": "\(event.availability.rawValue)"
    ]
    if let location = event.location, !location.isEmpty {
        payload["location"] = location
    } else {
        payload["location"] = ""
    }
    if let notes = event.notes, !notes.isEmpty {
        payload["notes"] = notes
    } else {
        payload["notes"] = ""
    }
    if let url = event.url {
        payload["url"] = url.absoluteString
    } else {
        payload["url"] = ""
    }
    if event.hasRecurrenceRules {
        payload["recurring"] = true
        payload["recurrenceRules"] = event.recurrenceRules?.map { "\($0)" } ?? []
    } else {
        payload["recurring"] = false
        payload["recurrenceRules"] = []
    }
    return payload
}

func matchingCalendars(store: EKEventStore, filter: String?, writableOnly: Bool = false) -> [EKCalendar] {
    store.calendars(for: .event).filter { calendar in
        if writableOnly && !calendar.allowsContentModifications {
            return false
        }
        guard let filter, !filter.isEmpty else {
            return true
        }
        return calendar.title == filter || calendar.calendarIdentifier == filter
    }
}

func writableCalendar(store: EKEventStore, filter: String?) throws -> EKCalendar {
    let calendars = matchingCalendars(store: store, filter: filter, writableOnly: true)
    if let calendar = calendars.first {
        return calendar
    }
    throw CalendarCLIError(description: "No writable calendar found for \(filter ?? "default selection")")
}

func events(store: EKEventStore, start: Date, end: Date, calendarFilter: String?) -> [EKEvent] {
    let calendars = matchingCalendars(store: store, filter: calendarFilter)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars.isEmpty ? nil : calendars)
    return store.events(matching: predicate).sorted {
        if $0.startDate == $1.startDate {
            return ($0.title ?? "") < ($1.title ?? "")
        }
        return $0.startDate < $1.startDate
    }
}

func findEvent(store: EKEventStore, id: String) throws -> EKEvent {
    if let event = store.event(withIdentifier: id) {
        return event
    }
    let now = Date()
    let start = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now
    let end = Calendar.current.date(byAdding: .year, value: 5, to: now) ?? now
    if let event = events(store: store, start: start, end: end, calendarFilter: nil).first(where: {
        $0.calendarItemIdentifier == id || $0.calendarItemExternalIdentifier == id
    }) {
        return event
    }
    throw CalendarCLIError(description: "No Calendar event found with id \(id)")
}

func commandCalendars(store: EKEventStore) {
    jsonPrint(store.calendars(for: .event).map(calendarPayload))
}

func commandAgenda(store: EKEventStore, args: [String]) throws {
    let days = Int(value(after: "--days", in: args) ?? "7") ?? 7
    let start = try parseDate(value(after: "--from", in: args) ?? "today")
    let end: Date
    if let rawEnd = value(after: "--to", in: args) {
        end = try parseDate(rawEnd, endOfDay: !rawEnd.contains(" ") && !rawEnd.contains("T"))
    } else {
        end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
    }
    jsonPrint(events(store: store, start: start, end: end, calendarFilter: value(after: "--calendar", in: args)).map(eventPayload))
}

func commandDay(store: EKEventStore, offset: Int, args: [String]) throws {
    let start = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    jsonPrint(events(store: store, start: start, end: end, calendarFilter: value(after: "--calendar", in: args)).map(eventPayload))
}

func commandSearch(store: EKEventStore, args: [String]) throws {
    let pos = positionalArgs(args)
    guard let query = pos.first else {
        throw CalendarCLIError(description: "search requires a query")
    }
    let days = Int(value(after: "--days", in: args) ?? "30") ?? 30
    let start = try parseDate(value(after: "--from", in: args) ?? "today")
    let end: Date
    if let rawEnd = value(after: "--to", in: args) {
        end = try parseDate(rawEnd, endOfDay: !rawEnd.contains(" ") && !rawEnd.contains("T"))
    } else {
        end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
    }
    let needle = query.lowercased()
    let matches = events(store: store, start: start, end: end, calendarFilter: value(after: "--calendar", in: args)).filter { event in
        let haystack = [
            event.title ?? "",
            event.location ?? "",
            event.notes ?? "",
            event.url?.absoluteString ?? "",
            event.calendar.title
        ].joined(separator: "\n").lowercased()
        return haystack.contains(needle)
    }
    jsonPrint(matches.map(eventPayload))
}

func recurrenceFrequency(_ raw: String) throws -> EKRecurrenceFrequency {
    switch raw.lowercased() {
    case "daily":
        return .daily
    case "weekly":
        return .weekly
    case "monthly":
        return .monthly
    case "yearly", "annually", "annual":
        return .yearly
    default:
        throw CalendarCLIError(description: "Unsupported repeat frequency: \(raw)")
    }
}

func recurrenceWeekday(_ raw: String) throws -> EKRecurrenceDayOfWeek {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "sun", "sunday":
        return EKRecurrenceDayOfWeek(.sunday)
    case "mon", "monday":
        return EKRecurrenceDayOfWeek(.monday)
    case "tue", "tues", "tuesday":
        return EKRecurrenceDayOfWeek(.tuesday)
    case "wed", "wednesday":
        return EKRecurrenceDayOfWeek(.wednesday)
    case "thu", "thur", "thurs", "thursday":
        return EKRecurrenceDayOfWeek(.thursday)
    case "fri", "friday":
        return EKRecurrenceDayOfWeek(.friday)
    case "sat", "saturday":
        return EKRecurrenceDayOfWeek(.saturday)
    default:
        throw CalendarCLIError(description: "Unsupported repeat weekday: \(raw)")
    }
}

func recurrenceDays(from raw: String?) throws -> [EKRecurrenceDayOfWeek]? {
    guard let raw, !raw.isEmpty else {
        return nil
    }
    return try raw.split(separator: ",").map { try recurrenceWeekday(String($0)) }
}

func applyRecurrence(to event: EKEvent, args: [String], timeZone: TimeZone?) throws {
    guard let rawRepeat = value(after: "--repeat", in: args) else {
        return
    }
    let frequency = try recurrenceFrequency(rawRepeat)
    let interval = Int(value(after: "--repeat-interval", in: args) ?? "1") ?? 1
    if interval < 1 {
        throw CalendarCLIError(description: "--repeat-interval must be 1 or greater")
    }
    let daysOfWeek = try recurrenceDays(from: value(after: "--repeat-days", in: args))

    let recurrenceEnd: EKRecurrenceEnd?
    if let rawUntil = value(after: "--repeat-until", in: args) {
        let until = try parseDate(rawUntil, endOfDay: true, timeZone: timeZone)
        recurrenceEnd = EKRecurrenceEnd(end: until)
    } else {
        recurrenceEnd = nil
    }

    let rule = EKRecurrenceRule(
        recurrenceWith: frequency,
        interval: interval,
        daysOfTheWeek: daysOfWeek,
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: recurrenceEnd
    )
    event.addRecurrenceRule(rule)
}

func commandCreate(store: EKEventStore, args: [String]) throws {
    let pos = positionalArgs(args)
    guard let title = pos.first else {
        throw CalendarCLIError(description: "create requires a title")
    }
    guard let rawStart = value(after: "--start", in: args) else {
        throw CalendarCLIError(description: "create requires --start")
    }

    let allDay = has("--all-day", in: args)
    let requestedTimeZone = try parseTimeZone(value(after: "--time-zone", in: args))
    let timeZone = allDay ? nil : requestedTimeZone
    var start = try parseDate(rawStart, timeZone: timeZone)
    if allDay {
        start = calendarFor(timeZone: timeZone).startOfDay(for: start)
    }

    let end: Date
    if let rawEnd = value(after: "--end", in: args) {
        var parsedEnd = try parseDate(rawEnd, timeZone: timeZone)
        if allDay {
            parsedEnd = calendarFor(timeZone: timeZone).startOfDay(for: parsedEnd)
            if parsedEnd <= start {
                parsedEnd = calendarFor(timeZone: timeZone).date(byAdding: .day, value: 1, to: start) ?? start
            }
        }
        end = parsedEnd
    } else if allDay {
        let days = Int(value(after: "--duration-days", in: args) ?? "1") ?? 1
        end = calendarFor(timeZone: timeZone).date(byAdding: .day, value: max(days, 1), to: start) ?? start
    } else {
        let minutes = Int(value(after: "--duration-minutes", in: args) ?? "60") ?? 60
        end = calendarFor(timeZone: timeZone).date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    if end <= start {
        throw CalendarCLIError(description: "Event end must be after start")
    }

    let event = EKEvent(eventStore: store)
    event.calendar = try writableCalendar(store: store, filter: value(after: "--calendar", in: args))
    event.title = title
    event.startDate = start
    event.endDate = end
    event.isAllDay = allDay
    if let timeZone {
        event.timeZone = timeZone
    }
    event.location = value(after: "--location", in: args)
    event.notes = value(after: "--notes", in: args)
    if let rawURL = value(after: "--url", in: args), let url = URL(string: rawURL) {
        event.url = url
    }
    try applyRecurrence(to: event, args: args, timeZone: timeZone)
    try store.save(event, span: .thisEvent, commit: true)
    jsonPrint(eventPayload(event))
}

func commandUpdate(store: EKEventStore, args: [String]) throws {
    let pos = positionalArgs(args)
    guard let id = pos.first else {
        throw CalendarCLIError(description: "update requires an event id")
    }
    let event = try findEvent(store: store, id: id)
    if let title = value(after: "--title", in: args) {
        event.title = title
    }
    if let rawStart = value(after: "--start", in: args) {
        event.startDate = try parseDate(rawStart)
    }
    if let rawEnd = value(after: "--end", in: args) {
        event.endDate = try parseDate(rawEnd)
    }
    if has("--all-day", in: args) {
        event.isAllDay = true
    }
    if has("--timed", in: args) {
        event.isAllDay = false
    }
    if let location = value(after: "--location", in: args) {
        event.location = location
    }
    if let notes = value(after: "--notes", in: args) {
        event.notes = notes
    }
    if let rawURL = value(after: "--url", in: args) {
        event.url = rawURL.isEmpty ? nil : URL(string: rawURL)
    }
    try store.save(event, span: .thisEvent, commit: true)
    jsonPrint(eventPayload(event))
}

func commandDelete(store: EKEventStore, args: [String]) throws {
    guard has("--yes", in: args) else {
        throw CalendarCLIError(description: "Refusing to delete without --yes")
    }
    let pos = positionalArgs(args)
    guard let id = pos.first else {
        throw CalendarCLIError(description: "delete requires an event id")
    }
    let event = try findEvent(store: store, id: id)
    let payload = eventPayload(event)
    let rawSpan = value(after: "--span", in: args) ?? "this"
    let span: EKSpan
    switch rawSpan.lowercased() {
    case "this":
        span = .thisEvent
    case "future", "all", "series":
        span = .futureEvents
    default:
        throw CalendarCLIError(description: "Unsupported delete span: \(rawSpan). Use this, future, all, or series.")
    }
    try store.remove(event, span: span, commit: true)
    jsonPrint(["deleted": payload, "span": rawSpan])
}

func commandValidateWrite(store: EKEventStore, args: [String]) throws {
    let start = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
    let end = Calendar.current.date(byAdding: .minute, value: 5, to: start)!
    let event = EKEvent(eventStore: store)
    event.calendar = try writableCalendar(store: store, filter: value(after: "--calendar", in: args))
    event.title = "Codex Calendar Skill Test"
    event.startDate = start
    event.endDate = end
    event.notes = "Temporary validation event created and deleted by the apple-calendar Codex skill."
    try store.save(event, span: .thisEvent, commit: true)
    let created = eventPayload(event)
    try store.remove(event, span: .thisEvent, commit: true)
    jsonPrint(["created": created, "deleted": created["id"] ?? "", "ok": true])
}

func usage() -> Never {
    write("""
    Usage:
      calendar.py calendars
      calendar.py today [--calendar NAME]
      calendar.py tomorrow [--calendar NAME]
      calendar.py agenda [--from DATE] [--to DATE] [--days N] [--calendar NAME]
      calendar.py search QUERY [--from DATE] [--to DATE] [--days N] [--calendar NAME]
      calendar.py create TITLE --start DATE [--end DATE|--duration-minutes N] [--calendar NAME] [--time-zone IANA_ID] [--all-day] [--location TEXT] [--notes TEXT] [--url URL] [--repeat daily|weekly|monthly|yearly] [--repeat-days tue,thu] [--repeat-until DATE]
      calendar.py update ID [--title TEXT] [--start DATE] [--end DATE] [--all-day|--timed] [--location TEXT] [--notes TEXT] [--url URL]
      calendar.py delete ID --yes [--span this|future|all]
      calendar.py validate-write [--calendar NAME]
    """
    + "\n", to: codexOutputPath, fallback: FileHandle.standardOutput)
    exit(2)
}

func consumeInternalFlag(_ flag: String, from args: inout [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
        return nil
    }
    let value = args[index + 1]
    args.removeSubrange(index...(index + 1))
    return value
}

var args = Array(CommandLine.arguments.dropFirst())
codexOutputPath = consumeInternalFlag("--codex-output", from: &args)
codexErrorPath = consumeInternalFlag("--codex-error", from: &args)

guard let command = args.first else {
    usage()
}
let commandArgs = Array(args.dropFirst())

do {
    let store = EKEventStore()
    try requestAccess(store)

    switch command {
    case "calendars":
        commandCalendars(store: store)
    case "agenda":
        try commandAgenda(store: store, args: commandArgs)
    case "today":
        try commandDay(store: store, offset: 0, args: commandArgs)
    case "tomorrow":
        try commandDay(store: store, offset: 1, args: commandArgs)
    case "search":
        try commandSearch(store: store, args: commandArgs)
    case "create":
        try commandCreate(store: store, args: commandArgs)
    case "update":
        try commandUpdate(store: store, args: commandArgs)
    case "delete":
        try commandDelete(store: store, args: commandArgs)
    case "validate-write":
        try commandValidateWrite(store: store, args: commandArgs)
    case "--help", "-h", "help":
        usage()
    default:
        fail("Unknown command: \(command)")
    }
} catch {
    fail("\(error)")
}

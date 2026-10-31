import Foundation
import EventKit
import Contacts
import UIKit
import PocketCore

/// Real side effects through Apple frameworks only. No tapping inside other apps:
/// messages go through a user-installed Shortcut ("PG Send Message") via the shortcuts:// URL scheme.
final class SystemActions: ActionExecutor, @unchecked Sendable {
    let events = EKEventStore()
    let contacts = CNContactStore()

    func requestAccess() async {
        _ = try? await events.requestFullAccessToReminders()
        _ = try? await events.requestFullAccessToEvents()
        _ = try? await contacts.requestAccess(for: .contacts)
    }

    func searchContacts(_ query: String) async throws -> [String] {
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey] as [CNKeyDescriptor]
        let found = try contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
        return found.prefix(7).map { c in
            let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let hint = [c.jobTitle, c.organizationName].filter { !$0.isEmpty }.joined(separator: ", ")
            return hint.isEmpty ? name : "\(name) (\(hint))"
        }
    }

    func searchEvents(_ query: String) async throws -> [String] {
        let start = Date(), end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
        let pred = events.predicateForEvents(withStart: start, end: end, calendars: nil)
        let f = DateFormatter(); f.dateFormat = "EEE MMM d, h:mm a"
        let q = query.lowercased()
        let hits = events.events(matching: pred).filter { ($0.title ?? "").lowercased().split(separator: " ").contains { q.contains($0) } }
        return hits.prefix(7).map { "\($0.title ?? "Event") (\(f.string(from: $0.startDate)))" }
    }

    func perform(_ a: PlannedAction) async throws -> String {
        switch a.tool {
        case "create_reminder":
            let r = EKReminder(eventStore: events)
            r.title = a.args["title"] ?? "Reminder"
            r.calendar = events.defaultCalendarForNewReminders()
            if let d = Self.date(from: a.args["when"]) {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                r.addAlarm(EKAlarm(absoluteDate: d))
            }
            try events.save(r, commit: true)
            return "Reminder set: \(r.title ?? "")" + (a.args["when"].map { " · \($0)" } ?? "")
        case "create_event":
            let e = EKEvent(eventStore: events)
            e.title = a.args["title"] ?? "Event"
            e.startDate = Self.date(from: a.args["when"]) ?? Date().addingTimeInterval(3600)
            e.endDate = e.startDate.addingTimeInterval(3600)
            e.calendar = events.defaultCalendarForNewEvents
            try events.save(e, span: .thisEvent)
            return "Added to calendar: \(e.title ?? "")"
        case "find_event":
            if let ev = a.args["event"] { return ev }
            let hits = try await searchEvents(a.args["query"] ?? "")
            return hits.first ?? "Nothing matching on your calendar in the next 30 days."
        case "lookup_contact":
            return try await searchContacts(a.args["contact"] ?? "").first ?? "No contact found."
        case "send_message":
            // Bridge: Shortcut "PG Send Message" receives "Name|Body" and runs the built-in Send Message action.
            let input = "\(a.args["contact"] ?? "")|\(a.args["body"] ?? "")"
            var c = URLComponents(string: "shortcuts://run-shortcut")!
            c.queryItems = [.init(name: "name", value: "PG Send Message"), .init(name: "input", value: "text"), .init(name: "text", value: input)]
            await MainActor.run { UIApplication.shared.open(c.url!) }
            return "Sending to \(a.args["contact"] ?? "")…"
        case "search_memory":
            return "Searching memory…"   // handled by AppModel using MemoryStore
        default:
            return "Nothing to do."
        }
    }

    static func date(from phrase: String?) -> Date? {
        guard let p = phrase, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return det.firstMatch(in: p, range: NSRange(p.startIndex..., in: p))?.date
    }
}

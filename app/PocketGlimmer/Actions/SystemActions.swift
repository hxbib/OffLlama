import Foundation
import EventKit
import Contacts
import UIKit
import MessageUI
import PocketCore

/// Real side effects through Apple frameworks only. No tapping inside other apps:
/// messages/emails open the system compose sheet pre-filled (the user taps Send); fallbacks are the sms:/mailto: schemes
/// and a user-installed Shortcut ("PG Send Message") via shortcuts://.
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

    /// Today's events for the morning brief: "Standup 9:00 AM".
    func eventsOn(_ day: Date) -> [String] {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let evs = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
        return evs.prefix(6).map { "\($0.title ?? "Event") \($0.isAllDay ? "all day" : f.string(from: $0.startDate))" }
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
            let who = Self.displayName(a.args["contact"] ?? "")
            let body = a.args["body"] ?? ""
            let phones = addresses(for: who).phones
            if let r = await ComposeSheets.message(to: Array(phones.prefix(1)), body: body, label: who) { return r }
            if let p = phones.first, let u = Self.smsURL(phone: p, body: body) {
                let opened = await ComposeSheets.open(u)
                if opened { return "Opened Messages for \(who) · tap Send" }
            }
            // Bridge: Shortcut "PG Send Message" receives "Name|Body" and runs the built-in Send Message action.
            var c = URLComponents(string: "shortcuts://run-shortcut")!
            c.queryItems = [.init(name: "name", value: "PG Send Message"), .init(name: "input", value: "text"), .init(name: "text", value: "\(who)|\(body)")]
            if let u = c.url {
                let opened = await ComposeSheets.open(u)
                if opened { return "Handed to Shortcut “PG Send Message” for \(who) · not confirmed sent" }
            }
            return "Couldn't open Messages on this device · nothing sent"
        case "send_email":
            let who = Self.displayName(a.args["contact"] ?? a.args["to"] ?? "")
            let to = a.args["to"].map { [$0] } ?? Array(addresses(for: who).emails.prefix(1))
            let subject = a.args["subject"] ?? "", body = a.args["body"] ?? ""
            if let r = await ComposeSheets.mail(to: to, subject: subject, body: body, label: who) { return r }
            var c = URLComponents(); c.scheme = "mailto"; c.path = to.first ?? ""
            c.queryItems = [.init(name: "subject", value: subject), .init(name: "body", value: body)]
            if let u = c.url {
                let opened = await ComposeSheets.open(u)
                if opened { return "Opened Mail for \(who) · tap Send" }
            }
            return "Couldn't open Mail on this device · nothing sent"
        case "search_memory":
            return "Searching memory…"   // handled by AppModel using MemoryStore
        default:
            return "Nothing to do."
        }
    }

    /// "Sam Ortiz (brother)" -> "Sam Ortiz" (contactPick labels carry a job/org hint).
    static func displayName(_ s: String) -> String { (s.components(separatedBy: " (").first ?? s).trimmingCharacters(in: .whitespaces) }

    func addresses(for name: String) -> (phones: [String], emails: [String]) {
        let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        guard !name.isEmpty,
              let c = (try? contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys))?.first
        else { return ([], []) }
        return (c.phoneNumbers.map { $0.value.stringValue }, c.emailAddresses.map { $0.value as String })
    }

    static func smsURL(phone: String, body: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        let enc = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?"))) ?? ""
        return digits.isEmpty ? nil : URL(string: "sms:\(digits)&body=\(enc)")
    }

    static func date(from phrase: String?) -> Date? {
        guard let p = phrase, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return det.firstMatch(in: p, range: NSRange(p.startIndex..., in: p))?.date
    }
}

/// Presents the system Messages / Mail compose sheet pre-filled and reports what the user actually did.
/// Returns nil when the sheet can't be shown (no SMS/Mail account, e.g. Simulator) so the caller falls back.
@MainActor
final class ComposeSheets: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
    static let shared = ComposeSheets()
    private var pending: CheckedContinuation<String, Never>?
    private var label = ""

    static func presenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }

    static func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            UIApplication.shared.open(url, options: [:]) { ok in c.resume(returning: ok) }
        }
    }

    static func message(to recipients: [String], body: String, label: String) async -> String? {
        guard MFMessageComposeViewController.canSendText(), shared.pending == nil, let top = presenter() else { return nil }
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = shared
        vc.recipients = recipients
        vc.body = body
        vc.isModalInPresentation = true     // no swipe-dismiss: the delegate always reports a result
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            shared.pending = c; shared.label = label
            top.present(vc, animated: true)
        }
    }

    static func mail(to: [String], subject: String, body: String, label: String) async -> String? {
        guard MFMailComposeViewController.canSendMail(), shared.pending == nil, let top = presenter() else { return nil }
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = shared
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.isModalInPresentation = true     // no swipe-dismiss: the delegate always reports a result
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            shared.pending = c; shared.label = label
            top.present(vc, animated: true)
        }
    }

    private func finish(_ text: String) { let c = pending; pending = nil; c?.resume(returning: text) }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        MainActor.assumeIsolated {
            let who = label.isEmpty ? "them" : label
            let text: String
            switch result {
            case .sent: text = "Sent to \(who) via Messages"
            case .cancelled: text = "Cancelled · nothing sent to \(who)"
            default: text = "Messages couldn't send to \(who)"
            }
            controller.dismiss(animated: true)
            finish(text)
        }
    }

    nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        MainActor.assumeIsolated {
            let who = label.isEmpty ? "them" : label
            let text: String
            switch result {
            case .sent: text = "Email to \(who) sent via Mail"
            case .saved: text = "Email to \(who) saved as a draft · not sent"
            case .cancelled: text = "Cancelled · nothing sent to \(who)"
            default: text = "Mail couldn't send to \(who)"
            }
            controller.dismiss(animated: true)
            finish(text)
        }
    }
}

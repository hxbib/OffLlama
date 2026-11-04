import Foundation
import EventKit
import Contacts
import UIKit
import UniformTypeIdentifiers
import PocketCore

/// The only `PhoneEffects`. It executes the compiled/snapshotted invocation after a claim and returns typed evidence.
/// Status sentences are not produced here; summaries come from `Disposition.userSummary`.
final class PocketEffects: PhoneEffects, @unchecked Sendable {
    private let events: EKEventStore
    private let contacts: CNContactStore
    private let memory: MemoryStore?

    init(events: EKEventStore, contacts: CNContactStore, memory: MemoryStore?) {
        self.events = events; self.contacts = contacts; self.memory = memory
    }

    // MARK: Contacts

    func resolveContacts(_ query: String) async -> ContactLookup {
        let access = contactAccess()
        guard access == .full || access == .limited else { return ContactLookup(access: access, matches: []) }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let found = (try? contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)) ?? []
        var matches = found.prefix(7).map(candidate)
        // Two same-name contacts with the same detail would produce identical choices. Show the visible methods
        // in `detail` so the user (and VoiceOver) can tell them apart without ever auto-picking one.
        let groups = Dictionary(grouping: matches, by: { ($0.displayName + "\u{1F}" + $0.detail).lowercased() })
        for i in matches.indices {
            if (groups[(matches[i].displayName + "\u{1F}" + matches[i].detail).lowercased()]?.count ?? 0) > 1 {
                let suffix = matches[i].methods.map(\.display).joined(separator: ", ")
                if !suffix.isEmpty { matches[i].detail = matches[i].detail.isEmpty ? suffix : "\(matches[i].detail) · \(suffix)" }
            }
        }
        return ContactLookup(access: access, matches: matches)
    }

    func contact(identifier: String) async -> ContactLookup {
        let access = contactAccess()
        guard access == .full || access == .limited else { return ContactLookup(access: access, matches: []) }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        guard let c = try? contacts.unifiedContact(withIdentifier: identifier, keysToFetch: keys) else {
            return ContactLookup(access: access, matches: [])
        }
        return ContactLookup(access: access, matches: [candidate(c)])
    }

    private func candidate(_ c: CNContact) -> ContactCandidate {
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let detail = [c.jobTitle, c.organizationName].filter { !$0.isEmpty }.joined(separator: ", ")
        var methods: [ContactMethod] = []
        for phone in c.phoneNumbers {
            let raw = phone.value.stringValue
            let digits = raw.filter { $0.isNumber || $0 == "+" }
            guard !digits.isEmpty else { continue }
            let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? CNLabelPhoneNumberMobile)
            let tail = digits.count > 4 ? String(digits.suffix(4)) : digits
            methods.append(ContactMethod(kind: .phone, label: label, value: digits, display: "\(label) ···\(tail)"))
        }
        for email in c.emailAddresses {
            let value = String(email.value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { continue }
            let label = CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? CNLabelWork)
            methods.append(ContactMethod(kind: .email, label: label, value: value, display: "\(label) \(value)"))
        }
        return ContactCandidate(identifier: c.identifier, displayName: name.isEmpty ? "Contact" : name,
                                detail: detail, methods: methods)
    }

    private func contactAccess() -> AccessLevel {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .full
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: Time

    func resolveInstant(_ phrase: String) -> InstantParse {
        InstantParser.parse(phrase) { text in
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
            return detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date
        }
    }

    func storeAccess(_ store: StoreKind) -> AccessLevel {
        switch store {
        case .contacts:
            return contactAccess()
        case .reminders:
            return eventAccess(for: .reminder)
        case .calendars:
            return eventAccess(for: .event)
        }
    }

    private func eventAccess(for entity: EKEntityType) -> AccessLevel {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess: return .full
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: Perform

    func perform(_ action: BoundAction, ticket: ClaimTicket) async -> EffectReport {
        switch action.executor {
        case .reminderCreate:
            return performReminder(action, ticket: ticket)
        case .eventCreate:
            return performEvent(action, ticket: ticket)
        case .messageSend:
            return await performMessage(action)
        case .mailSend:
            return await performMail(action)
        case .urlTemplate(let template):
            return await performURL(action, template: template)
        case .shortcut(let name, let input):
            return await performShortcut(action, name: name, input: input)
        case .autoreplyMemory:
            return await performAutoreply(action)
        case .notWired:
            return EffectReport(boundary: .notStarted(.unsupportedOnThisOS))
        case .emailDigest, .documentAnalysis, .htmlVisualization, .cloudReason, .deviceStatus, .calendarQuery, .memoryRecall:
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
    }

    private func performReminder(_ action: BoundAction, ticket: ClaimTicket) -> EffectReport {
        guard let title = Self.text(action, "title"), !title.isEmpty, case .instant(let date)? = action.arguments["when"] else {
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
        let access = storeAccess(.reminders)
        switch access {
        case .denied, .restricted, .notDetermined, .limited:
            return EffectReport(boundary: .notStarted(.permission(.reminders, access)))
        case .writeOnly:
            let r = EKReminder(eventStore: events)
            r.title = title
            r.notes = Self.appendToken(nil, ticket: ticket)
            r.calendar = events.defaultCalendarForNewReminders()
            setReminderTime(r, date: date, zoneID: action.timeZoneID)
            do { try events.save(r, commit: true) } catch {
                return EffectReport(boundary: .startedUnverified(.eventKitSaveThrew))
            }
            return EffectReport(boundary: .startedUnverified(.eventKitNoReadBack))
        case .full:
            let r = EKReminder(eventStore: events)
            r.title = title
            r.notes = Self.appendToken(existingNotes(r), ticket: ticket)
            r.calendar = events.defaultCalendarForNewReminders()
            setReminderTime(r, date: date, zoneID: action.timeZoneID)
            do {
                try events.save(r, commit: true)
            } catch {
                return EffectReport(boundary: .startedUnverified(.eventKitSaveThrew))
            }
            guard let item = events.calendarItem(withIdentifier: r.calendarItemIdentifier) else {
                return EffectReport(boundary: .startedUnverified(.eventKitNoReadBack))
            }
            let tokenFound = (item.notes ?? "").contains(Self.token(ticket))
            let observedDate: Date?
            if let rr = item as? EKReminder, let comps = rr.dueDateComponents {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: action.timeZoneID ?? "") ?? .current
                observedDate = cal.date(from: comps)
            } else {
                observedDate = nil
            }
            return EffectReport(boundary: .observed(.eventKit(EventKitObservation(
                identifier: item.calendarItemIdentifier, title: item.title ?? "",
                instant: observedDate, attemptTokenFound: tokenFound))))
        }
    }

    private func performEvent(_ action: BoundAction, ticket: ClaimTicket) -> EffectReport {
        guard let title = Self.text(action, "title"), !title.isEmpty, case .instant(let date)? = action.arguments["when"] else {
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
        let access = storeAccess(.calendars)
        switch access {
        case .denied, .restricted, .notDetermined, .limited:
            return EffectReport(boundary: .notStarted(.permission(.calendars, access)))
        case .writeOnly:
            let e = EKEvent(eventStore: events)
            e.title = title
            e.notes = Self.appendToken(nil, ticket: ticket)
            e.startDate = date
            e.endDate = date.addingTimeInterval(3600)
            e.calendar = events.defaultCalendarForNewEvents
            e.timeZone = TimeZone(identifier: action.timeZoneID ?? "")
            do { try events.save(e, span: .thisEvent) } catch {
                return EffectReport(boundary: .startedUnverified(.eventKitSaveThrew))
            }
            return EffectReport(boundary: .startedUnverified(.eventKitNoReadBack))
        case .full:
            let e = EKEvent(eventStore: events)
            e.title = title
            e.notes = Self.appendToken(existingNotes(e), ticket: ticket)
            e.startDate = date
            e.endDate = date.addingTimeInterval(3600)
            e.calendar = events.defaultCalendarForNewEvents
            e.timeZone = TimeZone(identifier: action.timeZoneID ?? "")
            do {
                try events.save(e, span: .thisEvent)
            } catch {
                return EffectReport(boundary: .startedUnverified(.eventKitSaveThrew))
            }
            guard let item = events.calendarItem(withIdentifier: e.calendarItemIdentifier) else {
                return EffectReport(boundary: .startedUnverified(.eventKitNoReadBack))
            }
            let tokenFound = (item.notes ?? "").contains(Self.token(ticket))
            let observedDate = (item as? EKEvent)?.startDate
            return EffectReport(boundary: .observed(.eventKit(EventKitObservation(
                identifier: item.calendarItemIdentifier, title: item.title ?? "",
                instant: observedDate, attemptTokenFound: tokenFound))))
        }
    }

    private func performMessage(_ action: BoundAction) async -> EffectReport {
        guard case .contact(let binding)? = action.arguments["contact"], let method = binding.method, method.kind == .phone else {
            return EffectReport(boundary: .notStarted(.missingContactMethod))
        }
        guard let body = Self.text(action, "body"), !body.isEmpty else {
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
        // Re-resolve the exact labelled destination. Never take the first number if the card bound another.
        let lookup = await contact(identifier: binding.identifier)
        guard lookup.matches.count == 1, let current = lookup.matches.first,
              let exact = current.methods.first(where: { $0.kind == .phone && $0.label == method.label && $0.value.caseInsensitiveCompare(method.value) == .orderedSame }) else {
            return EffectReport(boundary: .notStarted(.missingContactMethod))
        }
        let outcome = await ComposeSheets.message(to: [exact.value], body: body, label: current.displayName)
        switch outcome {
        case .result(let result): return EffectReport(boundary: .observed(.message(result)))
        case .unavailable: return EffectReport(boundary: .notStarted(.sheetUnavailable(.messages)))
        case .busy: return EffectReport(boundary: .notStarted(.sheetBusy(.messages)))
        }
    }

    private func performMail(_ action: BoundAction) async -> EffectReport {
        guard case .contact(let binding)? = action.arguments["contact"], let method = binding.method, method.kind == .email else {
            return EffectReport(boundary: .notStarted(.missingContactMethod))
        }
        let lookup = await contact(identifier: binding.identifier)
        guard lookup.matches.count == 1, let current = lookup.matches.first,
              let exact = current.methods.first(where: { $0.kind == .email && $0.label == method.label && $0.value.caseInsensitiveCompare(method.value) == .orderedSame }) else {
            return EffectReport(boundary: .notStarted(.missingContactMethod))
        }
        let subject = Self.text(action, "subject") ?? ""
        let body = Self.text(action, "body") ?? ""
        let outcome = await ComposeSheets.mail(to: [exact.value], subject: subject, body: body, label: current.displayName)
        switch outcome {
        case .result(let result): return EffectReport(boundary: .observed(.mail(result)))
        case .unavailable: return EffectReport(boundary: .notStarted(.sheetUnavailable(.mail)))
        case .busy: return EffectReport(boundary: .notStarted(.sheetBusy(.mail)))
        }
    }

    private func performURL(_ action: BoundAction, template: String) async -> EffectReport {
        let values = Self.fillValues(action)
        let filled = SkillTemplate.fill(template, args: values, raw: ["url"])
        guard let url = URL(string: filled), let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme) else {
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
        let opened = await ComposeSheets.open(url)
        guard opened else { return EffectReport(boundary: .observed(.url(.systemRefused))) }
        // Clipboard is only a local side effect after the system accepted the handoff; it is not a sent DM.
        if action.capabilityID == "instagram_dm" || action.capabilityID == "x_dm",
           let body = Self.text(action, "body"), !body.isEmpty {
            UIPasteboard.general.setItems([[UTType.plainText.identifier: body]],
                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
        }
        return EffectReport(boundary: .observed(.url(.systemAccepted)))
    }

    private func performShortcut(_ action: BoundAction, name: String, input: String) async -> EffectReport {
        let text = SkillTemplate.fill(input, args: Self.fillValues(action), encode: false)
        guard let url = URL(string: SkillTemplate.shortcutURL(name: name, text: text)) else {
            return EffectReport(boundary: .notStarted(.bindingRejected))
        }
        let opened = await ComposeSheets.open(url)
        return EffectReport(boundary: .observed(.url(opened ? .systemAccepted : .systemRefused)))
    }

    private func performAutoreply(_ action: BoundAction) async -> EffectReport {
        guard let memory, let trigger = Self.text(action, "trigger"), let reply = Self.text(action, "reply"), !reply.isEmpty else {
            return EffectReport(boundary: .notStarted(.unsupportedOnThisOS))
        }
        do {
            let saved = try await AutoreplyMemory.save(memory: memory, trigger: trigger, reply: reply)
            // `attemptTokenFound` is the semantic postcondition for a naturally idempotent memory write:
            // the rule exists now, whether this call inserted it or matched the existing row via ignoreNew.
            return EffectReport(boundary: .observed(.memoryFact(id: String(saved.fact.id), attemptTokenFound: true)))
        } catch {
            return EffectReport(boundary: .startedUnverified(.executorThrew))
        }
    }

    // MARK: Helpers

    private func setReminderTime(_ r: EKReminder, date: Date, zoneID: String?) {
        var cal = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: zoneID ?? "") ?? .current
        cal.timeZone = zone
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.timeZone = zone
        r.dueDateComponents = comps
        r.addAlarm(EKAlarm(absoluteDate: date))
    }

    private func existingNotes(_ item: EKCalendarItem) -> String? { item.notes }

    private static func token(_ ticket: ClaimTicket) -> String { "pg-attempt:\(ticket.attemptID.raw.uuidString)" }

    private static func appendToken(_ existing: String?, ticket: ClaimTicket) -> String {
        let token = token(ticket)
        guard let existing, !existing.isEmpty else { return token }
        if existing.contains(token) { return existing }
        return existing + "\n" + token
    }

    static let allowedSchemes: Set<String> = ["https", "http", "tel", "facetime", "whatsapp", "maps", "music",
                                              "spotify", "photos-redirect", "shortcuts", "uber"]

    static func text(_ action: BoundAction, _ name: String) -> String? {
        switch action.arguments[name] {
        case .text(let s)?: return s
        case .place(let s)?: return s
        case .shortcutName(let s)?: return s
        case .contactQuery(let s)?: return s
        case .contact(let b)?: return b.displayName
        default: return nil
        }
    }

    static func fillValues(_ action: BoundAction) -> [String: String] {
        var out: [String: String] = [:]
        for (name, value) in action.arguments {
            switch value {
            case .text(let s), .place(let s), .shortcutName(let s): out[name] = s
            case .contactQuery(let s): out[name] = s
            case .contact(let b): out[name] = b.method?.value ?? b.displayName
            case .instant(let d): out[name] = ISO8601DateFormatter().string(from: d)
            case .url(let u): out[name] = u.absoluteString
            }
        }
        return out
    }
}

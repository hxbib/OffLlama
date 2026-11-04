import Foundation
import EventKit
import Contacts
import UIKit
import MessageUI
import PocketCore

/// Read-only lookups plus the two system compose sheets. Effects are performed by `PocketEffects` after a
/// `ClaimTicket`; this type has no `perform` method, so an old caller cannot execute around the ledger.
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
}

enum MessageComposeOutcome: Sendable {
    case result(MessageSheetResult)
    case unavailable
    case busy
}

enum MailComposeOutcome: Sendable {
    case result(MailSheetResult)
    case unavailable
    case busy
}

/// Presents the system Messages / Mail compose sheet pre-filled and reports a typed result.
/// One presentation at a time (the second attempt gets `.busy`, not a terminal failure). Task cancellation
/// dismisses the sheet and resolves the continuation exactly once.
@MainActor
final class ComposeSheets: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate {
    static let shared = ComposeSheets()

    private enum Kind { case message, mail }
    private enum Outcome {
        case message(MessageSheetResult)
        case mail(MailSheetResult)
    }
    private var pending: (token: UUID, kind: Kind, resume: (Outcome) -> Void, controller: UIViewController)?
    var label = ""

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

    static func message(to recipients: [String], body: String, label: String) async -> MessageComposeOutcome {
        guard MFMessageComposeViewController.canSendText(), let top = presenter() else { return .unavailable }
        let token = UUID()
        shared.label = label
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<MessageComposeOutcome, Never>) in
                if Task.isCancelled { c.resume(returning: .result(.cancelled)); return }
                guard shared.pending == nil else { c.resume(returning: .busy); return }
                let vc = MFMessageComposeViewController()
                vc.messageComposeDelegate = shared
                vc.recipients = recipients
                vc.body = body
                vc.isModalInPresentation = true
                shared.pending = (token, .message, { outcome in
                    if case .message(let r) = outcome { c.resume(returning: .result(r)) }
                }, vc)
                top.present(vc, animated: true)
            }
        } onCancel: {
            Task { @MainActor in shared.cancel(token: token) }
        }
    }

    static func mail(to: [String], subject: String, body: String, label: String) async -> MailComposeOutcome {
        guard MFMailComposeViewController.canSendMail(), let top = presenter() else { return .unavailable }
        let token = UUID()
        shared.label = label
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<MailComposeOutcome, Never>) in
                if Task.isCancelled { c.resume(returning: .result(.cancelled)); return }
                guard shared.pending == nil else { c.resume(returning: .busy); return }
                let vc = MFMailComposeViewController()
                vc.mailComposeDelegate = shared
                vc.setToRecipients(to)
                vc.setSubject(subject)
                vc.setMessageBody(body, isHTML: false)
                vc.isModalInPresentation = true
                shared.pending = (token, .mail, { outcome in
                    if case .mail(let r) = outcome { c.resume(returning: .result(r)) }
                }, vc)
                top.present(vc, animated: true)
            }
        } onCancel: {
            Task { @MainActor in shared.cancel(token: token) }
        }
    }

    private func cancel(token: UUID) {
        guard let p = pending, p.token == token else { return }
        pending = nil
        p.controller.dismiss(animated: true)
        switch p.kind {
        case .message: p.resume(.message(.cancelled))
        case .mail: p.resume(.mail(.cancelled))
        }
    }

    private func finish(_ outcome: Outcome) {
        guard let p = pending else { return }
        pending = nil
        p.controller.dismiss(animated: true)
        p.resume(outcome)
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        MainActor.assumeIsolated {
            switch result {
            case .sent: finish(.message(.acceptedOrQueued))
            case .cancelled: finish(.message(.cancelled))
            default: finish(.message(.failed))
            }
        }
    }

    nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        MainActor.assumeIsolated {
            switch result {
            case .sent: finish(.mail(.queuedInOutbox))
            case .saved: finish(.mail(.savedDraft))
            case .cancelled: finish(.mail(.cancelled))
            default: finish(.mail(.failed))
            }
        }
    }
}

import Foundation

// MARK: - Skill model
//
// A Skill is a declarative, data-driven phone capability. The trained Reflex decisions are untouched; open-world
// actions are picked by the dynamic `skillPick` decision (see ActionPlanner.swift) over candidates retrieved from
// this registry. Adding an ability = adding a JSON object to Resources/Skills/*.json. No retraining.

public enum SkillCategory: String, Codable, CaseIterable, Sendable {
    case message, social, email, calendar, reminders, alarms, phone, documents, shortcuts, device, memory, web
    /// Hard rule: these speak for the user to other people, so they always confirm (a JSON file cannot turn it off).
    public var reachesOtherPeople: Bool { self == .message || self == .social || self == .email }
}

/// Why a skill needs reasoning rather than an app hand-off.
public enum CloudReasonKind: String, Codable, Sendable {
    case needsOnline   // needs live data; offline it explains instead of guessing
    case longContext   // long input: local 1B on a truncated window, Muse Spark 1.3 when online
    case generation    // free-text writing: local 1B for short output, escalate for long
}

public enum SkillInvocation: Sendable, Equatable {
    /// URL (scheme or universal link) with `{arg}` placeholders, percent-encoded when filled.
    case urlScheme(String)
    /// A user-installed Shortcut run via shortcuts://run-shortcut; `input` is a `{arg}` template passed as text.
    case shortcut(name: String, input: String)
    /// A handler implemented in code: ActionExecutor tools (EventKit/Contacts/Messages) or the iOS SkillRunner.
    case native(String)
    /// Answered by a model (local 1B, or Muse Spark 1.3 when online and allowed).
    case cloudReason(CloudReasonKind)

    public var kindName: String {
        switch self { case .urlScheme: return "url"; case .shortcut: return "shortcut"; case .native: return "native"; case .cloudReason: return "cloud" }
    }
}

extension SkillInvocation: Codable {
    enum K: String, CodingKey { case type, template, name, input, handler, kind }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "url": self = .urlScheme(try c.decode(String.self, forKey: .template))
        case "shortcut": self = .shortcut(name: try c.decode(String.self, forKey: .name), input: try c.decodeIfPresent(String.self, forKey: .input) ?? "")
        case "native": self = .native(try c.decode(String.self, forKey: .handler))
        case "cloud": self = .cloudReason(try c.decode(CloudReasonKind.self, forKey: .kind))
        case let t: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown invocation type \(t)")
        }
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(kindName, forKey: .type)
        switch self {
        case .urlScheme(let t): try c.encode(t, forKey: .template)
        case .shortcut(let n, let i): try c.encode(n, forKey: .name); try c.encode(i, forKey: .input)
        case .native(let h): try c.encode(h, forKey: .handler)
        case .cloudReason(let k): try c.encode(k, forKey: .kind)
        }
    }
}

public enum ArgKind: String, Codable, Sendable {
    case contact    // a person in Contacts (disambiguated by the trained contactPick decision)
    case handle     // a social handle (@name); never looked up in Contacts
    case text, datetime, url, document, app, duration, number, place, query
}

public struct ArgSpec: Codable, Sendable, Equatable {
    public var name: String
    public var kind: ArgKind
    public var required: Bool
    public init(_ name: String, _ kind: ArgKind, required: Bool = false) { self.name = name; self.kind = kind; self.required = required }
    enum CodingKeys: String, CodingKey { case name, kind, required }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); kind = try c.decode(ArgKind.self, forKey: .kind)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
    }
}

public struct Skill: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var category: SkillCategory
    public var invocation: SkillInvocation
    public var argSchema: [ArgSpec]
    /// Ask before acting. Forced true for message/social/email (SkillRegistry normalizes) and for anything that spends.
    public var confirm: Bool
    /// True when the decision AND the hand-off work with no internet (delivery may still need a network later).
    public var offlineCapable: Bool
    public var examples: [String]
    public var aliases: [String]
    /// Template copied to the clipboard before opening (apps that accept no prefilled text, e.g. Instagram DMs).
    public var clipboard: String?
    /// Honest limit shown to the user / in docs/SKILLS.md.
    public var note: String?

    public init(id: String, title: String, category: SkillCategory, invocation: SkillInvocation, args: [ArgSpec] = [],
                confirm: Bool = false, offline: Bool, examples: [String], aliases: [String] = [], clipboard: String? = nil, note: String? = nil) {
        self.id = id; self.title = title; self.category = category; self.invocation = invocation; self.argSchema = args
        self.confirm = confirm || category.reachesOtherPeople; self.offlineCapable = offline
        self.examples = examples; self.aliases = aliases; self.clipboard = clipboard; self.note = note
    }

    enum CodingKeys: String, CodingKey { case id, title, category, invocation, argSchema, confirm, offlineCapable, examples, aliases, clipboard, note }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(SkillCategory.self, forKey: .category)
        invocation = try c.decode(SkillInvocation.self, forKey: .invocation)
        argSchema = try c.decodeIfPresent([ArgSpec].self, forKey: .argSchema) ?? []
        confirm = (try c.decodeIfPresent(Bool.self, forKey: .confirm) ?? false) || category.reachesOtherPeople
        offlineCapable = try c.decodeIfPresent(Bool.self, forKey: .offlineCapable) ?? false
        examples = try c.decodeIfPresent([String].self, forKey: .examples) ?? []
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        clipboard = try c.decodeIfPresent(String.self, forKey: .clipboard)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Short option label for the skillPick question (kept short: the 1B reads every label in one prefill).
    public var optionLabel: String {
        guard let ex = examples.first else { return title }
        let s = "\(title) (e.g. \(ex))"
        return s.count <= 72 ? s : String(s.prefix(71)) + "…"
    }
}

// MARK: - Templates

public enum SkillTemplate {
    /// Query-safe: everything that could break a URL component is escaped (space, &, =, ?, #, +, /, @, :).
    static let allowed: CharacterSet = {
        var c = CharacterSet.alphanumerics
        c.insert(charactersIn: "-._~")
        return c
    }()
    public static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }

    /// Replace `{name}` placeholders. `encode` = percent-encode values (URLs); false for Shortcut text input.
    /// Unknown placeholders become empty strings so a missing optional arg never leaves "{body}" in a URL.
    /// `raw` names are inserted verbatim (a full URL argument such as `{url}`).
    public static func fill(_ template: String, args: [String: String], encode enc: Bool = true, raw: Set<String> = []) -> String {
        var out = "", name = "", inBrace = false
        for ch in template {
            if inBrace {
                if ch == "}" { let v = args[name] ?? ""; out += enc && !raw.contains(name) ? encode(v) : v; name = ""; inBrace = false }
                else { name.append(ch) }
            } else if ch == "{" { inBrace = true } else { out.append(ch) }
        }
        if inBrace { out += "{" + name }
        return out
    }

    /// Placeholders a template references, in order.
    public static func placeholders(_ template: String) -> [String] {
        var out: [String] = [], name = "", inBrace = false
        for ch in template {
            if inBrace { if ch == "}" { out.append(name); name = ""; inBrace = false } else { name.append(ch) } }
            else if ch == "{" { inBrace = true }
        }
        return out
    }

    /// shortcuts://run-shortcut?name=…&input=text&text=… (Apple's documented Shortcuts URL scheme).
    public static func shortcutURL(name: String, text: String) -> String {
        "shortcuts://run-shortcut?name=\(encode(name))&input=text&text=\(encode(text))"
    }
}

// MARK: - Registry + retrieval

public struct SkillRegistry: Sendable {
    public private(set) var skills: [Skill]
    private var index: [Doc] = []
    private var df: [String: Int] = [:]
    private var avgdl = 1.0

    struct Doc: Sendable { let tf: [String: Double]; let len: Double; let phrases: [String]; let vec: [Float] }

    public init(skills: [Skill] = BuiltinSkills.all) {
        var seen: [String: Int] = [:], out: [Skill] = []
        for var s in skills {
            s.confirm = s.confirm || s.category.reachesOtherPeople        // hard rule survives any JSON
            if let i = seen[s.id] { out[i] = s } else { seen[s.id] = out.count; out.append(s) }   // later id overrides
        }
        self.skills = out
        reindex()
    }

    /// Load skills from a JSON file or a directory of *.json files. Each file is `[Skill]` or `{"skills": [Skill]}`.
    /// Falls back to the Swift built-ins when nothing loads, so a missing/corrupt bundle file never disables actions.
    public static func load(from url: URL, fallback: [Skill] = BuiltinSkills.all) -> SkillRegistry {
        let loaded = (try? decodeSkills(at: url)) ?? []
        return SkillRegistry(skills: loaded.isEmpty ? fallback : loaded)
    }

    /// Adds user skills (same format) on top; a user skill with a built-in id replaces it. Returns how many were read.
    @discardableResult public mutating func merge(contentsOf url: URL) throws -> Int {
        let extra = try Self.decodeSkills(at: url)
        self = SkillRegistry(skills: skills + extra)
        return extra.count
    }

    public mutating func add(_ s: Skill) { self = SkillRegistry(skills: skills + [s]) }

    public func skill(id: String) -> Skill? { skills.first { $0.id == id } }

    static func decodeSkills(at url: URL) throws -> [Skill] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        let files = isDir.boolValue
            ? try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            : [url]
        struct Wrapped: Decodable { let skills: [Skill] }
        var out: [Skill] = []
        for f in files {
            let d = try Data(contentsOf: f)
            if let arr = try? JSONDecoder().decode([Skill].self, from: d) { out += arr }
            else { out += try JSONDecoder().decode(Wrapped.self, from: d).skills }
        }
        return out
    }

    /// Pretty JSON of the registry (the format of Resources/Skills/builtin.json).
    public func json() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(["skills": skills])
    }

    // Retrieval: BM25 over title/aliases/examples (field-weighted) + multi-word alias phrase bonus
    // + HashingEmbedder cosine (character trigrams catch "msg"/"insta"/typos). Pure Swift, deterministic, ~µs.
    static let stop: Set<String> = ["a", "an", "the", "to", "on", "in", "at", "for", "of", "my", "me", "i", "and", "or", "is",
                                    "it", "please", "can", "you", "could", "would", "with", "from", "this", "that", "these",
                                    "those", "some", "be", "do", "up", "just", "now", "hey", "pocket", "glimmer", "want", "like"]
    static func stem(_ w: String) -> String {
        if w.count > 4 && w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") && !w.hasSuffix("us") { return String(w.dropLast()) }
        return w
    }
    public static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !stop.contains($0) }.map(stem)
    }
    static func norm(_ s: String) -> String { " " + s.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " " }

    mutating func reindex() {
        index = skills.map { s in
            var tf: [String: Double] = [:]
            func add(_ text: String, _ w: Double) { for t in Self.tokens(text) { tf[t, default: 0] += w } }
            add(s.title, 2); add(s.id.replacingOccurrences(of: "_", with: " "), 1)
            for a in s.aliases { add(a, 3) }
            for e in s.examples { add(e, 1) }
            let phrases = s.aliases.map(Self.norm).filter { $0.split(separator: " ").count >= 2 }
            let vec = HashingEmbedder.vector(([s.title] + s.aliases + s.examples).joined(separator: " "), 256)
            return Doc(tf: tf, len: tf.values.reduce(0, +), phrases: phrases, vec: vec)
        }
        df = [:]
        for d in index { for t in d.tf.keys { df[t, default: 0] += 1 } }
        avgdl = max(1, index.map(\.len).reduce(0, +) / Double(max(1, index.count)))
    }

    /// Top-k skills for an utterance, best first. Scores > 0 only.
    public func retrieve(_ query: String, k: Int = 7) -> [(skill: Skill, score: Double)] {
        let q = Self.tokens(query), qn = Self.norm(query)
        let qv = HashingEmbedder.vector(query, 256)
        let N = Double(index.count), k1 = 1.2, b = 0.75
        var scored: [(Int, Double)] = []
        for (i, d) in index.enumerated() {
            var s = 0.0
            for t in Set(q) {
                guard let f = d.tf[t], let n = df[t] else { continue }
                let idf = log(1 + (N - Double(n) + 0.5) / (Double(n) + 0.5))
                s += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * d.len / avgdl))
            }
            for p in d.phrases where qn.contains(p) { s += 1.5 * Double(p.split(separator: " ").count) }
            s += 2.0 * Double(cosine(qv, d.vec))
            scored.append((i, s))
        }
        return scored.filter { $0.1 > 0.6 }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(max(0, k)).map { (skills[$0.0], $0.1) }
    }
}

// MARK: - Shared text inbox (share sheet / Shortcuts -> app)

/// Text handed to the app by the "Pocket Glimmer: handle text" App Intent (e.g. emails shared from Mail).
/// email_digest / analyze_document / html_viz read it; it is consumed once and expires after 15 minutes.
public final class SharedInbox: @unchecked Sendable {
    public static let shared = SharedInbox()
    private let lock = NSLock()
    private var item: (text: String, source: String, at: Date)?
    public init() {}
    public func put(_ text: String, source: String = "share", at: Date = Date()) { lock.lock(); item = (text, source, at); lock.unlock() }
    public func peek(maxAge: TimeInterval = 900, now: Date = Date()) -> (text: String, source: String)? {
        lock.lock(); defer { lock.unlock() }
        guard let i = item, now.timeIntervalSince(i.at) <= maxAge else { return nil }
        return (i.text, i.source)
    }
    public func take(maxAge: TimeInterval = 900, now: Date = Date()) -> (text: String, source: String)? {
        lock.lock(); defer { lock.unlock() }   // read-and-clear under one lock so two takers cannot both receive the item
        guard let i = item, now.timeIntervalSince(i.at) <= maxAge else { item = nil; return nil }
        item = nil; return (i.text, i.source)
    }
}

// MARK: - Offline HTML visualization (no model needed)

public enum HTMLViz {
    /// "rent 1200, food 400; transit: 130" -> [(rent,1200),(food,400),(transit,130)]. Unlabeled numbers get #1, #2…
    public static func pairs(from text: String) -> [(label: String, value: Double)] {
        let numRe = try! NSRegularExpression(pattern: #"-?\$?\d[\d,]*(?:\.\d+)?%?"#)
        var out: [(String, Double)] = []
        for seg in text.components(separatedBy: CharacterSet(charactersIn: ";\n|")).flatMap({ $0.components(separatedBy: ", ") }) {
            let ns = seg as NSString
            guard let m = numRe.matches(in: seg, range: NSRange(location: 0, length: ns.length)).last else { continue }
            let raw = ns.substring(with: m.range).filter { $0.isNumber || $0 == "." || $0 == "-" }
            guard let v = Double(raw) else { continue }
            var label = ns.substring(to: m.range.location)
            if let c = label.lastIndex(where: { $0 == ":" || $0 == "=" }) {
                let after = String(label[label.index(after: c)...])
                label = after.contains(where: \.isLetter) ? after : String(label[..<c])
            }
            let words = label.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "&" }.suffix(3)
            out.append((words.joined(separator: " "), v))
        }
        return out.enumerated().map { ($0.element.0.isEmpty ? "#\($0.offset + 1)" : $0.element.0, $0.element.1) }
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Self-contained HTML page with an inline SVG horizontal bar chart (light/dark aware). Nil when no numbers.
    public static func render(text: String, title: String = "Chart") -> (html: String, bars: Int)? {
        let p = Array(pairs(from: text).prefix(24))
        guard !p.isEmpty else { return nil }
        let maxV = max(p.map { abs($0.value) }.max() ?? 1, 1e-9)
        let rowH = 28.0, labelW = 110.0, barW = 190.0, h = Double(p.count) * rowH + 8
        var rows = ""
        for (i, x) in p.enumerated() {
            let y = Double(i) * rowH + 4, w = max(2, barW * abs(x.value) / maxV)
            let v = x.value == x.value.rounded() ? String(Int(x.value)) : String(format: "%.2f", x.value)
            rows += "<text x=\"\(Int(labelW - 6))\" y=\"\(Int(y + 17))\" text-anchor=\"end\" class=\"l\">\(esc(String(x.label.prefix(16))))</text>"
            rows += "<rect x=\"\(Int(labelW))\" y=\"\(Int(y + 4))\" width=\"\(Int(w))\" height=\"18\" rx=\"4\" class=\"b\"/>"
            rows += "<text x=\"\(Int(labelW + w + 6))\" y=\"\(Int(y + 17))\" class=\"v\">\(v)</text>"
        }
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>:root{color-scheme:light dark}body{font:15px -apple-system,system-ui,sans-serif;margin:16px}
        h1{font-size:18px;margin:0 0 4px}p{color:#888;font-size:12px;margin:0 0 12px}.l,.v{font-size:12px;fill:currentColor}
        .b{fill:#5B6BFF}</style></head><body><h1>\(esc(title))</h1>
        <p>\(p.count) values · drawn on device, no model or network</p>
        <svg viewBox="0 0 360 \(Int(h))" width="100%" role="img" aria-label="\(esc(title))">\(rows)</svg></body></html>
        """
        return (html, p.count)
    }
}

// MARK: - Built-in skills (fallback when Resources/Skills/builtin.json is missing; the JSON is generated from these)

public enum BuiltinSkills {
    static func s(_ id: String, _ title: String, _ cat: SkillCategory, _ inv: SkillInvocation, _ args: [ArgSpec] = [],
                  confirm: Bool = false, offline: Bool, _ examples: [String], aliases: [String] = [], clipboard: String? = nil, note: String? = nil) -> Skill {
        Skill(id: id, title: title, category: cat, invocation: inv, args: args, confirm: confirm, offline: offline,
              examples: examples, aliases: aliases, clipboard: clipboard, note: note)
    }
    static let contact = ArgSpec("contact", .contact, required: true)
    static let handle = ArgSpec("contact", .handle, required: true)
    static let body = ArgSpec("body", .text)

    public static let all: [Skill] = [
        // Messaging: speaks for the user -> always confirm.
        s("imessage_send", "Send an iMessage / text", .message, .native("send_message"), [contact, body], offline: true,
          ["text Sam I'm running late", "reply to Mom's text saying on my way"],
          aliases: ["imessage", "sms", "text message", "reply to a text", "respond to a text", "messages app"],
          note: "Opens the system Messages compose sheet pre-filled; you tap Send."),
        s("instagram_dm", "Instagram DM", .social, .urlScheme("https://ig.me/m/{contact}"), [handle, body], offline: false,
          ["dm sam on instagram saying congrats", "message @sam on insta"],
          aliases: ["instagram", "insta", "ig", "instagram dm", "instagram message", "ig dm", "dm on instagram"],
          clipboard: "{body}",
          note: "Instagram has no API to send DMs. ig.me opens the DM thread; the message is on your clipboard: paste and send."),
        s("x_dm", "X (Twitter) DM", .social, .urlScheme("https://x.com/{contact}"), [handle, body], offline: false,
          ["message @sam on twitter", "dm sam on x saying gg"],
          aliases: ["twitter", "x dm", "twitter dm", "tweet dm", "dm on twitter", "on x", "x.com"],
          clipboard: "{body}",
          note: "X needs a numeric recipient_id to prefill a DM; we open @handle's profile (tap Message) with the text on your clipboard."),
        s("whatsapp_send", "WhatsApp message", .social, .urlScheme("whatsapp://send?text={body}"), [contact, body], offline: false,
          ["whatsapp Leo that I landed", "send a whatsapp to mom"],
          aliases: ["whatsapp", "whats app", "wa message"],
          note: "Opens WhatsApp with the text prefilled; you pick the chat and tap Send."),
        s("instagram_autoreply", "Auto-reply rule (Instagram / any app)", .social, .native("autoreply_rule"), [ArgSpec("trigger", .text), ArgSpec("reply", .text, required: true)],
          offline: true, ["reply to every reel with haha nice", "whenever someone sends a reel say lol"],
          aliases: ["auto reply", "autoreply", "every reel", "reply to every", "whenever someone", "automatic reply"],
          note: "iOS lets no app read or answer Instagram DMs. The rule is saved to memory and turned into a Shortcuts Automation recipe."),
        s("email_compose", "Write an email", .email, .native("send_email"), [contact, ArgSpec("subject", .text), body], offline: true,
          ["email Dana the slides are ready", "send an email to my professor"],
          aliases: ["email", "e-mail", "mail", "gmail", "write an email", "send an email"],
          note: "Opens the Mail compose sheet pre-filled; you tap Send."),
        s("email_digest", "Summarize my recent emails", .email, .native("email_digest"), [ArgSpec("n", .number)], offline: true,
          ["summarize my last 5 emails", "analyze my last few emails and tell me about them"],
          aliases: ["summarize emails", "recent emails", "last emails", "inbox summary", "my emails", "unread mail", "analyze emails"],
          note: "Apps cannot read Mail. Select messages in Mail, Share → Pocket Glimmer (Shortcut “PG Share Emails”); the summary is made on device."),
        // Calendar / reminders / alarms
        s("reminder_create", "Create a reminder", .reminders, .native("create_reminder"), [ArgSpec("title", .text, required: true), ArgSpec("when", .datetime)],
          offline: true, ["remind me to buy milk tomorrow"], aliases: ["reminder", "remind me", "to-do", "todo"]),
        s("calendar_create", "Add a calendar event", .calendar, .native("create_event"), [ArgSpec("title", .text, required: true), ArgSpec("when", .datetime)],
          offline: true, ["put lunch with Leo on my calendar Friday at 1pm"], aliases: ["calendar", "event", "schedule", "meeting", "book"]),
        s("calendar_find", "Check my calendar", .calendar, .native("find_event"), [ArgSpec("query", .query)],
          offline: true, ["when is my dentist appointment"], aliases: ["what's on", "agenda", "next meeting", "free time"]),
        s("alarm_create", "Set an alarm", .alarms, .shortcut(name: "PG Create Alarm", input: "{time}|{label}"), [ArgSpec("time", .datetime, required: true), ArgSpec("label", .text)],
          offline: true, ["wake me at 6", "set an alarm for 7:30am"], aliases: ["alarm", "wake me", "wake up", "alarm clock"],
          note: "No public alarm URL; the Shortcut uses the built-in Clock “Create Alarm” action."),
        s("timer_start", "Start a timer", .alarms, .shortcut(name: "PG Start Timer", input: "{duration}"), [ArgSpec("duration", .duration, required: true)],
          offline: true, ["set a timer for 10 minutes", "start a 25 minute pomodoro"], aliases: ["timer", "countdown", "pomodoro"],
          note: "Shortcut wraps the built-in Clock “Start Timer” action."),
        // Phone
        s("call", "Phone call", .phone, .urlScheme("tel:{phone}"), [contact], confirm: true, offline: true,
          ["call Mom", "phone the pharmacy"], aliases: ["call", "phone", "ring", "dial"],
          note: "iOS shows its own Call prompt; the number comes from Contacts on device."),
        s("facetime", "FaceTime", .phone, .urlScheme("facetime:{phone}"), [contact], confirm: true, offline: false,
          ["facetime Leo"], aliases: ["facetime", "video call", "video chat"]),
        s("maps_directions", "Directions in Maps", .web, .urlScheme("maps://?daddr={place}"), [ArgSpec("place", .place, required: true)],
          offline: false, ["directions to Hunter College", "navigate to the nearest Walgreens"], aliases: ["directions", "navigate", "maps", "how do i get to", "route to"]),
        s("uber_ride", "Request an Uber", .web, .urlScheme("uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]={place}"), [ArgSpec("place", .place, required: true)],
          confirm: true, offline: false, ["get me an uber to JFK"], aliases: ["uber", "ride", "taxi", "cab", "lyft"],
          note: "Opens Uber with the drop-off filled; you confirm the ride (spends money) in Uber."),
        s("web_search", "Search the web", .web, .urlScheme("https://duckduckgo.com/?q={query}"), [ArgSpec("query", .query, required: true)],
          offline: false, ["search the web for best ramen in the Bronx", "google how tall is the Empire State Building"],
          aliases: ["search", "google", "look up online", "web search", "duckduckgo", "safari"]),
        s("open_url", "Open a link", .web, .urlScheme("{url}"), [ArgSpec("url", .url, required: true)], offline: false,
          ["open https://hunter.cuny.edu"], aliases: ["open link", "open url", "website", "go to"]),
        // Apps & Shortcuts
        s("open_app", "Open an app", .shortcuts, .shortcut(name: "PG Open App", input: "{app}"), [ArgSpec("app", .app, required: true)],
          offline: true, ["open Spotify", "launch the camera"], aliases: ["open", "launch", "start app", "open app"],
          note: "Shortcut “PG Open App” uses the built-in Open App action with the app name as input."),
        s("run_shortcut", "Run a Shortcut by name", .shortcuts, .urlScheme("shortcuts://run-shortcut?name={name}&input=text&text={text}"), [ArgSpec("name", .text, required: true), ArgSpec("text", .text)],
          offline: true, ["run my shortcut Morning Routine"], aliases: ["run shortcut", "shortcut named", "run my shortcut"]),
        s("create_shortcut", "Create a new Shortcut", .shortcuts, .urlScheme("shortcuts://create-shortcut"), [], offline: true,
          ["create a shortcut", "make a new automation"], aliases: ["create shortcut", "new shortcut", "make a shortcut", "automation"],
          note: "Apps cannot write Shortcuts; this opens the Shortcuts editor (and docs/SKILLS.md lists recipes)."),
        s("music_play", "Play music", .shortcuts, .urlScheme("music://"), [ArgSpec("query", .query)], offline: true,
          ["play some music", "open apple music"], aliases: ["music", "play music", "song", "playlist", "apple music"]),
        s("spotify_play", "Spotify", .shortcuts, .urlScheme("spotify:search:{query}"), [ArgSpec("query", .query)], offline: false,
          ["play lofi on spotify"], aliases: ["spotify"]),
        s("appletv_play", "Apple TV: play a show", .shortcuts, .shortcut(name: "PG Play on Apple TV", input: "{show}"),
          [ArgSpec("show", .query, required: true)], offline: false,
          ["open the latest episode of Severance on Apple TV", "play Ted Lasso on apple tv", "put on the new episode of Silo"],
          aliases: ["apple tv", "appletv", "tv app", "latest episode", "new episode", "watch", "episode"],
          note: "iOS has no public URL that plays a specific show. The Shortcut “PG Play on Apple TV” (Shortcuts → TV → “Play” with the show name as input; set “Play Up Next” on, which resumes or starts the newest unwatched episode) does the playback. Fallback when the Shortcut is missing: https://tv.apple.com/search?term={show} opens the show page in the TV app."),
        s("notes_create", "Create a note", .documents, .shortcut(name: "PG Create Note", input: "{text}"), [ArgSpec("text", .text, required: true)],
          offline: true, ["make a note: wifi code is on the fridge", "jot down the parking spot"], aliases: ["note", "notes", "jot down", "write down"],
          note: "Shortcut wraps Notes “Create Note”; mobilenotes:// only opens Notes."),
        s("photos_open", "Open Photos", .documents, .urlScheme("photos-redirect://"), [], offline: true,
          ["show my photos", "open the camera roll"], aliases: ["photos", "camera roll", "pictures", "gallery"]),
        // Documents & reasoning
        s("analyze_document", "Analyze a document", .documents, .native("analyze_document"), [ArgSpec("document", .document)],
          offline: true, ["analyze this document", "summarize this pdf"], aliases: ["document", "pdf", "analyze this", "summarize this file", "read this file"],
          note: "Document picker: PDF (PDFKit), .txt and .md. Summary on device; long files escalate to Muse Spark 1.3 only if sensitivity allows."),
        s("html_viz", "Make a chart / HTML visualization", .documents, .native("html_viz"), [ArgSpec("data", .text)],
          offline: true, ["make a chart of these numbers: rent 1200, food 400, transit 130", "visualize this data as a bar chart"],
          aliases: ["chart", "graph", "plot", "visualize", "visualization", "bar chart", "html"],
          note: "Numbers in the text become an inline SVG bar chart offline, no model needed."),
        s("translate", "Translate a phrase", .web, .cloudReason(.generation), [ArgSpec("text", .text, required: true)], offline: true,
          ["translate good morning to Spanish"], aliases: ["translate", "translation", "in spanish", "in french", "how do you say"],
          note: "Short phrases on the 1B; long text escalates when online and allowed."),
        s("summarize_text", "Summarize shared text", .documents, .cloudReason(.longContext), [ArgSpec("text", .text)], offline: true,
          ["summarize what I just shared", "tldr this"], aliases: ["summarize", "tldr", "summary", "key points"]),
        // Device
        s("device_status", "Battery & storage", .device, .native("device_status"), [], offline: true,
          ["how much battery do I have", "how much storage is left"], aliases: ["battery", "storage", "disk space", "free space", "charge"]),
        s("flashlight_toggle", "Toggle flashlight", .device, .shortcut(name: "PG Toggle Flashlight", input: ""), [], offline: true,
          ["turn on the flashlight"], aliases: ["flashlight", "torch", "light"]),
        s("focus_toggle", "Toggle Do Not Disturb", .device, .shortcut(name: "PG Toggle Focus", input: ""), [], offline: true,
          ["turn on do not disturb", "focus mode on"], aliases: ["do not disturb", "dnd", "focus", "silence notifications"]),
        s("low_power_toggle", "Toggle Low Power Mode", .device, .shortcut(name: "PG Toggle Low Power", input: ""), [], offline: true,
          ["turn on low power mode"], aliases: ["low power", "battery saver", "power saving"]),
        s("weather", "Weather", .web, .shortcut(name: "PG Weather", input: "{place}"), [ArgSpec("place", .place)], offline: false,
          ["what's the weather", "will it rain tomorrow"], aliases: ["weather", "rain", "forecast", "temperature outside"],
          note: "WeatherKit needs a paid entitlement; the Shortcut uses the built-in Get Current Weather action. Needs internet."),
        // Memory
        s("memory_recall", "Recall something I told you", .memory, .native("search_memory"), [ArgSpec("query", .query)], offline: true,
          ["what did I say my locker code was"], aliases: ["remember", "recall", "what did i say", "did i tell you"]),
    ]
}

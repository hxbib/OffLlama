import Foundation
import PocketCore

// pg-cli: drive PocketCore against a real llama-server (Linux/macOS dev loop).
//   pg-cli e2e [--url http://127.0.0.1:8088] [--db e2e.sqlite] [--tau 0.8]
//   pg-cli decide <decisionType> "<context>"
//   pg-cli telemetry --db e2e.sqlite      (CSV to stdout)

struct Case { let set: OptionSet; let context: String; let expected: String }

let cases: [Case] = [
    .init(set: OptionSets.route, context: "User: Remind me to take my vitamins at 8pm", expected: "tool"),
    .init(set: OptionSets.route, context: "User: Text Maya that I'm on my way", expected: "tool"),
    .init(set: OptionSets.route, context: "User: Thanks, that's all for now!", expected: "answer_local"),
    .init(set: OptionSets.route, context: "User: Compare the tax treatment of ISOs vs RSOs for an early-stage startup employee and recommend a strategy", expected: "escalate_cloud"),
    .init(set: OptionSets.route, context: "User: Move it", expected: "clarify"),
    .init(set: OptionSets.toolChoice, context: "User: Remind me to buy oat milk when I get to the store", expected: "create_reminder"),
    .init(set: OptionSets.toolChoice, context: "User: What's on my calendar tomorrow morning?", expected: "find_event"),
    .init(set: OptionSets.toolChoice, context: "User: Send Sam a message saying happy birthday", expected: "send_message"),
    .init(set: OptionSets.rememberOrNot, context: "User: By the way, I'm allergic to peanuts.", expected: "remember_fact"),
    .init(set: OptionSets.rememberOrNot, context: "User: What time is it?", expected: "no"),
    .init(set: OptionSets.memoryConflict, context: "Existing memory: User lives in Boston\nNew statement: I just moved to Brooklyn last week", expected: "update"),
    .init(set: OptionSets.notificationTriage, context: "Notification from Mom: 'Call me ASAP, Dad is in the hospital'", expected: "interrupt"),
    .init(set: OptionSets.notificationTriage, context: "Notification from ShopMart: '20% off sneakers this weekend only!'", expected: "ignore"),
    .init(set: OptionSets.confirmBeforeAct, context: "Planned action: delete all calendar events next week", expected: "confirm"),
    .init(set: OptionSets.timing, context: "User: Every Monday at 9 remind me to submit my timesheet", expected: "recurring"),
    .init(set: OptionSets.sensitivity, context: "User: Summarize my HIV test results and my bank account balance", expected: "sensitive"),
    .init(set: OptionSets.contactPick(candidates: ["Sam Lee (coworker)", "Sam Ortiz (brother)", "Samantha Diaz (dentist)"]),
          context: "User: Tell my brother Sam I'll be late to dinner", expected: "c1"),
    .init(set: OptionSets.nudgeNow, context: "Trigger: arrive, place: Trader Joe's\nMemory: User needs to buy oat milk", expected: "nudge"),
]

func arg(_ name: String, _ def: String) -> String {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return def
}

let cmd = CommandLine.arguments.dropFirst().first ?? "help"
let url = URL(string: arg("--url", ProcessInfo.processInfo.environment["PG_LLAMA_URL"] ?? "http://127.0.0.1:8088"))!
let engine = LlamaServerEngine(baseURL: url, modelName: arg("--model", "Llama-3.2-1B-Instruct-Q4_K_M"))

switch cmd {
case "e2e":
    let db = try SQLiteDB(path: arg("--db", "e2e-telemetry.sqlite"))
    let tel = try TelemetryLog(db: db)
    let reflex = Reflex(engine: engine, profile: .init(defaultTau: Double(arg("--tau", "0.8"))!), telemetry: tel, source: "linux-e2e")
    var correct = 0, local = 0, localCorrect = 0
    var lat: [Double] = []
    print("type                 expected        argmax          conf   esc   ms")
    for c in cases {
        let d = try await reflex.decide(c.set, context: c.context)
        let ok = d.argmax.id == c.expected
        correct += ok ? 1 : 0
        if !d.escalated { local += 1; localCorrect += ok ? 1 : 0 }
        lat.append(d.latencyMs)
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: n, withPad: " ", startingAt: 0) }
        print(pad(c.set.type.rawValue, 21) + pad(c.expected, 16) + pad(d.argmax.id, 16) + String(format: "%.3f  ", d.confidence)
              + (d.escalated ? "yes" : "no ") + String(format: "  %6.0f ", d.latencyMs) + (ok ? "✓" : "✗"))
    }
    lat.sort()
    print("\nargmax accuracy \(correct)/\(cases.count); handled locally (conf>=tau) \(local)/\(cases.count), of which correct \(localCorrect); median latency \(Int(lat[lat.count / 2])) ms")
    print("(latency = llama-server round-trip on this Linux CPU box incl. prompt eval; NOT an iPhone number)")
case "decide":
    let a = CommandLine.arguments
    guard a.count >= 4, let t = DecisionType(rawValue: a[2]), let set = OptionSets.staticSets.first(where: { $0.type == t }) else {
        print("usage: pg-cli decide <\(OptionSets.staticSets.map(\.type.rawValue).joined(separator: "|"))> \"context\""); exit(2)
    }
    let d = try await Reflex(engine: engine).decide(set, context: a[3])
    print(d.argmax.id, String(format: "%.3f", d.confidence), d.escalated ? "ESCALATE" : "local", String(format: "%.0fms", d.latencyMs))
    for o in set.options { print(String(format: "  %.3f  %@", d.probabilities[o.id] ?? 0, o.id as NSString)) }
case "dump-sets":
    // Machine-readable option sets + one rendered prompt; training/tests/test_parity.py checks Python matches Swift.
    let sets = OptionSets.staticSets + [OptionSets.contactPick(candidates: ["Sam Lee", "Sam Ortiz"]), OptionSets.eventPick(candidates: ["Dentist", "Standup"])]
    let obj: [String: Any] = [
        "system": DecisionPrompt.system,
        "sets": sets.map { ["type": $0.type.rawValue, "question": $0.question, "fallback": $0.fallbackID,
                            "options": $0.options.map { ["id": $0.id, "label": $0.label] }] },
        "sample_prompt": DecisionPrompt.llama3(set: OptionSets.route, context: "User: hello"),
    ]
    print(String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
case "telemetry":
    print(try TelemetryLog(db: SQLiteDB(path: arg("--db", "e2e-telemetry.sqlite"))).csv(), terminator: "")
default:
    print("pg-cli e2e | decide <type> <context> | telemetry  [--url URL] [--db PATH] [--tau X]")
}

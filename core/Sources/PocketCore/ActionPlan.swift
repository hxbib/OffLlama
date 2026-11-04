import Foundation

public enum SavedResultField: String, Codable, Sendable, Equatable {
    case title, time, summary
}

public struct PlanDependency: Codable, Sendable, Equatable {
    public let stepIndex: Int
    public let field: SavedResultField
    public init(stepIndex: Int, field: SavedResultField) {
        self.stepIndex = stepIndex; self.field = field
    }
}

public struct PlanStepInput: Codable, Sendable, Equatable {
    public let capabilityID: String
    public let arguments: [String: String]
    public let messageFrom: PlanDependency?
    public init(capabilityID: String, arguments: [String: String], messageFrom: PlanDependency? = nil) {
        self.capabilityID = capabilityID; self.arguments = arguments; self.messageFrom = messageFrom
    }
}

public enum PlanStepPresentation: Sendable, Equatable {
    case review(DraftCard)
    case outcome(EffectResult)
    case unsupported(String)
}

public struct ActionPlanStep: Sendable, Equatable {
    public let index: Int
    public let attemptID: AttemptID
    public let title: String
    public let presentation: PlanStepPresentation
}

public struct ActionPlan: Sendable, Equatable {
    public let requestID: UserRequestID
    public let steps: [ActionPlanStep]
}

public enum ActionPlanError: Error, Equatable {
    case stepCount, tooLarge, capacity, requestAlreadyUsed, invalidDependency, corruptPlan
}

enum PlanWriteKind: String, Codable, Sendable, Equatable { case event, reminder }

enum PlanStepState: Codable, Sendable, Equatable {
    case independent
    case dependent(PlanDependency, PlanWriteKind)
    case unsupported(String)

    var dependency: PlanDependency? {
        if case .dependent(let dependency, _) = self { return dependency }; return nil
    }
    var requiredWrite: PlanWriteKind? {
        if case .dependent(_, let kind) = self { return kind }; return nil
    }
    var unsupportedReason: String? {
        if case .unsupported(let reason) = self { return reason }; return nil
    }
}

struct PreparedPlanStep {
    var action: BoundAction
    var pause: UserPause?
    var notice: String
    var state: PlanStepState
}

enum PlanCapability {
    case producer(PlanWriteKind), consumer, unsupported

    init(_ contract: CapabilityContract?) {
        guard let contract, contract.availability == .ready else { self = .unsupported; return }
        switch contract.executor {
        case .eventCreate: self = .producer(.event)
        case .reminderCreate: self = .producer(.reminder)
        case .messageSend, .mailSend: self = .consumer
        default: self = .unsupported
        }
    }
}

extension EffectSession {
    public func stagePlan(requestID: UserRequestID, steps: [PlanStepInput]) async throws -> ActionPlan {
        if let existing = try ledger.actionPlan(requestID: requestID) { return existing }
        guard (2...3).contains(steps.count) else { throw ActionPlanError.stepCount }
        guard try JSONEncoder().encode(steps).count <= 16_384 else { throw ActionPlanError.tooLarge }
        var prepared: [PreparedPlanStep] = []
        for (index, input) in steps.enumerated() {
            if let dependency = input.messageFrom,
               !(0..<index).contains(dependency.stepIndex) { throw ActionPlanError.invalidDependency }
            let contract = CapabilityCatalog.current(id: input.capabilityID)
            let role = PlanCapability(contract)
            var state = PlanStepState.independent
            if case .unsupported = role {
                state = .unsupported("OffLlama cannot perform this step as part of a plan. Nothing was opened or changed.")
            }
            if let dependency = input.messageFrom {
                guard case .consumer = role else { throw ActionPlanError.invalidDependency }
                guard (input.arguments["body"] ?? "").trimmed.isEmpty else { throw ActionPlanError.invalidDependency }
                if case .producer(let kind) = PlanCapability(CapabilityCatalog.current(id: steps[dependency.stepIndex].capabilityID)) {
                    state = .dependent(dependency, kind)
                } else {
                    state = .unsupported("The earlier step cannot provide a verified saved result for this message. Nothing will be sent.")
                }
            }
            guard let contract, state.unsupportedReason == nil else {
                let action = BoundAction(capabilityID: input.capabilityID, contractVersion: contract?.version ?? 1,
                    title: contract?.title ?? input.capabilityID, arguments: [:], source: .userUtterance,
                    executor: contract?.executor ?? .notWired)
                prepared.append(PreparedPlanStep(action: action, pause: .outputBinding,
                    notice: state.unsupportedReason ?? "This step is unavailable.", state: state))
                continue
            }
            if let issue = ActionValidation.issues(contract: contract, args: input.arguments).first(where: { $0.code == .unsupported }) {
                state = .unsupported(issue.question)
            }
            var raw = input.arguments
            if input.messageFrom != nil { raw.removeValue(forKey: "body") }
            let bound = await bind(raw: PlannedAction(tool: input.capabilityID, args: raw), contract: contract, now: ledger.now())
            var step = PreparedPlanStep(action: bound.action, pause: bound.pause, notice: bound.notice, state: state)
            if input.messageFrom != nil || state.unsupportedReason != nil {
                step.pause = .outputBinding
                step.notice = state.unsupportedReason ?? "Waiting for the earlier step to be saved and verified."
            }
            prepared.append(step)
        }
        try Task.checkCancellation()
        try ledger.insertPlan(requestID: requestID, steps: prepared)
        guard let plan = try ledger.actionPlan(requestID: requestID) else { throw ActionPlanError.corruptPlan }
        return plan
    }

    public func plan(requestID: UserRequestID) throws -> ActionPlan? {
        try ledger.actionPlan(requestID: requestID)
    }

    public func refreshPlan(requestID: UserRequestID) throws -> ActionPlan? {
        try ledger.materializePlan(requestID: requestID)
        return try ledger.actionPlan(requestID: requestID)
    }

    public func cancelPlan(requestID: UserRequestID) throws -> ActionPlan? {
        try ledger.cancelAwaitingPlan(requestID: requestID)
        return try ledger.actionPlan(requestID: requestID)
    }
}

extension EffectLedger {
    func migratePlans() throws {
        try db.transaction {
            let columns = Set(try db.query("PRAGMA table_info(action_attempts)").compactMap { $0["name"]?.text })
            if !columns.contains("plan_size") { try db.exec("ALTER TABLE action_attempts ADD COLUMN plan_size INTEGER") }
            if !columns.contains("plan_json") { try db.exec("ALTER TABLE action_attempts ADD COLUMN plan_json TEXT") }
            try db.exec("""
                CREATE UNIQUE INDEX IF NOT EXISTS action_plan_step
                ON action_attempts(request_id, step_index) WHERE plan_size IS NOT NULL;
                """)
        }
    }

    func insertPlan(requestID: UserRequestID, steps: [PreparedPlanStep]) throws {
        guard (2...3).contains(steps.count) else { throw ActionPlanError.stepCount }
        let encodedBytes = try steps.reduce(0) { total, step in
            total + (try JSONEncoder().encode(step.action).count) + (try JSONEncoder().encode(step.state).count)
        }
        guard encodedBytes <= 16_384 else { throw ActionPlanError.tooLarge }
        try db.transaction {
            let existing = try db.query("SELECT plan_size FROM action_attempts WHERE request_id=?", [.text(requestID.raw.uuidString)])
            if !existing.isEmpty {
                guard existing.allSatisfy({ $0["plan_size"]?.int != nil }) else { throw ActionPlanError.requestAlreadyUsed }
                return
            }
            let active = try db.query("""
                SELECT COUNT(DISTINCT request_id) AS n FROM action_attempts
                WHERE plan_size IS NOT NULL AND phase IN ('awaitingUser','claimed','ambiguous')
                """).first?["n"]?.int ?? 0
            guard active < 4 else { throw ActionPlanError.capacity }
            for (index, step) in steps.enumerated() {
                try insertAwaiting(requestID: requestID, capabilityID: step.action.capabilityID,
                    contractVersion: step.action.contractVersion, action: step.action,
                    pause: step.pause, notice: step.notice, stepIndex: index, planSize: steps.count, planState: step.state)
            }
        }
    }

    func planRecords(requestID: UserRequestID) throws -> [AttemptRecord] {
        let rows = try db.query("SELECT * FROM action_attempts WHERE request_id=? ORDER BY step_index", [.text(requestID.raw.uuidString)])
        guard rows.contains(where: { $0["plan_size"]?.int != nil }) else { return [] }
        let records = try rows.map(Self.decode)
        guard let size = records.first?.planSize, records.count == size,
              records.enumerated().allSatisfy({ $0.element.stepIndex == $0.offset && $0.element.planSize == size })
        else { throw ActionPlanError.corruptPlan }
        return records
    }

    func actionPlan(requestID: UserRequestID) throws -> ActionPlan? {
        let records = try planRecords(requestID: requestID)
        guard !records.isEmpty else { return nil }
        let steps = try records.map { record -> ActionPlanStep in
            var current = record
            current.planBlock = try planBlockingReason(for: current, action: current.action)
            let presentation: PlanStepPresentation
            if case .awaitingUser = current.phase, let reason = current.planState?.unsupportedReason {
                presentation = .unsupported(reason)
            } else if case .awaitingUser = current.phase, let contract = Self.contract(for: current) {
                presentation = .review(Self.card(for: current, contract: contract,
                    duplicate: try duplicateHint(for: current, contract: contract), now: now()))
            } else {
                presentation = .outcome(Self.result(for: current, contract: Self.contract(for: current)))
            }
            return ActionPlanStep(index: current.stepIndex, attemptID: current.attemptID,
                title: current.action.title, presentation: presentation)
        }
        return ActionPlan(requestID: requestID, steps: steps)
    }

    func materializePlan(requestID: UserRequestID) throws {
        try db.transaction {
            for record in try planRecords(requestID: requestID) {
                guard case .awaitingUser = record.phase, record.planState?.dependency != nil,
                      record.planState?.unsupportedReason == nil, record.action.arguments["body"] == nil,
                      let body = try verifiedPlanBody(for: record), let contract = Self.contract(for: record) else { continue }
                var action = record.action
                action.arguments["body"] = .text(body)
                let readiness = Self.readiness(action, contract: contract, now: now())
                _ = try updateAwaiting(attemptID: record.attemptID, expectedRevision: record.revision,
                    action: action, pause: readiness.pause, notice: readiness.notice)
            }
        }
    }

    func cancelAwaitingPlan(requestID: UserRequestID) throws {
        try db.transaction {
            for record in try planRecords(requestID: requestID) {
                if case .awaitingUser = record.phase { _ = try cancel(attemptID: record.attemptID) }
            }
        }
    }

    func planBlockingReason(for record: AttemptRecord, action: BoundAction) throws -> String? {
        guard record.planSize != nil else { return nil }
        guard let state = record.planState else { return "This saved plan cannot be read. It will not run." }
        if let reason = state.unsupportedReason { return reason }
        guard let contract = Self.contract(for: record), action.capabilityID == record.action.capabilityID,
              action.contractVersion == record.action.contractVersion, action.executor == record.action.executor
        else { return "This saved plan uses an unavailable action contract. It will not run." }
        if case .unsupported = PlanCapability(contract) { return "This action is unavailable in a plan." }
        guard state.dependency != nil else { return nil }
        guard case .consumer = PlanCapability(contract) else { return "Only a message can use a saved result in this plan." }
        guard let body = try verifiedPlanBody(for: record) else {
            return "Waiting for the earlier step to be saved and verified. Nothing will be sent."
        }
        guard record.action.arguments["body"] == .text(body), action.arguments["body"] == .text(body) else {
            return "Review the message prepared from the saved result before confirming."
        }
        return nil
    }

    func validatePlanEdit(record: AttemptRecord, action: BoundAction) throws {
        guard record.planState?.dependency != nil,
              action.arguments["body"] != record.action.arguments["body"] else { return }
        guard record.action.arguments["body"] == nil, let body = try verifiedPlanBody(for: record),
              action.arguments["body"] == .text(body) else {
            throw EffectError.invalidEdit("This message uses the verified saved result. Start a separate message to change that text.")
        }
    }

    func verifiedPlanBody(for record: AttemptRecord) throws -> String? {
        guard let state = record.planState, state.unsupportedReason == nil,
              let dependency = state.dependency, let required = state.requiredWrite,
              (0..<record.stepIndex).contains(dependency.stepIndex) else { return nil }
        let rows = try db.query("""
            SELECT * FROM action_attempts WHERE request_id=? AND step_index=? AND plan_size IS NOT NULL
            """, [.text(record.requestID.raw.uuidString), .int(Int64(dependency.stepIndex))])
        guard rows.count == 1, let predecessor = try? Self.decode(rows[0]), predecessor.planSize == record.planSize,
              predecessor.planState?.unsupportedReason == nil, let contract = Self.contract(for: predecessor),
              case .producer(let actual) = PlanCapability(contract), actual == required,
              case .settled(let disposition) = predecessor.phase, predecessor.receipt == disposition,
              case .committed(.eventKitItem(let identifier, let title, let instant)) = disposition,
              !identifier.isEmpty, !title.isEmpty, let instant, instant.timeIntervalSince1970.isFinite else { return nil }
        let zone = predecessor.action.timeZoneID ?? TimeZone.current.identifier
        let time = InstantText.full(instant, timeZoneID: zone)
        let text: String
        switch dependency.field {
        case .title: text = title
        case .time: text = time
        case .summary: text = "\(title) · \(time)"
        }
        return text.count <= ActionValidation.textLimit ? text : nil
    }
}

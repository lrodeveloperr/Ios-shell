import Foundation

public struct BenchEngine: Sendable {
    public private(set) var state: BenchState
    public init(state: BenchState = BenchState()) throws {
        self.state = state
        try Self.validate(state)
    }

    @discardableResult public mutating func apply(
        _ command: BenchCommand, actor: String, at: Date = Date(), operationID: UUID = UUID(),
        access: BenchAccess = .free
    ) throws -> BenchState {
        let name = try Self.required(actor, "Actor")
        if state.audit.contains(where: { $0.operationID == operationID }) ||
           state.archivedOperationIDs.contains(operationID) { return state }
        var next = state
        try Self.execute(command, in: &next, actor: name, at: at, operationID: operationID, access: access)
        try Self.validate(next)
        state = next
        return state
    }

    public static func decimal(_ value: String, nonnegative: Bool = false) throws -> Decimal {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.range(of: #"^-?[0-9]{1,9}(\.[0-9]{1,6})?$"#, options: .regularExpression) != nil,
              let result = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              (!nonnegative || result >= 0) else { throw BenchError.invalid("Enter a finite decimal with up to six fractional digits using a dot.") }
        return result
    }

    private static func required(_ text: String, _ label: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BenchError.invalid("\(label) must contain 1–256 printable characters.")
        }
        return trimmed
    }
    private static func shortNote(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4_000 else { throw BenchError.invalid("Note exceeds 4,000 characters.") }
        return trimmed
    }
    private static func identity(_ setup: Setup) -> String {
        [setup.part, setup.drawing, setup.machine].joined(separator: "\u{0}")
    }
    private static func normalizedExpected(_ input: [Checkpoint: String]) throws -> [Checkpoint: String] {
        guard Set(input.keys) == Set(Checkpoint.allCases) else { throw BenchError.invalid("All six preparation references are required.") }
        var result: [Checkpoint: String] = [:]
        for (key, value) in input { result[key] = try required(value, "Preparation reference") }
        return result
    }
    private static func normalizedDimensions(_ input: [Dimension]) throws -> [Dimension] {
        try input.map { d in
            Dimension(code: try required(d.code, "Dimension code"),
                      nominal: d.nominal.trimmingCharacters(in: .whitespacesAndNewlines),
                      minus: d.minus.trimmingCharacters(in: .whitespacesAndNewlines),
                      plus: d.plus.trimmingCharacters(in: .whitespacesAndNewlines),
                      unit: try required(d.unit, "Dimension unit"))
        }
    }
    private static func validSetup(_ setup: Setup) throws {
        guard setup.part == (try required(setup.part, "Part")),
              setup.drawing == (try required(setup.drawing, "Drawing revision")),
              setup.machine == (try required(setup.machine, "Machine")),
              setup.revision == (try required(setup.revision, "Setup revision")) else {
            throw BenchError.invalid("Setup identifiers must be stored without surrounding whitespace.")
        }
        guard Set(setup.expected.keys) == Set(Checkpoint.allCases) else { throw BenchError.invalid("All six preparation references are required.") }
        for value in setup.expected.values {
            guard value == (try required(value, "Preparation reference")) else { throw BenchError.invalid("Preparation reference has surrounding whitespace.") }
        }
        guard !setup.dimensions.isEmpty, setup.dimensions.count <= 100 else { throw BenchError.invalid("Specify 1–100 first-piece dimensions.") }
        var codes = Set<String>()
        for dimension in setup.dimensions {
            guard dimension.code == (try required(dimension.code, "Dimension code")),
                  dimension.unit == (try required(dimension.unit, "Dimension unit")),
                  dimension.nominal == dimension.nominal.trimmingCharacters(in: .whitespacesAndNewlines),
                  dimension.minus == dimension.minus.trimmingCharacters(in: .whitespacesAndNewlines),
                  dimension.plus == dimension.plus.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw BenchError.invalid("Dimension values must be stored without surrounding whitespace.")
            }
            let code = dimension.code.lowercased()
            guard codes.insert(code).inserted else { throw BenchError.conflict("Duplicate dimension code.") }
            _ = try decimal(dimension.nominal)
            _ = try decimal(dimension.minus, nonnegative: true)
            _ = try decimal(dimension.plus, nonnegative: true)
        }
        _ = try shortNote(setup.notes)
    }
    private static func addAudit(_ state: inout BenchState, _ id: UUID, _ at: Date, _ actor: String,
                                 _ action: String, _ subject: UUID, _ detail: String = "") {
        state.audit.append(Audit(operationID: id, at: at, actor: actor, action: action, subjectID: subject, detail: detail))
    }
    private static func getRun(_ state: BenchState, _ id: UUID, allowPendingHandoff: Bool = false) throws -> Run {
        guard let run = state.runs[id] else { throw BenchError.missing("Run not found.") }
        if !allowPendingHandoff, run.status != .closed, run.status != .aborted,
           let handoff = run.handoffs.last, handoff.acknowledgedAt == nil {
            throw BenchError.blocked("The named recipient must acknowledge the pending handoff before work continues.")
        }
        return run
    }
    private static func open(_ run: Run) throws {
        guard run.status != .closed && run.status != .aborted else { throw BenchError.blocked("This run is finished.") }
    }
    private static func current(_ run: Run, in state: BenchState) throws {
        guard let setup = state.setups[run.setupID], setup.status == .approved,
              setup.part == run.part, setup.drawing == run.drawing,
              setup.machine == run.machine, setup.revision == run.setupRevision else {
            throw BenchError.blocked("Approved setup or drawing revision changed. Review before proceeding.")
        }
    }
    private static func prepared(_ run: Run, _ setup: Setup) -> Bool {
        Checkpoint.allCases.allSatisfy { key in
            guard let confirmation = run.confirmations[key], let baseline = setup.expected[key] else { return false }
            let expected = run.deviations[key]?.runReference ?? baseline
            return confirmation.matches && confirmation.expected == expected
        }
    }
    private static func measured(_ run: Run, _ setup: Setup) -> Bool {
        setup.dimensions.allSatisfy { d in run.firstPiece.observations[d.code]?.withinTolerance == true }
    }
    private static func pauseForInspection(_ run: inout Run, id: UUID, at: Date, trigger: String, reason: String) {
        if let since = run.activeSince { run.elapsedSeconds += max(0, at.timeIntervalSince(since)); run.activeSince = nil }
        run.status = .held
        run.pendingInspection = InProcessInspection(id: id, trigger: trigger, dueGood: run.count(.good),
            at: at, observations: [:], decision: nil, reviewer: nil, reviewedAt: nil, reason: reason)
    }
    private static func enforceInterval(_ run: inout Run, disposition: PieceDisposition,
                                        in state: BenchState, id: UUID, at: Date) throws {
        guard disposition == .good, let due = run.nextInspectionGood,
              let interval = state.inspectionPolicies[run.setupID]?.everyGood,
              run.status == .running || run.status == .paused else { return }
        let good = run.count(.good)
        guard good <= due else { throw BenchError.blocked("Split the good count at piece \(due) and complete its inspection before further production.") }
        if good == due {
            pauseForInspection(&run, id: id, at: at, trigger: "scheduled", reason: "Every \(interval) good pieces")
        }
    }
    private static func hold(_ run: inout Run, detail: String, id: UUID, at: Date) {
        if let start = run.activeSince { run.elapsedSeconds += max(0, at.timeIntervalSince(start)); run.activeSince = nil }
        run.status = .held
        run.issues.append(Issue(id: id, detail: detail, openedAt: at, resolvedBy: nil, resolvedAt: nil, resolution: nil))
    }
    private static func approve(_ state: inout BenchState, setupID: UUID,
                                replacedDrawing: String?, coexistReason: String?, actor: String,
                                at: Date, operationID id: UUID, access: BenchAccess,
                                decisionReason: String = "") throws {
        guard var setup = state.setups[setupID], setup.status == .draft else {
            throw BenchError.blocked("Only an existing draft may be approved.")
        }
        guard state.inspectionPolicies[setupID] != nil else {
            throw BenchError.blocked("Decide the in-process inspection interval or explicitly select manual only before approval.")
        }
        try validSetup(setup)
        let family = SetupFamily(setup)
        let existingApprovedFamily = state.setups.values.contains {
            $0.approvedAt != nil && SetupFamily($0) == family
        }
        if access == .free && !existingApprovedFamily && state.freeFamilies.count == 2 {
            throw BenchError.blocked("Two setup families are included. Subscribe to approve another part and machine.")
        }
        let others = state.setups.values.filter { $0.status == .approved &&
            $0.part == setup.part && $0.machine == setup.machine && $0.drawing != setup.drawing }
        if let previous = replacedDrawing {
            guard previous != setup.drawing, !others.isEmpty,
                  others.allSatisfy({ $0.drawing == previous }) else {
                throw BenchError.blocked("The previous approved drawing must be explicit and unambiguous.")
            }
        } else if coexistReason == nil && !others.isEmpty {
            throw BenchError.blocked("Another drawing revision is approved. Explicitly replace it or approve coexistence.")
        } else if coexistReason != nil && others.isEmpty {
            throw BenchError.blocked("No other approved drawing requires a coexistence decision.")
        }
        for oldID in Array(state.setups.keys) {
            guard var old = state.setups[oldID], old.status == .approved,
                  old.part == setup.part, old.machine == setup.machine,
                  (old.drawing == setup.drawing || (replacedDrawing.map { old.drawing == $0 } ?? false)) else { continue }
            old.status = .superseded; state.setups[oldID] = old
            for runID in Array(state.runs.keys) {
                guard var run = state.runs[runID], run.setupID == oldID,
                      run.status != .closed && run.status != .aborted else { continue }
                hold(&run, detail: "Approved setup/drawing superseded by \(setup.drawing) / \(setup.revision).",
                     id: UUID(), at: at)
                state.runs[runID] = run
            }
        }
        setup.status = .approved; setup.approvedBy = actor; setup.approvedAt = at
        state.setups[setupID] = setup
        let action = replacedDrawing != nil ? "replaceDrawing" : (coexistReason != nil ? "approveCoexistingDrawing" : "approveSetup")
        let detail = replacedDrawing.map { "\($0) -> \(setup.drawing): \(decisionReason)" } ??
                     coexistReason.map { "coexists with other drawing: \($0)" } ?? setup.revision
        addAudit(&state, id, at, actor, action, setupID, detail)
    }

    private static func execute(_ command: BenchCommand, in state: inout BenchState,
                                actor: String, at: Date, operationID id: UUID, access: BenchAccess) throws {
        switch command {
        case let .draftSetup(part, drawing, machine, revision, expected, dimensions, notes):
            let setup = Setup(id: id, part: try required(part, "Part"), drawing: try required(drawing, "Drawing revision"),
                              machine: try required(machine, "Machine"), revision: try required(revision, "Setup revision"),
                              status: .draft, expected: try normalizedExpected(expected), dimensions: try normalizedDimensions(dimensions), notes: try shortNote(notes),
                              createdAt: at, approvedBy: nil, approvedAt: nil)
            try validSetup(setup)
            guard !state.setups.values.contains(where: { identity($0) == identity(setup) && $0.revision == setup.revision }) else {
                throw BenchError.conflict("This setup revision already exists for that part, drawing and machine.")
            }
            state.setups[id] = setup
            addAudit(&state, id, at, actor, "draftSetup", id, setup.revision)
        case let .reviseDraft(setupID, expected, dimensions, notes):
            guard var setup = state.setups[setupID], setup.status == .draft else { throw BenchError.blocked("Only an existing draft may be revised.") }
            setup.expected = try normalizedExpected(expected); setup.dimensions = try normalizedDimensions(dimensions); setup.notes = try shortNote(notes)
            try validSetup(setup)
            state.setups[setupID] = setup
            addAudit(&state, id, at, actor, "reviseDraft", setupID)
        case let .setDraftInspectionPolicy(setupID, everyGood, reason):
            guard state.setups[setupID]?.status == .draft else { throw BenchError.blocked("Inspection policy can only be set on a draft setup.") }
            guard everyGood == nil || (1...1_000_000).contains(everyGood!) else {
                throw BenchError.invalid("Inspection interval must be 1–1,000,000 good pieces.")
            }
            let why = try required(reason, "Inspection policy reason")
            state.inspectionPolicies[setupID] = InspectionPolicy(everyGood: everyGood, reason: why, decidedBy: actor, at: at)
            addAudit(&state, id, at, actor, "setInspectionPolicy", setupID,
                     everyGood.map { "every \($0) good: \(why)" } ?? "manual only: \(why)")
        case let .approveSetup(setupID):
            try approve(&state, setupID: setupID, replacedDrawing: nil, coexistReason: nil,
                        actor: actor, at: at, operationID: id, access: access)
        case let .replaceDrawing(setupID, previousDrawing, reason):
            let old = try required(previousDrawing, "Previous drawing revision")
            let why = try required(reason, "Drawing replacement reason")
            try approve(&state, setupID: setupID, replacedDrawing: old, coexistReason: nil,
                        actor: actor, at: at, operationID: id, access: access, decisionReason: why)
        case let .approveCoexistingDrawing(setupID, reason):
            let why = try required(reason, "Coexistence reason")
            try approve(&state, setupID: setupID, replacedDrawing: nil, coexistReason: why,
                        actor: actor, at: at, operationID: id, access: access)
        case let .start(job, part, drawing, machine, setupID, targetGood):
            guard let setup = state.setups[setupID] else { throw BenchError.missing("Setup not found.") }
            guard setup.status == .approved else { throw BenchError.blocked("Select an approved setup.") }
            if access == .free && !state.freeFamilies.contains(SetupFamily(setup)) {
                throw BenchError.blocked("Subscribe to start another run on this Pro setup family. Existing records remain available.")
            }
            let requestedPart = try required(part, "Part")
            let requestedDrawing = try required(drawing, "Drawing revision")
            let requestedMachine = try required(machine, "Machine")
            guard setup.part == requestedPart, setup.drawing == requestedDrawing,
                  setup.machine == requestedMachine else {
                throw BenchError.blocked("Part, drawing revision or machine does not match the selected setup.")
            }
            guard (1...1_000_000).contains(targetGood) else { throw BenchError.invalid("Target must be 1–1,000,000 good pieces.") }
            let jobName = try required(job, "Job")
            let run = Run(id: id, job: jobName, part: setup.part, drawing: setup.drawing, machine: setup.machine,
                          setupID: setupID, setupRevision: setup.revision, targetGood: targetGood, status: .preparing,
                          operatorName: actor, confirmations: [:], deviations: [:], firstPiece: FirstPiece(observations: [:], decision: nil, reviewer: nil, reviewedAt: nil),
                          firstPieceHistory: [], measurementHistory: [], counts: [], changes: [], issues: [], handoffs: [], attachments: [],
                          startedAt: at, closedAt: nil, closeReason: nil, activeSince: nil, elapsedSeconds: 0, proposedSetupID: nil)
            var scheduled = run
            scheduled.nextInspectionGood = state.inspectionPolicies[setupID]?.everyGood
            state.runs[id] = scheduled
            addAudit(&state, id, at, actor, "start", id, jobName)
        case let .confirm(runID, checkpoint, observed):
            var run = try getRun(state, runID); try open(run)
            guard (run.status == .preparing || run.status == .held), run.firstPiece.decision == nil,
                  run.firstPiece.observations.isEmpty else { throw BenchError.blocked("Preparation changed after inspection began; log a change to restart first-piece review.") }
            guard let setup = state.setups[run.setupID], let baseline = setup.expected[checkpoint] else { throw BenchError.missing("Setup checkpoint missing.") }
            let expected = run.deviations[checkpoint]?.runReference ?? baseline
            let value = try required(observed, "Observed reference")
            let matches = value == expected
            run.confirmations[checkpoint] = Confirmation(expected: expected, observed: value, actor: actor, at: at, matches: matches)
            if !matches { hold(&run, detail: "\(checkpoint.rawValue) mismatch: expected \(expected), observed \(value).", id: id, at: at) }
            else if prepared(run, setup) && run.unresolvedIssues.isEmpty && run.status == .preparing { run.status = .firstPiece }
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "confirm", runID, "\(checkpoint.rawValue): \(value)")
        case let .measure(runID, code, value):
            var run = try getRun(state, runID); try open(run)
            guard run.status == .firstPiece || run.status == .held else { throw BenchError.blocked("Measurements require the first-piece stage.") }
            guard let setup = state.setups[run.setupID], prepared(run, setup) else { throw BenchError.blocked("Confirm the six preparation references first.") }
            guard run.firstPiece.decision == nil else { throw BenchError.blocked("First-piece review is complete; log a change to require reinspection.") }
            guard let d = setup.dimensions.first(where: { $0.code == code }) else { throw BenchError.missing("Dimension not in the approved setup.") }
            guard run.firstPiece.observations[code] == nil else { throw BenchError.blocked("This dimension has a reading. Use repeatMeasurement with a reason.") }
            let v = try decimal(value), nominal = try decimal(d.nominal), lower = nominal - (try decimal(d.minus)), upper = nominal + (try decimal(d.plus))
            let pass = v >= lower && v <= upper
            let observation = Observation(dimension: code, value: value, withinTolerance: pass, actor: actor, at: at)
            run.firstPiece.observations[code] = observation; run.measurementHistory.append(observation)
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "measure", runID, "\(code): \(value); within tolerance: \(pass)")
        case let .repeatMeasurement(runID, code, value, reason):
            var run = try getRun(state, runID); try open(run)
            guard run.status == .firstPiece || run.status == .held, run.firstPiece.decision == nil,
                  run.firstPiece.observations[code] != nil else { throw BenchError.blocked("Repeat a recorded, unreviewed first-piece dimension.") }
            let why = try required(reason, "Repeat-measurement reason")
            guard let setup = state.setups[run.setupID], let d = setup.dimensions.first(where: { $0.code == code }) else { throw BenchError.missing("Dimension not found.") }
            let v = try decimal(value), nominal = try decimal(d.nominal)
            let pass = v >= nominal - (try decimal(d.minus)) && v <= nominal + (try decimal(d.plus))
            let observation = Observation(dimension: code, value: value, withinTolerance: pass, actor: actor, at: at)
            run.firstPiece.observations[code] = observation; run.measurementHistory.append(observation)
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "repeatMeasurement", runID, "\(code): \(value); reason: \(why); within tolerance: \(pass)")
        case let .review(runID, decision, reviewer, reason):
            var run = try getRun(state, runID); try open(run)
            guard (run.status == .firstPiece || run.status == .held), run.firstPiece.decision == nil else {
                throw BenchError.blocked("This first piece has already been reviewed. Log a change for a new first-piece cycle.")
            }
            let reviewerName = try required(reviewer, "Reviewer")
            guard let setup = state.setups[run.setupID], prepared(run, setup),
                  run.firstPiece.observations.count == setup.dimensions.count else { throw BenchError.blocked("Record every required first-piece measurement.") }
            if decision == .accept {
                try current(run, in: state)
                guard run.unresolvedIssues.isEmpty, measured(run, setup) else { throw BenchError.blocked("Resolve holds and out-of-tolerance measurements before acceptance.") }
                if let interval = state.inspectionPolicies[run.setupID]?.everyGood {
                    run.nextInspectionGood = run.count(.good) + interval
                } else { run.nextInspectionGood = nil }
                run.status = .running; run.activeSince = at
            } else {
                let why = try required(reason, "Rejection reason")
                hold(&run, detail: "First piece rejected: \(why)", id: id, at: at)
            }
            run.firstPiece.decision = decision; run.firstPiece.reviewer = reviewerName; run.firstPiece.reviewedAt = at
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "review", runID, "\(decision.rawValue) by \(reviewerName)")
        case let .pause(runID):
            var run = try getRun(state, runID); guard run.status == .running, let since = run.activeSince else { throw BenchError.blocked("Only an active run can be paused.") }
            run.elapsedSeconds += max(0, at.timeIntervalSince(since)); run.activeSince = nil; run.status = .paused
            state.runs[runID] = run; addAudit(&state, id, at, actor, "pause", runID)
        case let .resume(runID):
            var run = try getRun(state, runID)
            guard run.status == .paused else { throw BenchError.blocked("Only a paused run can resume.") }
            try current(run, in: state)
            guard run.unresolvedIssues.isEmpty, run.firstPiece.decision == .accept else { throw BenchError.blocked("Resolve holds and approve the first piece first.") }
            if let last = run.handoffs.last {
                guard last.acknowledgedBy == actor, last.to == actor else { throw BenchError.blocked("The named handoff recipient must acknowledge before resuming.") }
            }
            run.status = .running; run.activeSince = at
            state.runs[runID] = run; addAudit(&state, id, at, actor, "resume", runID)
        case let .recordCount(runID, disposition, quantity, reason):
            var run = try getRun(state, runID)
            guard run.status == .running else { throw BenchError.blocked("Counts require an active approved run.") }
            try current(run, in: state)
            guard (1...1_000_000).contains(quantity) else { throw BenchError.invalid("Quantity must be 1–1,000,000.") }
            let why = try required(reason, "Count reason")
            run.counts.append(CountEntry(id: id, disposition: disposition, delta: quantity, reason: why, actor: actor, at: at, corrects: nil))
            try enforceInterval(&run, disposition: disposition, in: state, id: id, at: at)
            state.runs[runID] = run; addAudit(&state, id, at, actor, "recordCount", runID, "\(disposition.rawValue) +\(quantity): \(why)")
        case let .requestInspection(runID, reason):
            var run = try getRun(state, runID)
            guard run.status == .running || run.status == .paused else { throw BenchError.blocked("Manual inspection requires an accepted active or paused production run.") }
            try current(run, in: state)
            let why = try required(reason, "Inspection trigger reason")
            pauseForInspection(&run, id: id, at: at, trigger: "manual", reason: why)
            state.runs[runID] = run; addAudit(&state, id, at, actor, "requestInspection", runID, why)
        case let .measureInspection(runID, code, value, repeatReason):
            var run = try getRun(state, runID)
            guard run.status == .held, var inspection = run.pendingInspection, inspection.decision == nil else {
                throw BenchError.blocked("No open in-process inspection is waiting for measurements.")
            }
            guard let setup = state.setups[run.setupID], let d = setup.dimensions.first(where: { $0.code == code }) else {
                throw BenchError.missing("Dimension not in the approved setup.")
            }
            if inspection.observations[code] != nil { _ = try required(repeatReason ?? "", "Repeat measurement reason") }
            else if repeatReason != nil { throw BenchError.invalid("A repeat reason is only valid after an initial reading.") }
            let reading = try decimal(value), nominal = try decimal(d.nominal)
            let pass = reading >= nominal - (try decimal(d.minus)) && reading <= nominal + (try decimal(d.plus))
            let observation = Observation(dimension: code, value: value, withinTolerance: pass, actor: actor, at: at)
            inspection.observations[code] = observation
            run.measurementHistory.append(observation)
            run.pendingInspection = inspection
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "measureInspection", runID,
                     "\(code): \(value); within tolerance: \(pass)" + (repeatReason.map { "; repeat: \($0)" } ?? ""))
        case let .reviewInspection(runID, decision, reviewer, reason):
            var run = try getRun(state, runID)
            guard run.status == .held, var inspection = run.pendingInspection, inspection.decision == nil,
                  let setup = state.setups[run.setupID],
                  inspection.observations.count == setup.dimensions.count else {
                throw BenchError.blocked("Measure every configured dimension before reviewing the open inspection.")
            }
            let name = try required(reviewer, "Inspection reviewer")
            inspection.decision = decision; inspection.reviewer = name; inspection.reviewedAt = at
            if decision == .accept {
                try current(run, in: state)
                guard run.unresolvedIssues.isEmpty,
                      setup.dimensions.allSatisfy({ inspection.observations[$0.code]?.withinTolerance == true }) else {
                    throw BenchError.blocked("Resolve issues and out-of-tolerance readings before accepting inspection.")
                }
                run.inspections = (run.inspections ?? []) + [inspection]
                run.pendingInspection = nil
                if inspection.trigger == "scheduled", let interval = state.inspectionPolicies[run.setupID]?.everyGood {
                    run.nextInspectionGood = inspection.dueGood + interval
                }
                run.status = .paused
            } else {
                let why = try required(reason, "Inspection rejection reason")
                inspection.reason += "; rejected: \(why)"
                run.pendingInspection = inspection
                hold(&run, detail: "In-process inspection rejected: \(why)", id: id, at: at)
            }
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "reviewInspection", runID, "\(decision.rawValue) by \(name)")
        case let .correctCount(runID, entryID, replacementQuantity, reason):
            var run = try getRun(state, runID)
            guard run.pendingInspection == nil else { throw BenchError.blocked("Finish the in-process inspection before correcting counts.") }
            guard let original = run.counts.first(where: { $0.id == entryID && $0.delta > 0 && $0.corrects == nil }),
                  !run.counts.contains(where: { $0.corrects == entryID }) else { throw BenchError.blocked("Count entry is missing or has already been corrected.") }
            guard (0...1_000_000).contains(replacementQuantity) else { throw BenchError.invalid("Replacement quantity must be 0–1,000,000.") }
            let why = try required(reason, "Correction reason")
            run.counts.append(CountEntry(id: id, disposition: original.disposition, delta: -original.delta, reason: why,
                                         actor: actor, at: at, corrects: entryID))
            if replacementQuantity > 0 {
                run.counts.append(CountEntry(id: UUID(), disposition: original.disposition, delta: replacementQuantity,
                                             reason: why, actor: actor, at: at, corrects: nil))
            }
            try enforceInterval(&run, disposition: original.disposition, in: state, id: id, at: at)
            state.runs[runID] = run; addAudit(&state, id, at, actor, "correctCount", runID, "\(entryID): \(original.delta) -> \(replacementQuantity): \(why)")
        case let .change(runID, kind, detail):
            var run = try getRun(state, runID); try open(run)
            let category = try required(kind, "Change type"), note = try required(detail, "New observed reference")
            guard Checkpoint(rawValue: category) != nil else { throw BenchError.invalid("Change type must be a preparation checkpoint (for example offsets or tools). Use issue for other exceptions.") }
            run.changes.append(Change(id: id, kind: category, detail: note, actor: actor, at: at))
            if let pending = run.pendingInspection {
                run.inspections = (run.inspections ?? []) + [pending]
                run.pendingInspection = nil
            }
            if let interval = state.inspectionPolicies[run.setupID]?.everyGood {
                run.nextInspectionGood = run.count(.good) + interval
            } else { run.nextInspectionGood = nil }
            if run.firstPiece.reviewedAt != nil { run.firstPieceHistory.append(run.firstPiece) }
            run.firstPiece = FirstPiece(observations: [:], decision: nil, reviewer: nil, reviewedAt: nil)
            hold(&run, detail: "Changed \(category): \(note). Reconfirm and reinspect.", id: id, at: at)
            run.confirmations = [:]
            state.runs[runID] = run; addAudit(&state, id, at, actor, "change", runID, "\(category): \(note)")
        case let .authorizeDeviation(runID, changeID, checkpoint, observed, reviewer, reason):
            var run = try getRun(state, runID); try open(run)
            guard run.status == .held, let change = run.changes.first(where: { $0.id == changeID }),
                  let issueIndex = run.issues.firstIndex(where: { $0.id == changeID && $0.resolvedAt == nil }),
                  change.kind == checkpoint.rawValue else { throw BenchError.blocked("An open change for that exact checkpoint is required.") }
            let value = try required(observed, "Observed new reference")
            guard value == change.detail else { throw BenchError.blocked("New reference must match the recorded change detail.") }
            let name = try required(reviewer, "Deviation reviewer"), why = try required(reason, "Deviation approval reason")
            guard let setup = state.setups[run.setupID], setup.status == .approved,
                  let baseline = setup.expected[checkpoint] else { throw BenchError.blocked("Only a current approved setup can authorize a run deviation.") }
            run.deviations[checkpoint] = Deviation(checkpoint: checkpoint, approvedReference: baseline,
                runReference: value, approvedBy: name, approvedAt: at, reason: why, changeID: changeID)
            run.issues[issueIndex].resolvedBy = name; run.issues[issueIndex].resolvedAt = at
            run.issues[issueIndex].resolution = why
            if run.unresolvedIssues.isEmpty { run.status = .preparing }
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "authorizeDeviation", runID, "\(checkpoint.rawValue): \(baseline) -> \(value); approved by \(name): \(why)")
        case let .acknowledgeHandoff(runID):
            var run = try getRun(state, runID, allowPendingHandoff: true); try open(run)
            guard let lastIndex = run.handoffs.indices.last, run.handoffs[lastIndex].acknowledgedAt == nil,
                  run.handoffs[lastIndex].to == actor else { throw BenchError.blocked("Only the named recipient can acknowledge the pending handoff.") }
            run.handoffs[lastIndex].acknowledgedBy = actor; run.handoffs[lastIndex].acknowledgedAt = at
            state.runs[runID] = run; addAudit(&state, id, at, actor, "acknowledgeHandoff", runID)
        case let .reassignHandoff(runID, to, reason):
            var run = try getRun(state, runID, allowPendingHandoff: true); try open(run)
            guard let pending = run.handoffs.last, pending.acknowledgedAt == nil else {
                throw BenchError.blocked("Only an unacknowledged handoff can be reassigned.")
            }
            let recipient = try required(to, "New recipient")
            guard recipient != pending.to else { throw BenchError.invalid("Select a different recipient.") }
            let why = try required(reason, "Reassignment reason")
            run.handoffs.append(Handoff(id: id, to: recipient, by: actor, at: at,
                status: run.status, remainingGood: run.remainingGood,
                unresolvedIssueIDs: run.unresolvedIssues.map(\.id),
                note: "Reassigned from \(pending.to): \(why)", acknowledgedBy: nil, acknowledgedAt: nil,
                reassignedFrom: pending.id))
            state.runs[runID] = run
            addAudit(&state, id, at, actor, "reassignHandoff", runID,
                     "\(pending.to) -> \(recipient): \(why)")
        case let .issue(runID, detail):
            var run = try getRun(state, runID); try open(run)
            hold(&run, detail: try required(detail, "Issue"), id: id, at: at)
            state.runs[runID] = run; addAudit(&state, id, at, actor, "issue", runID, detail)
        case let .resolve(runID, issueID, resolution):
            var run = try getRun(state, runID); try open(run)
            guard let index = run.issues.firstIndex(where: { $0.id == issueID && $0.resolvedAt == nil }) else { throw BenchError.missing("Open issue not found.") }
            guard state.setups[run.setupID]?.status == .approved else { throw BenchError.blocked("Superseded setup cannot be cleared. Abort and start a run with the current approved setup.") }
            guard !run.changes.contains(where: { $0.id == issueID }) else { throw BenchError.blocked("A process-reference change requires an explicit reviewed run deviation.") }
            run.issues[index].resolvedBy = actor; run.issues[index].resolvedAt = at
            run.issues[index].resolution = try required(resolution, "Resolution")
            if run.unresolvedIssues.isEmpty && run.firstPiece.decision == .reject {
                run.firstPieceHistory.append(run.firstPiece)
                run.firstPiece = FirstPiece(observations: [:], decision: nil, reviewer: nil, reviewedAt: nil)
            }
            if run.unresolvedIssues.isEmpty, var inspection = run.pendingInspection, inspection.decision == .reject {
                run.inspections = (run.inspections ?? []) + [inspection]
                inspection = InProcessInspection(id: id, trigger: inspection.trigger, dueGood: run.count(.good),
                    at: at, observations: [:], decision: nil, reviewer: nil, reviewedAt: nil,
                    reason: "Repeat after rejected inspection")
                run.pendingInspection = inspection
            }
            if run.unresolvedIssues.isEmpty, let setup = state.setups[run.setupID], run.pendingInspection == nil {
                if prepared(run, setup) { run.status = run.firstPiece.decision == .accept ? .paused : .firstPiece }
                else { run.status = .preparing }
            }
            state.runs[runID] = run; addAudit(&state, id, at, actor, "resolve", runID, "\(issueID): \(resolution)")
        case let .handoff(runID, to, note):
            var run = try getRun(state, runID); try open(run)
            if let since = run.activeSince {
                run.elapsedSeconds += max(0, at.timeIntervalSince(since)); run.activeSince = nil; run.status = .paused
            }
            run.handoffs.append(Handoff(id: id, to: try required(to, "Recipient"), by: actor, at: at,
                                        status: run.status, remainingGood: run.remainingGood,
                                        unresolvedIssueIDs: run.unresolvedIssues.map(\.id), note: try shortNote(note), acknowledgedBy: nil, acknowledgedAt: nil))
            state.runs[runID] = run; addAudit(&state, id, at, actor, "handoff", runID, to)
        case let .attach(runID, filename, mimeType, bytes):
            var run = try getRun(state, runID); try open(run)
            let mime = try required(mimeType, "MIME type")
            guard ["image/jpeg", "image/png", "application/pdf"].contains(mime) else { throw BenchError.invalid("Only JPEG, PNG and PDF attachments are supported.") }
            let signatureOK: Bool = {
                switch mime {
                case "image/jpeg": return bytes.starts(with: [0xFF, 0xD8, 0xFF])
                case "image/png": return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                default: return bytes.starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D])
                }
            }()
            guard signatureOK, bytes.count <= 4_000_000, run.attachments.count < 40,
                  run.attachments.reduce(0, { $0 + $1.bytes.count }) + bytes.count <= 40_000_000 else {
                throw BenchError.invalid("Attachment exceeds the per-file, count or per-run limit.")
            }
            let filenameValue = try required(filename, "Filename")
            guard !filenameValue.contains("/") && !filenameValue.contains("\\") else { throw BenchError.invalid("Filename cannot include a path.") }
            run.attachments.append(Attachment(id: id, filename: filenameValue, mimeType: mime, bytes: bytes, actor: actor, at: at))
            state.runs[runID] = run; addAudit(&state, id, at, actor, "attach", runID, filenameValue)
        case let .proposeSetup(runID, revision, expected, dimensions, notes):
            var run = try getRun(state, runID); try open(run)
            guard run.proposedSetupID == nil else { throw BenchError.conflict("This run already has a proposed revision.") }
            let old = state.setups[run.setupID]!
            let proposal = Setup(id: id, part: old.part, drawing: old.drawing, machine: old.machine,
                                 revision: try required(revision, "Proposed setup revision"), status: .draft,
                                 expected: try normalizedExpected(expected), dimensions: try normalizedDimensions(dimensions), notes: try shortNote(notes),
                                 createdAt: at, approvedBy: nil, approvedAt: nil)
            try validSetup(proposal)
            guard !state.setups.values.contains(where: { identity($0) == identity(proposal) && $0.revision == proposal.revision }) else {
                throw BenchError.conflict("Proposed revision already exists.")
            }
            state.setups[id] = proposal; run.proposedSetupID = id; state.runs[runID] = run
            addAudit(&state, id, at, actor, "proposeSetup", runID, proposal.revision)
        case let .close(runID, reason):
            var run = try getRun(state, runID); try open(run)
            guard run.status == .running || run.status == .paused else { throw BenchError.blocked("Resolve holds and review the first piece before closing.") }
            try current(run, in: state)
            guard run.unresolvedIssues.isEmpty, run.firstPiece.decision == .accept,
                  run.count(.quarantine) == 0 else { throw BenchError.blocked("Resolve holds, complete first-piece approval and clear quarantine before closing.") }
            let why = try required(reason, "Closeout reason")
            if let since = run.activeSince { run.elapsedSeconds += max(0, at.timeIntervalSince(since)); run.activeSince = nil }
            run.status = .closed; run.closedAt = at; run.closeReason = why
            state.runs[runID] = run; addAudit(&state, id, at, actor, "close", runID, why)
        case let .abort(runID, reason):
            var run = try getRun(state, runID, allowPendingHandoff: true); try open(run)
            let why = try required(reason, "Abandonment reason")
            if let pending = run.pendingInspection {
                run.inspections = (run.inspections ?? []) + [pending]
                run.pendingInspection = nil
            }
            if let since = run.activeSince { run.elapsedSeconds += max(0, at.timeIntervalSince(since)); run.activeSince = nil }
            run.status = .aborted; run.closedAt = at; run.closeReason = why
            state.runs[runID] = run; addAudit(&state, id, at, actor, "abort", runID, why)
        case let .setLocale(locale):
            guard ["en-US", "en-CA"].contains(locale) else { throw BenchError.invalid("Supported locales: en-US and en-CA.") }
            state.locale = locale; addAudit(&state, id, at, actor, "setLocale", id, locale)
        }
    }

    public static func validate(_ state: BenchState) throws {
        guard state.schema == 1 else { throw BenchError.unsupportedSchema(state.schema) }
        guard ["en-US", "en-CA"].contains(state.locale) else { throw BenchError.invalid("Unsupported locale.") }
        guard Set(state.audit.map(\.operationID)).count == state.audit.count,
              state.archivedOperationIDs.isDisjoint(with: Set(state.audit.map(\.operationID))) else {
            throw BenchError.invalid("Duplicate operation ID in live or archived audit.")
        }
        guard Set(state.archiveReceipts.map(\.id)).count == state.archiveReceipts.count else { throw BenchError.invalid("Duplicate archive receipt.") }
        for receipt in state.archiveReceipts {
            guard !receipt.runIDs.isEmpty, Set(receipt.runIDs).count == receipt.runIDs.count,
                  receipt.bytes > 0, receipt.sha256.count == 64,
                  !receipt.filename.isEmpty, receipt.filename.count <= 256,
                  receipt.runIDs.allSatisfy({ state.runs[$0] == nil }) else {
                throw BenchError.invalid("Archive receipt conflicts with live data.")
            }
        }
        let allRevisions = Array(state.setups.values)
        for (id, setup) in state.setups {
            guard id == setup.id else { throw BenchError.invalid("Setup ID mismatch.") }
            try validSetup(setup)
            guard (setup.status == .draft) == (setup.approvedBy == nil && setup.approvedAt == nil) else { throw BenchError.invalid("Setup approval metadata mismatch.") }
        }
        for (id, policy) in state.inspectionPolicies {
            guard state.setups[id] != nil, policy.everyGood == nil || (1...1_000_000).contains(policy.everyGood!),
                  policy.reason == (try required(policy.reason, "Inspection policy reason")),
                  policy.decidedBy == (try required(policy.decidedBy, "Inspection policy actor")) else {
                throw BenchError.invalid("Invalid in-process inspection policy.")
            }
        }
        var revisionKeys = Set<String>()
        var approvedKeys = Set<String>()
        for setup in allRevisions {
            let key = identity(setup)
            guard revisionKeys.insert(key + "\u{0}" + setup.revision).inserted else { throw BenchError.invalid("Duplicate setup revision.") }
            if setup.status == .approved {
                guard approvedKeys.insert(key).inserted else { throw BenchError.invalid("Multiple approved revisions.") }
            }
        }
        for (id, run) in state.runs {
            guard id == run.id, let setup = state.setups[run.setupID],
                  run.part == setup.part, run.drawing == setup.drawing,
                  run.machine == setup.machine, run.setupRevision == setup.revision else { throw BenchError.invalid("Run/setup identity mismatch.") }
            guard (1...1_000_000).contains(run.targetGood), run.elapsedSeconds >= 0,
                  (run.status == .running) == (run.activeSince != nil),
                  ([RunStatus.closed, .aborted].contains(run.status)) == (run.closedAt != nil) else { throw BenchError.invalid("Run state is inconsistent.") }
            let policyInterval = state.inspectionPolicies[run.setupID]?.everyGood
            if let interval = policyInterval {
                guard let due = run.nextInspectionGood, due > 0,
                      due <= 2_000_000, (run.status != .running && run.status != .paused) || due > run.count(.good),
                      run.pendingInspection != nil || run.status != .held || due > run.count(.good),
                      interval > 0 else { throw BenchError.invalid("Scheduled inspection threshold is missing or passed without a hold.") }
            } else if run.nextInspectionGood != nil {
                throw BenchError.invalid("Inspection threshold lacks a setup policy.")
            }
            if let pending = run.pendingInspection {
                guard run.status == .held, run.activeSince == nil, run.firstPiece.decision == .accept,
                      pending.dueGood == run.count(.good), pending.decision != .accept,
                      (pending.decision == nil) == (pending.reviewer == nil && pending.reviewedAt == nil),
                      pending.trigger == "manual" || pending.trigger == "scheduled" else {
                    throw BenchError.invalid("Invalid pending in-process inspection.")
                }
                if pending.trigger == "scheduled" {
                    guard policyInterval != nil, pending.dueGood == run.nextInspectionGood else {
                        throw BenchError.invalid("Scheduled inspection does not match the configured threshold.")
                    }
                }
            }
            for inspection in (run.inspections ?? []) + (run.pendingInspection.map { [$0] } ?? []) {
                guard inspection.dueGood >= 0,
                      inspection.observations.count <= setup.dimensions.count,
                      (inspection.reviewer == nil) == (inspection.reviewedAt == nil),
                      inspection.decision == nil || inspection.reviewer != nil else {
                    throw BenchError.invalid("Invalid in-process inspection record.")
                }
                for (code, observation) in inspection.observations {
                    guard let dimension = setup.dimensions.first(where: { $0.code == code }),
                          observation.dimension == code else { throw BenchError.invalid("Unknown inspection dimension.") }
                    let value = try decimal(observation.value), nominal = try decimal(dimension.nominal)
                    guard observation.withinTolerance == (value >= nominal - (try decimal(dimension.minus)) &&
                          value <= nominal + (try decimal(dimension.plus))) else {
                        throw BenchError.invalid("Inspection measurement does not match its tolerance.")
                    }
                }
                if inspection.decision == .accept {
                    guard inspection.observations.count == setup.dimensions.count,
                          inspection.observations.values.allSatisfy({ $0.withinTolerance }) else {
                        throw BenchError.invalid("Accepted inspection lacks passing measurements.")
                    }
                }
            }
            guard (run.inspections ?? []).count <= 100_000 else { throw BenchError.invalid("Inspection history exceeds limits.") }
            guard run.measurementHistory.count <= 100_000, run.counts.count <= 100_000,
                  run.counts.allSatisfy({ $0.delta != 0 && (-1_000_000...1_000_000).contains($0.delta) }) else {
                throw BenchError.invalid("Count ledger exceeds limits.")
            }
            guard run.counts.map(\.id).count == Set(run.counts.map(\.id)).count else { throw BenchError.invalid("Duplicate count ID.") }
            var priorPositive: [UUID: CountEntry] = [:]
            var reversed = Set<UUID>()
            for entry in run.counts {
                if entry.delta > 0 {
                    guard entry.corrects == nil else { throw BenchError.invalid("Positive count cannot reverse another entry.") }
                    priorPositive[entry.id] = entry
                } else {
                    guard let targetID = entry.corrects, let target = priorPositive[targetID],
                          reversed.insert(targetID).inserted,
                          entry.disposition == target.disposition, entry.delta == -target.delta else {
                        throw BenchError.invalid("Count reversal does not match a prior uncorrected entry.")
                    }
                }
            }
            for disposition in [PieceDisposition.good, .scrap, .quarantine] {
                guard run.count(disposition) >= 0, run.count(disposition) <= 1_000_000_000 else { throw BenchError.invalid("Invalid count total.") }
            }
            guard run.count(.good) <= run.targetGood else { throw BenchError.invalid("Good count exceeds target.") }
            for (key, confirmation) in run.confirmations {
                guard let baseline = setup.expected[key] else { throw BenchError.invalid("Missing preparation reference.") }
                let expected = run.deviations[key]?.runReference ?? baseline
                guard confirmation.expected == expected,
                      confirmation.matches == (confirmation.observed == expected) else { throw BenchError.invalid("Invalid preparation confirmation.") }
            }
            for (key, deviation) in run.deviations {
                guard let baseline = setup.expected[key], deviation.checkpoint == key,
                      deviation.approvedReference == baseline,
                      run.changes.contains(where: { $0.id == deviation.changeID && $0.kind == key.rawValue && $0.detail == deviation.runReference }) else {
                    throw BenchError.invalid("Run deviation does not match its change and approved baseline.")
                }
            }
            for index in run.handoffs.indices {
                let handoff = run.handoffs[index]
                guard (handoff.acknowledgedBy == nil) == (handoff.acknowledgedAt == nil),
                      handoff.acknowledgedBy == nil || handoff.acknowledgedBy == handoff.to else {
                    throw BenchError.invalid("Invalid handoff acknowledgment.")
                }
                if index > 0 && run.handoffs[index - 1].acknowledgedAt == nil {
                    let prior = run.handoffs[index - 1]
                    guard handoff.reassignedFrom == prior.id,
                          handoff.note.contains("Reassigned from \(prior.to): "),
                          state.audit.contains(where: { $0.operationID == handoff.id &&
                              $0.subjectID == run.id && $0.action == "reassignHandoff" && $0.actor == handoff.by }) else {
                        throw BenchError.invalid("Unacknowledged handoff was replaced without a recorded reassignment.")
                    }
                } else if handoff.reassignedFrom != nil {
                    throw BenchError.invalid("Handoff reassignment does not follow a pending handoff.")
                }
            }
            for (code, observation) in run.firstPiece.observations {
                guard let dimension = setup.dimensions.first(where: { $0.code == code }) else { throw BenchError.invalid("Unknown measured dimension.") }
                let value = try decimal(observation.value), nominal = try decimal(dimension.nominal)
                guard observation.dimension == code,
                      observation.withinTolerance == (value >= nominal - (try decimal(dimension.minus)) && value <= nominal + (try decimal(dimension.plus))) else {
                    throw BenchError.invalid("Measurement result does not match the approved tolerances.")
                }
            }
            guard run.attachments.count <= 40, run.attachments.reduce(0, { $0 + $1.bytes.count }) <= 40_000_000 else { throw BenchError.invalid("Attachment limit exceeded.") }
            if run.status == .running || run.status == .paused {
                guard setup.status == .approved else { throw BenchError.invalid("Open production run references a superseded setup.") }
            }
            if run.status == .running || run.status == .paused || run.status == .closed {
                guard run.unresolvedIssues.isEmpty, prepared(run, setup), measured(run, setup), run.firstPiece.decision == .accept else {
                    throw BenchError.invalid("Production state lacks preparation or first-piece approval.")
                }
            }
            if run.status == .closed { guard run.count(.quarantine) == 0, run.closeReason != nil else { throw BenchError.invalid("Closed run has unresolved output.") } }
            if let proposal = run.proposedSetupID { guard let proposed = state.setups[proposal], proposed.part == run.part,
                proposed.drawing == run.drawing, proposed.machine == run.machine else { throw BenchError.invalid("Proposed revision mismatch.") } }
        }
    }
}

import Foundation

public enum BenchError: Error, Equatable, LocalizedError {
    case invalid(String)
    case conflict(String)
    case missing(String)
    case blocked(String)
    case unsupportedSchema(Int)
    public var errorDescription: String? {
        switch self {
        case .invalid(let m), .conflict(let m), .missing(let m), .blocked(let m): return m
        case .unsupportedSchema(let v): return "Unsupported backup schema \(v). Update the app before restoring."
        }
    }
}

public enum Checkpoint: String, CaseIterable, Codable, Sendable {
    case stock, program, fixture, tools, offsets, documents
}
public enum RevisionStatus: String, Codable, Sendable { case draft, approved, superseded }
public enum RunStatus: String, Codable, Sendable { case preparing, firstPiece, running, paused, held, closed, aborted }
public enum PieceDisposition: String, Codable, Sendable { case good, scrap, quarantine }
public enum Decision: String, Codable, Sendable { case accept, reject }

public struct Dimension: Codable, Equatable, Sendable {
    public var code: String
    public var nominal: String
    public var minus: String
    public var plus: String
    public var unit: String
    public init(code: String, nominal: String, minus: String, plus: String, unit: String) {
        self.code = code; self.nominal = nominal; self.minus = minus; self.plus = plus; self.unit = unit
    }
}

public struct Setup: Codable, Equatable, Sendable {
    public var id: UUID
    public var part: String
    public var drawing: String
    public var machine: String
    public var revision: String
    public var status: RevisionStatus
    public var expected: [Checkpoint: String]
    public var dimensions: [Dimension]
    public var notes: String
    public var createdAt: Date
    public var approvedBy: String?
    public var approvedAt: Date?
}

/// The free limit is per exact part and machine, independent of drawing/setup revision.
public struct SetupFamily: Codable, Hashable, Sendable {
    public let part: String
    public let machine: String
    public init(part: String, machine: String) { self.part = part; self.machine = machine }
    public init(_ setup: Setup) { self.init(part: setup.part, machine: setup.machine) }
}

/// This value must come from verified StoreKit entitlements in an iOS host.
/// It is deliberately never serialized in a shop backup.
public enum BenchAccess: Equatable, Sendable { case free, pro }

public struct Confirmation: Codable, Equatable, Sendable {
    public var expected: String
    public var observed: String
    public var actor: String
    public var at: Date
    public var matches: Bool
}
public struct Observation: Codable, Equatable, Sendable {
    public var dimension: String
    public var value: String
    public var withinTolerance: Bool
    public var actor: String
    public var at: Date
}
public struct InspectionPolicy: Codable, Equatable, Sendable {
    public var everyGood: Int? // nil is an explicit decision to use manual inspections only
    public var reason: String
    public var decidedBy: String
    public var at: Date
}
public struct InProcessInspection: Codable, Equatable, Sendable {
    public var id: UUID
    public var trigger: String
    public var dueGood: Int
    public var at: Date
    public var observations: [String: Observation]
    public var decision: Decision?
    public var reviewer: String?
    public var reviewedAt: Date?
    public var reason: String
}
public struct FirstPiece: Codable, Equatable, Sendable {
    public var observations: [String: Observation]
    public var decision: Decision?
    public var reviewer: String?
    public var reviewedAt: Date?
}
public struct CountEntry: Codable, Equatable, Sendable {
    public var id: UUID
    public var disposition: PieceDisposition
    public var delta: Int
    public var reason: String
    public var actor: String
    public var at: Date
    public var corrects: UUID?
}
public struct Change: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: String
    public var detail: String
    public var actor: String
    public var at: Date
}
public struct Issue: Codable, Equatable, Sendable {
    public var id: UUID
    public var detail: String
    public var openedAt: Date
    public var resolvedBy: String?
    public var resolvedAt: Date?
    public var resolution: String?
}
public struct Deviation: Codable, Equatable, Sendable {
    public var checkpoint: Checkpoint
    public var approvedReference: String
    public var runReference: String
    public var approvedBy: String
    public var approvedAt: Date
    public var reason: String
    public var changeID: UUID
}
public struct Handoff: Codable, Equatable, Sendable {
    public var id: UUID
    public var to: String
    public var by: String
    public var at: Date
    public var status: RunStatus
    public var remainingGood: Int
    public var unresolvedIssueIDs: [UUID]
    public var note: String
    public var acknowledgedBy: String?
    public var acknowledgedAt: Date?
    public var reassignedFrom: UUID?
    public init(id: UUID, to: String, by: String, at: Date, status: RunStatus,
                remainingGood: Int, unresolvedIssueIDs: [UUID], note: String,
                acknowledgedBy: String?, acknowledgedAt: Date?, reassignedFrom: UUID? = nil) {
        self.id = id; self.to = to; self.by = by; self.at = at; self.status = status
        self.remainingGood = remainingGood; self.unresolvedIssueIDs = unresolvedIssueIDs
        self.note = note; self.acknowledgedBy = acknowledgedBy; self.acknowledgedAt = acknowledgedAt
        self.reassignedFrom = reassignedFrom
    }
    private enum CodingKeys: String, CodingKey {
        case id, to, by, at, status, remainingGood, unresolvedIssueIDs, note,
             acknowledgedBy, acknowledgedAt, reassignedFrom
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        to = try c.decode(String.self, forKey: .to)
        by = try c.decode(String.self, forKey: .by)
        at = try c.decode(Date.self, forKey: .at)
        status = try c.decode(RunStatus.self, forKey: .status)
        remainingGood = try c.decode(Int.self, forKey: .remainingGood)
        unresolvedIssueIDs = try c.decode([UUID].self, forKey: .unresolvedIssueIDs)
        note = try c.decode(String.self, forKey: .note)
        acknowledgedBy = try c.decodeIfPresent(String.self, forKey: .acknowledgedBy)
        acknowledgedAt = try c.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        reassignedFrom = try c.decodeIfPresent(UUID.self, forKey: .reassignedFrom)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(to, forKey: .to)
        try c.encode(by, forKey: .by); try c.encode(at, forKey: .at)
        try c.encode(status, forKey: .status); try c.encode(remainingGood, forKey: .remainingGood)
        try c.encode(unresolvedIssueIDs, forKey: .unresolvedIssueIDs); try c.encode(note, forKey: .note)
        try c.encodeIfPresent(acknowledgedBy, forKey: .acknowledgedBy)
        try c.encodeIfPresent(acknowledgedAt, forKey: .acknowledgedAt)
        try c.encodeIfPresent(reassignedFrom, forKey: .reassignedFrom)
    }
}
public struct Attachment: Codable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    public var mimeType: String
    public var bytes: Data
    public var actor: String
    public var at: Date
}
public struct Run: Codable, Equatable, Sendable {
    public var id: UUID
    public var job: String
    public var part: String
    public var drawing: String
    public var machine: String
    public var setupID: UUID
    public var setupRevision: String
    public var targetGood: Int
    public var status: RunStatus
    public var operatorName: String
    public var confirmations: [Checkpoint: Confirmation]
    public var deviations: [Checkpoint: Deviation]
    public var firstPiece: FirstPiece
    public var firstPieceHistory: [FirstPiece]
    public var measurementHistory: [Observation]
    public var counts: [CountEntry]
    public var changes: [Change]
    public var issues: [Issue]
    public var handoffs: [Handoff]
    public var attachments: [Attachment]
    public var startedAt: Date
    public var closedAt: Date?
    public var closeReason: String?
    public var activeSince: Date?
    public var elapsedSeconds: TimeInterval
    public var proposedSetupID: UUID?
    // Optional for decoding backups made before the inspection feature.
    public var inspections: [InProcessInspection]? = nil
    public var pendingInspection: InProcessInspection? = nil
    public var nextInspectionGood: Int? = nil

    public func count(_ disposition: PieceDisposition) -> Int {
        counts.filter { $0.disposition == disposition }.reduce(0) { $0 + $1.delta }
    }
    public var unresolvedIssues: [Issue] { issues.filter { $0.resolvedAt == nil } }
    public var remainingGood: Int { max(0, targetGood - count(.good)) }
}
public struct Audit: Codable, Equatable, Sendable {
    public var operationID: UUID
    public var at: Date
    public var actor: String
    public var action: String
    public var subjectID: UUID
    public var detail: String
}
public struct ArchiveReceipt: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var runIDs: [UUID]
    public var filename: String
    public var sha256: String
    public var bytes: Int
}
public struct BenchState: Codable, Equatable, Sendable {
    public var schema: Int = 1
    public var setups: [UUID: Setup] = [:]
    public var runs: [UUID: Run] = [:]
    public var audit: [Audit] = []
    public var archiveReceipts: [ArchiveReceipt] = []
    public var archivedOperationIDs: Set<UUID> = []
    public var inspectionPolicies: [UUID: InspectionPolicy] = [:]
    public var locale: String = "en-US"
    public init() {}
    private enum CodingKeys: String, CodingKey { case schema, setups, runs, audit, archiveReceipts, archivedOperationIDs, inspectionPolicies, locale }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        setups = try c.decode([UUID: Setup].self, forKey: .setups)
        runs = try c.decode([UUID: Run].self, forKey: .runs)
        audit = try c.decode([Audit].self, forKey: .audit)
        archiveReceipts = try c.decodeIfPresent([ArchiveReceipt].self, forKey: .archiveReceipts) ?? []
        archivedOperationIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .archivedOperationIDs) ?? []
        inspectionPolicies = try c.decodeIfPresent([UUID: InspectionPolicy].self, forKey: .inspectionPolicies) ?? [:]
        locale = try c.decode(String.self, forKey: .locale)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(setups, forKey: .setups)
        try c.encode(runs, forKey: .runs)
        try c.encode(audit, forKey: .audit)
        try c.encode(archiveReceipts, forKey: .archiveReceipts)
        try c.encode(archivedOperationIDs, forKey: .archivedOperationIDs)
        try c.encode(inspectionPolicies, forKey: .inspectionPolicies)
        try c.encode(locale, forKey: .locale)
    }

    /// The first two distinct approved families stay usable when Pro expires.
    /// Approval audit order is stable even when the device clock moves backwards.
    /// Superseded revisions still identify the original family; drafts do not claim a slot.
    public var freeFamilies: [SetupFamily] {
        var result: [SetupFamily] = []
        for event in audit where ["approveSetup", "replaceDrawing", "approveCoexistingDrawing"].contains(event.action) {
            guard let setup = setups[event.subjectID], setup.approvedAt != nil else { continue }
            let family = SetupFamily(setup)
            if !result.contains(family) { result.append(family) }
            if result.count == 2 { return result }
        }
        // Older imported data may lack the approval audit; use stable metadata.
        let approved = setups.values.filter { $0.approvedAt != nil }.sorted {
            if $0.approvedAt! != $1.approvedAt! { return $0.approvedAt! < $1.approvedAt! }
            return $0.id.uuidString < $1.id.uuidString
        }
        for setup in approved {
            let family = SetupFamily(setup)
            if !result.contains(family) { result.append(family) }
            if result.count == 2 { break }
        }
        return result
    }
}

public enum BenchCommand: Sendable {
    case draftSetup(part: String, drawing: String, machine: String, revision: String, expected: [Checkpoint: String], dimensions: [Dimension], notes: String)
    case reviseDraft(setupID: UUID, expected: [Checkpoint: String], dimensions: [Dimension], notes: String)
    case setDraftInspectionPolicy(setupID: UUID, everyGood: Int?, reason: String)
    case approveSetup(setupID: UUID)
    case replaceDrawing(setupID: UUID, previousDrawing: String, reason: String)
    case approveCoexistingDrawing(setupID: UUID, reason: String)
    case start(job: String, part: String, drawing: String, machine: String, setupID: UUID, targetGood: Int)
    case confirm(runID: UUID, checkpoint: Checkpoint, observed: String)
    case measure(runID: UUID, code: String, value: String)
    case repeatMeasurement(runID: UUID, code: String, value: String, reason: String)
    case review(runID: UUID, decision: Decision, reviewer: String, reason: String)
    case resume(runID: UUID)
    case pause(runID: UUID)
    case recordCount(runID: UUID, disposition: PieceDisposition, quantity: Int, reason: String)
    case requestInspection(runID: UUID, reason: String)
    case measureInspection(runID: UUID, code: String, value: String, repeatReason: String?)
    case reviewInspection(runID: UUID, decision: Decision, reviewer: String, reason: String)
    case correctCount(runID: UUID, entryID: UUID, replacementQuantity: Int, reason: String)
    case change(runID: UUID, kind: String, detail: String)
    case authorizeDeviation(runID: UUID, changeID: UUID, checkpoint: Checkpoint, observed: String, reviewer: String, reason: String)
    case acknowledgeHandoff(runID: UUID)
    case reassignHandoff(runID: UUID, to: String, reason: String)
    case issue(runID: UUID, detail: String)
    case resolve(runID: UUID, issueID: UUID, resolution: String)
    case handoff(runID: UUID, to: String, note: String)
    case attach(runID: UUID, filename: String, mimeType: String, bytes: Data)
    case proposeSetup(runID: UUID, revision: String, expected: [Checkpoint: String], dimensions: [Dimension], notes: String)
    case close(runID: UUID, reason: String)
    case abort(runID: UUID, reason: String)
    case setLocale(String)
}

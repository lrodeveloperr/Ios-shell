import Foundation

public enum BenchExport {
    public static func handoff(_ run: Run, setup: Setup) -> String {
        let issues = run.unresolvedIssues.map { "• \($0.detail)" }.joined(separator: "\n")
        let checks = Checkpoint.allCases.map { key -> String in
            let value = run.confirmations[key]
            let deviation = run.deviations[key].map { " [RUN DEVIATION: \($0.approvedReference) → \($0.runReference), reviewed by \($0.approvedBy)]" } ?? ""
            return "\(key.rawValue): \(value?.observed ?? "UNCONFIRMED")" + (value?.matches == false ? " [MISMATCH]" : "") + deviation
        }.joined(separator: "\n")
        let measurements = setup.dimensions.map { d -> String in
            let o = run.firstPiece.observations[d.code]
            return "\(d.code): \(o?.value ?? "NOT MEASURED") \(d.unit)" + (o?.withinTolerance == false ? " [OUT OF TOLERANCE]" : "")
        }.joined(separator: "\n")
        let last = run.handoffs.last
        let changes = run.changes.map { "• \($0.kind): \($0.detail)" }.joined(separator: "\n")
        return """
        CNC repeat job handoff — factual operator record
        Job: \(run.job) | Part: \(run.part) | Drawing: \(run.drawing)
        Machine: \(run.machine) | Setup revision: \(run.setupRevision) | Setup status: \(setup.status.rawValue)
        State: \(run.status.rawValue) | First-piece decision: \(run.firstPiece.decision?.rawValue ?? "PENDING")
        Reviewer: \(run.firstPiece.reviewer ?? "NONE") | Remaining good: \(run.remainingGood)
        Good: \(run.count(.good)) | Scrap: \(run.count(.scrap)) | Quarantine: \(run.count(.quarantine))
        Preparation:
        \(checks)
        First piece:
        \(measurements)
        Open issues:
        \(issues.isEmpty ? "None recorded" : issues)
        Recorded changes:
        \(changes.isEmpty ? "None recorded" : changes)
        Proposed setup draft: \(run.proposedSetupID?.uuidString ?? "None")
        In-process inspection: \(run.pendingInspection.map { "DUE \($0.trigger) at good \($0.dueGood); \($0.observations.count)/\(setup.dimensions.count) measured" } ?? "No inspection due")
        Next scheduled good count: \(run.nextInspectionGood.map { String($0) } ?? "None configured")
        Inspections: \((run.inspections ?? []).filter { $0.decision == .accept }.count) accepted, \((run.inspections ?? []).filter { $0.decision == .reject }.count) rejected
        Latest handoff: \(last.map { "\($0.by) → \($0.to); acknowledged by \($0.acknowledgedBy ?? "NO ONE"); \($0.note)" } ?? "None")
        This record does not certify inspection, regulatory compliance or machine safety.
        """
    }

    /// Spreadsheet formula injection is neutralized before RFC 4180 CSV quoting.
    public static func runsCSV(_ state: BenchState) -> String {
        let header = ["run_id", "job", "part", "drawing", "machine", "setup_revision", "setup_status", "run_status", "target_good", "good", "scrap", "quarantine", "open_issues", "first_piece_decision", "reviewer", "started_utc", "closed_utc", "inspection_due", "next_inspection_good", "accepted_inspections"]
        let rows: [[String]] = state.runs.values.sorted { $0.job < $1.job }.map { run in
            let setup = state.setups[run.setupID]
            return [run.id.uuidString, run.job, run.part, run.drawing, run.machine, run.setupRevision,
                    setup?.status.rawValue ?? "missing", run.status.rawValue, String(run.targetGood),
                    String(run.count(.good)), String(run.count(.scrap)), String(run.count(.quarantine)),
                    String(run.unresolvedIssues.count), run.firstPiece.decision?.rawValue ?? "pending",
                    run.firstPiece.reviewer ?? "", iso(run.startedAt), run.closedAt.map(iso) ?? "",
                    run.pendingInspection == nil ? "no" : "yes", run.nextInspectionGood.map { String($0) } ?? "",
                    String((run.inspections ?? []).filter { $0.decision == .accept }.count)]
        }
        return ([header] + rows).map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func csvCell(_ value: String) -> String {
        let dangerous = "=+-@\t\r\n"
        let firstNonSpace = value.drop(while: { $0.isWhitespace }).first
        let protected = firstNonSpace.map { dangerous.contains($0) } == true ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

import Foundation
import Observation
import CNCRepeatJobEngine

/// The UI owns no job rules or paid flag. Every write passes through the engine's
/// verified StoreKit adapter, which reevaluates entitlement at mutation time.
@MainActor
@Observable
final class BenchAppModel {
    private(set) var state = BenchState()
    private(set) var busy = false
    private(set) var errorMessage: String?
    var selectedRunID: UUID?
    var operatorName: String {
        didSet { UserDefaults.standard.set(operatorName, forKey: "cnc.operatorName") }
    }

    @ObservationIgnored private var repository: BenchRepository?
    @ObservationIgnored private var purchases: BenchStoreKit?
    @ObservationIgnored private var loaded = false

    init() {
        operatorName = UserDefaults.standard.string(forKey: "cnc.operatorName") ?? ""
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                       in: .userDomainMask, appropriateFor: nil, create: true)
            repository = try BenchRepository(url: support.appendingPathComponent("cnc-repeat-job.json"))
            purchases = try BenchStoreKit(
                monthlyProductID: ShellConfiguration.monetization.subscriptionProductID,
                annualProductID: ShellConfiguration.monetization.additionalSubscriptionProductID ?? ""
            )
        } catch { errorMessage = error.localizedDescription }
    }

    var activeRuns: [Run] {
        state.runs.values.filter { $0.status != .closed && $0.status != .aborted }
            .sorted { $0.startedAt > $1.startedAt }
    }
    var completedRuns: [Run] {
        state.runs.values.filter { $0.status == .closed || $0.status == .aborted }
            .sorted { ($0.closedAt ?? $0.startedAt) > ($1.closedAt ?? $1.startedAt) }
    }
    var approvedSetups: [Setup] {
        state.setups.values.filter { $0.status == .approved }
            .sorted { $0.part.localizedStandardCompare($1.part) == .orderedAscending }
    }
    var draftSetups: [Setup] { state.setups.values.filter { $0.status == .draft }.sorted { $0.createdAt > $1.createdAt } }
    var selectedRun: Run? {
        if let selectedRunID, let run = state.runs[selectedRunID] { return run }
        return activeRuns.first
    }

    func load() async {
        guard !loaded, let repository else { return }
        loaded = true
        state = await repository.snapshot()
    }

    @discardableResult func perform(_ command: BenchCommand) async -> Bool {
        guard !busy, let repository, let purchases else { return false }
        let name = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { errorMessage = "Enter the operator's name before recording work."; return false }
        busy = true
        defer { busy = false }
        do {
            state = try await purchases.apply(command, to: repository, actor: name)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dismissError() { errorMessage = nil }

    func exportCSV() throws -> URL { try temporaryFile(BenchExport.runsCSV(state).data(using: .utf8)!, name: "cnc-runs.csv") }
    func exportHandoff(runID: UUID, pdf: Bool) throws -> URL {
        guard let run = state.runs[runID], let setup = state.setups[run.setupID] else {
            throw BenchError.missing("Select a run with an approved setup.")
        }
        if pdf { return try temporaryFile(BenchPDF.handoff(run, setup: setup), name: "handoff-\(run.job).pdf") }
        return try temporaryFile(Data(BenchExport.handoff(run, setup: setup).utf8), name: "handoff-\(run.job).txt")
    }
    func exportBackup() async throws -> URL {
        guard let repository else { throw BenchError.missing("Local database is unavailable.") }
        return try temporaryFile(await repository.backup(), name: "cnc-repeat-job-backup.json")
    }
    func restoreBackup(_ data: Data) async -> Bool {
        guard !busy, let repository else { return false }
        busy = true
        defer { busy = false }
        do {
            state = try await repository.restore(data, expectedAuditCount: state.audit.count)
            selectedRunID = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func archive(_ ids: [UUID]) async -> URL? {
        guard !busy, let repository else { return nil }
        busy = true
        defer { busy = false }
        do {
            let name = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw BenchError.invalid("Enter the operator's name before archiving.") }
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                       in: .userDomainMask, appropriateFor: nil, create: true)
            let destination = support.appendingPathComponent("Archives", isDirectory: true)
                .appendingPathComponent("cnc-archive-\(UUID().uuidString).json")
            _ = try await repository.archive(ids, to: destination, actor: name,
                                              expectedAuditCount: state.audit.count)
            state = await repository.snapshot()
            return destination
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func restoreArchive(_ data: Data, receiptID: UUID) async -> Bool {
        guard !busy, let repository else { return false }
        busy = true
        defer { busy = false }
        do {
            let name = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw BenchError.invalid("Enter the operator's name before restoring.") }
            state = try await repository.restoreArchive(data, receiptID: receiptID,
                                                        actor: name, expectedAuditCount: state.audit.count)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func show(_ error: Error) { errorMessage = error.localizedDescription }

    private func temporaryFile(_ data: Data, name: String) throws -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cnc-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(safe)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
}

import XCTest
@testable import CNCRepeatJobEngine

final class BenchEngineTests: XCTestCase {
    private let expected: [Checkpoint: String] = [
        .stock: "6061-T6 25mm", .program: "P100-v4", .fixture: "F-12",
        .tools: "T1/T2", .offsets: "G54 rev3", .documents: "DRAW-C"
    ]
    private let dimensions = [Dimension(code: "D1", nominal: "25.000", minus: "0.010", plus: "0.020", unit: "mm")]
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func setup(_ engine: inout BenchEngine, revision: String = "S1") throws -> UUID {
        let id = UUID()
        try engine.apply(.draftSetup(part: "P-42", drawing: "C", machine: "M1", revision: revision,
                                     expected: expected, dimensions: dimensions, notes: "Check clamp"),
                         actor: "Lead", at: now, operationID: id)
        try engine.apply(.setDraftInspectionPolicy(setupID: id, everyGood: nil,
            reason: "Fixture default: manual inspection only"), actor: "Lead", at: now)
        try engine.apply(.approveSetup(setupID: id), actor: "Lead", at: now.addingTimeInterval(1))
        return id
    }
    private func preparedRun(_ engine: inout BenchEngine, setupID: UUID) throws -> UUID {
        let runID = UUID()
        try engine.apply(.start(job: "WO-7", part: "P-42", drawing: "C", machine: "M1", setupID: setupID, targetGood: 10),
                         actor: "Op", at: now, operationID: runID)
        for checkpoint in Checkpoint.allCases {
            try engine.apply(.confirm(runID: runID, checkpoint: checkpoint, observed: expected[checkpoint]!), actor: "Op", at: now)
        }
        XCTAssertEqual(engine.state.runs[runID]?.status, .firstPiece)
        return runID
    }
    private func running(_ engine: inout BenchEngine, setupID: UUID) throws -> UUID {
        let runID = try preparedRun(&engine, setupID: setupID)
        try engine.apply(.measure(runID: runID, code: "D1", value: "25.020"), actor: "Op", at: now)
        try engine.apply(.review(runID: runID, decision: .accept, reviewer: "QC", reason: ""), actor: "QC", at: now)
        return runID
    }

    func testRevisionAndMeasurementGates() throws {
        var engine = try BenchEngine()
        let id = try setup(&engine)
        XCTAssertThrowsError(try engine.apply(.start(job: "W", part: "P-42", drawing: "D", machine: "M1", setupID: id, targetGood: 10), actor: "Op"))
        let run = try preparedRun(&engine, setupID: id)
        try engine.apply(.measure(runID: run, code: "D1", value: "25.021"), actor: "Op")
        XCTAssertThrowsError(try engine.apply(.review(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC"))
        XCTAssertEqual(engine.state.runs[run]?.status, .firstPiece)
        try engine.apply(.repeatMeasurement(runID: run, code: "D1", value: "24.990", reason: "new first piece"), actor: "Op")
        try engine.apply(.review(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.status, .running)
    }
    func testMismatchAndRejectionRecovery() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = UUID()
        try engine.apply(.start(job: "WO-7", part: "P-42", drawing: "C", machine: "M1", setupID: id, targetGood: 10), actor: "Op", operationID: run)
        try engine.apply(.confirm(runID: run, checkpoint: .stock, observed: "wrong"), actor: "Op")
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        let issue = try XCTUnwrap(engine.state.runs[run]?.unresolvedIssues.first?.id)
        try engine.apply(.confirm(runID: run, checkpoint: .stock, observed: expected[.stock]!), actor: "Op")
        try engine.apply(.resolve(runID: run, issueID: issue, resolution: "Correct stock verified"), actor: "Lead")
        for key in Checkpoint.allCases where key != .stock {
            try engine.apply(.confirm(runID: run, checkpoint: key, observed: expected[key]!), actor: "Op")
        }
        try engine.apply(.measure(runID: run, code: "D1", value: "25.000"), actor: "Op")
        try engine.apply(.review(runID: run, decision: .reject, reviewer: "QC", reason: "surface"), actor: "QC")
        let rejection = try XCTUnwrap(engine.state.runs[run]?.unresolvedIssues.first?.id)
        try engine.apply(.resolve(runID: run, issueID: rejection, resolution: "Adjusted process and cut new first piece"), actor: "Lead")
        XCTAssertNil(engine.state.runs[run]?.firstPiece.decision)
        XCTAssertEqual(engine.state.runs[run]?.firstPieceHistory.count, 1)
        try engine.apply(.measure(runID: run, code: "D1", value: "25.000"), actor: "Op")
        try engine.apply(.review(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.status, .running)
    }
    func testSupersessionHoldsOldRunAndLeavesDraftUnapproved() throws {
        var engine = try BenchEngine(); let first = try setup(&engine)
        let run = try running(&engine, setupID: first)
        let draft = UUID()
        try engine.apply(.draftSetup(part: "P-42", drawing: "C", machine: "M1", revision: "S2", expected: expected,
                                     dimensions: dimensions, notes: "Updated"), actor: "Lead", operationID: draft)
        XCTAssertEqual(engine.state.runs[run]?.status, .running)
        try engine.apply(.setDraftInspectionPolicy(setupID: draft, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: draft), actor: "Lead")
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        XCTAssertEqual(engine.state.setups[first]?.status, .superseded)
        let heldIssue = try XCTUnwrap(engine.state.runs[run]?.unresolvedIssues.first?.id)
        XCTAssertThrowsError(try engine.apply(.resolve(runID: run, issueID: heldIssue, resolution: "ignore"), actor: "Lead"))
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        XCTAssertThrowsError(try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 1, reason: "cut"), actor: "Op"))
    }
    func testCountsCorrectionHandoffChangeAndIdempotency() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try running(&engine, setupID: id)
        let entry = UUID()
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 3, reason: "shift 1"), actor: "Op", operationID: entry)
        let before = engine.state.audit.count
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 3, reason: "shift 1"), actor: "Op", operationID: entry)
        XCTAssertEqual(engine.state.audit.count, before)
        try engine.apply(.correctCount(runID: run, entryID: entry, replacementQuantity: 2, reason: "double counted"), actor: "Op")
        XCTAssertEqual(engine.state.runs[run]?.count(.good), 2)
        XCTAssertThrowsError(try engine.apply(.correctCount(runID: run, entryID: entry, replacementQuantity: 1, reason: "again"), actor: "Op"))
        try engine.apply(.handoff(runID: run, to: "Next", note: "Check T2"), actor: "Op")
        XCTAssertEqual(engine.state.runs[run]?.handoffs.last?.remainingGood, 8)
        XCTAssertThrowsError(try engine.apply(.resume(runID: run), actor: "Op"))
        try engine.apply(.acknowledgeHandoff(runID: run), actor: "Next")
        try engine.apply(.resume(runID: run), actor: "Next")
        try engine.apply(.change(runID: run, kind: "offsets", detail: "G54 rev4"), actor: "Next")
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        XCTAssertEqual(engine.state.runs[run]?.firstPieceHistory.count, 1)
        XCTAssertThrowsError(try engine.apply(.close(runID: run, reason: "done"), actor: "Next"))
        let change = try XCTUnwrap(engine.state.runs[run]?.changes.last)
        XCTAssertThrowsError(try engine.apply(.resolve(runID: run, issueID: change.id, resolution: "done"), actor: "Lead"))
        try engine.apply(.authorizeDeviation(runID: run, changeID: change.id, checkpoint: .offsets,
                                             observed: "G54 rev4", reviewer: "Lead", reason: "Verified new offset"), actor: "Lead")
        for key in Checkpoint.allCases {
            let observed = key == .offsets ? "G54 rev4" : expected[key]!
            try engine.apply(.confirm(runID: run, checkpoint: key, observed: observed), actor: "Next")
        }
        try engine.apply(.measure(runID: run, code: "D1", value: "25.000"), actor: "Next")
        try engine.apply(.review(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.status, .running)
        XCTAssertEqual(engine.state.setups[id]?.expected[.offsets], "G54 rev3")
    }
    func testBackupRestoreAndTamperRejection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BenchRepository(url: directory.appendingPathComponent("db.json"))
        let backup = try await store.backup()
        let id = UUID()
        try await store.apply(.draftSetup(part: "P-42", drawing: "C", machine: "M1", revision: "S1",
                                         expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: id)
        do { _ = try await store.restore(backup, expectedAuditCount: 0); XCTFail("Stale restore should fail") } catch BenchError.conflict { }
        let current = try await store.backup()
        let reopened = try BenchRepository(url: directory.appendingPathComponent("db.json"))
        let snapshot = await reopened.snapshot()
        XCTAssertNotNil(snapshot.setups[id])
        let damaged = Data(String(decoding: current, as: UTF8.self).replacingOccurrences(of: "\"schema\":1", with: "\"schema\":99").utf8)
        do { _ = try await reopened.restore(damaged, expectedAuditCount: snapshot.audit.count); XCTFail("Unsupported schema should fail") } catch BenchError.unsupportedSchema(99) { }
        let after = await reopened.snapshot()
        XCTAssertEqual(after.setups.count, 1)
    }
    func testAbortPreservesHeldRunAndAllowsNewJobRun() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let old = try preparedRun(&engine, setupID: id)
        try engine.apply(.issue(runID: old, detail: "Drawing note unclear"), actor: "Op")
        XCTAssertThrowsError(try engine.apply(.close(runID: old, reason: "cannot continue"), actor: "Lead"))
        try engine.apply(.abort(runID: old, reason: "Awaiting drawing clarification"), actor: "Lead")
        XCTAssertEqual(engine.state.runs[old]?.status, .aborted)
        let replacement = UUID()
        try engine.apply(.start(job: "WO-7", part: "P-42", drawing: "C", machine: "M1", setupID: id, targetGood: 10), actor: "Op", operationID: replacement)
        XCTAssertEqual(engine.state.runs[replacement]?.status, .preparing)
    }
    func testDraftProposalNeedsSeparateApproval() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try running(&engine, setupID: id)
        let draft = UUID()
        try engine.apply(.proposeSetup(runID: run, revision: "S2", expected: expected, dimensions: dimensions, notes: "Proposed T2"), actor: "Op", operationID: draft)
        XCTAssertEqual(engine.state.setups[draft]?.status, .draft)
        XCTAssertEqual(engine.state.setups[id]?.status, .approved)
        try engine.apply(.reviseDraft(setupID: draft, expected: expected, dimensions: dimensions, notes: "Reviewed T2"), actor: "Lead")
        XCTAssertEqual(engine.state.setups[draft]?.notes, "Reviewed T2")
        try engine.apply(.setDraftInspectionPolicy(setupID: draft, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: draft), actor: "Lead")
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
    }
    func testClosedCountCorrectionAndQuarantineGate() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try running(&engine, setupID: id)
        let good = UUID()
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 10, reason: "complete"), actor: "Op", operationID: good)
        let held = UUID()
        try engine.apply(.recordCount(runID: run, disposition: .quarantine, quantity: 1, reason: "inspect"), actor: "Op", operationID: held)
        XCTAssertThrowsError(try engine.apply(.close(runID: run, reason: "complete"), actor: "Lead"))
        try engine.apply(.correctCount(runID: run, entryID: held, replacementQuantity: 0, reason: "released after inspection"), actor: "QC")
        try engine.apply(.close(runID: run, reason: "ten accepted"), actor: "Lead")
        try engine.apply(.correctCount(runID: run, entryID: good, replacementQuantity: 9, reason: "one double count"), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.count(.good), 9)
        XCTAssertEqual(engine.state.runs[run]?.status, .closed)
    }
    func testAttachmentLimits() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try preparedRun(&engine, setupID: id)
        XCTAssertThrowsError(try engine.apply(.attach(runID: run, filename: "fake.pdf", mimeType: "application/pdf", bytes: Data("fake".utf8)), actor: "Op"))
        try engine.apply(.attach(runID: run, filename: "setup.jpg", mimeType: "image/jpeg", bytes: Data([0xFF, 0xD8, 0xFF, 0x00])), actor: "Op")
        XCTAssertEqual(engine.state.runs[run]?.attachments.count, 1)
    }
    func testLocaleMatrix() throws {
        var engine = try BenchEngine()
        try engine.apply(.setLocale("en-CA"), actor: "Op")
        XCTAssertEqual(engine.state.locale, "en-CA")
        XCTAssertThrowsError(try engine.apply(.setLocale("fr-CA"), actor: "Op"))
        XCTAssertEqual(engine.state.locale, "en-CA")
    }
    private func approveFamily(_ part: String, machine: String, engine: inout BenchEngine,
                               access: BenchAccess = .free, at: Date) throws -> UUID {
        let id = UUID()
        try engine.apply(.draftSetup(part: part, drawing: "A", machine: machine, revision: "S1",
                                     expected: expected, dimensions: dimensions, notes: ""),
                         actor: "Lead", at: at, operationID: id)
        try engine.apply(.setDraftInspectionPolicy(setupID: id, everyGood: nil, reason: "Manual inspection"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: id), actor: "Lead", at: at.addingTimeInterval(1), access: access)
        return id
    }

    func testTwoFreeFamiliesProExpiryAndOpenRun() throws {
        var engine = try BenchEngine()
        let first = try approveFamily("A", machine: "M1", engine: &engine, at: now)
        _ = try approveFamily("B", machine: "M1", engine: &engine, at: now.addingTimeInterval(10))
        let third = UUID()
        try engine.apply(.draftSetup(part: "C", drawing: "A", machine: "M1", revision: "S1",
                                     expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: third)
        try engine.apply(.setDraftInspectionPolicy(setupID: third, everyGood: nil, reason: "Manual"), actor: "Lead")
        let before = engine.state
        XCTAssertThrowsError(try engine.apply(.approveSetup(setupID: third), actor: "Lead"))
        XCTAssertEqual(engine.state, before)
        try engine.apply(.approveSetup(setupID: third), actor: "Lead", at: now.addingTimeInterval(21), access: .pro)
        let active = UUID()
        try engine.apply(.start(job: "Paid job", part: "C", drawing: "A", machine: "M1", setupID: third, targetGood: 1),
                         actor: "Op", operationID: active, access: .pro)
        XCTAssertThrowsError(try engine.apply(.start(job: "New paid job", part: "C", drawing: "A", machine: "M1", setupID: third, targetGood: 1), actor: "Op"))
        XCTAssertEqual(engine.state.runs[active]?.status, .preparing)
        // Expiry cannot interrupt preparation, quality review or an open run.
        for checkpoint in Checkpoint.allCases {
            try engine.apply(.confirm(runID: active, checkpoint: checkpoint, observed: expected[checkpoint]!), actor: "Op")
        }
        try engine.apply(.measure(runID: active, code: "D1", value: "25.000"), actor: "Op")
        try engine.apply(.review(runID: active, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        try engine.apply(.recordCount(runID: active, disposition: .good, quantity: 1, reason: "Complete"), actor: "Op")
        try engine.apply(.close(runID: active, reason: "Complete"), actor: "Lead")
        XCTAssertEqual(engine.state.runs[active]?.status, .closed)
        let paidRevision = UUID()
        try engine.apply(.draftSetup(part: "C", drawing: "A", machine: "M1", revision: "S2",
                                     expected: expected, dimensions: dimensions, notes: "Safety correction"), actor: "Lead", operationID: paidRevision)
        try engine.apply(.setDraftInspectionPolicy(setupID: paidRevision, everyGood: nil, reason: "Manual"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: paidRevision), actor: "Lead")
        XCTAssertThrowsError(try engine.apply(.start(job: "Another paid job", part: "C", drawing: "A", machine: "M1", setupID: paidRevision, targetGood: 1), actor: "Op"))
        try engine.apply(.start(job: "Free repeat", part: "A", drawing: "A", machine: "M1", setupID: first, targetGood: 1), actor: "Op")
        XCTAssertFalse(BenchExport.runsCSV(engine.state).isEmpty)
    }

    func testSameFamilyRevisionDoesNotConsumeAnotherFreeSlot() throws {
        var engine = try BenchEngine()
        _ = try approveFamily("A", machine: "M1", engine: &engine, at: now)
        let revised = UUID()
        try engine.apply(.draftSetup(part: "A", drawing: "A", machine: "M1", revision: "S2",
                                     expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: revised)
        try engine.apply(.setDraftInspectionPolicy(setupID: revised, everyGood: nil, reason: "Manual"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: revised), actor: "Lead")
        XCTAssertEqual(engine.state.freeFamilies, [SetupFamily(part: "A", machine: "M1")])
        _ = try approveFamily("B", machine: "M1", engine: &engine, at: now.addingTimeInterval(30))
        XCTAssertEqual(engine.state.freeFamilies.count, 2)
    }

    func testLegacyBackupPaidFlagCannotGrantAccess() throws {
        var state = BenchState()
        let old = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json["entitlement"] = "full" // A field in pre-paywall backups.
        state = try JSONDecoder().decode(BenchState.self, from: JSONSerialization.data(withJSONObject: json))
        var engine = try BenchEngine(state: state)
        _ = try approveFamily("A", machine: "M1", engine: &engine, at: now)
        _ = try approveFamily("B", machine: "M1", engine: &engine, at: now.addingTimeInterval(10))
        XCTAssertThrowsError(try approveFamily("C", machine: "M1", engine: &engine, at: now.addingTimeInterval(20)))
    }
    #if canImport(UIKit)
    func testIOSPDFRender() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let runID = try preparedRun(&engine, setupID: id)
        let run = try XCTUnwrap(engine.state.runs[runID])
        let data = BenchPDF.handoff(run, setup: try XCTUnwrap(engine.state.setups[id]))
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }
    #endif
    func testExactCaseSetupIdentity() throws {
        var engine = try BenchEngine()
        let upper = UUID(), lower = UUID()
        try engine.apply(.draftSetup(part: "P", drawing: "C", machine: "M1", revision: "S1", expected: expected,
                                     dimensions: dimensions, notes: ""), actor: "Lead", operationID: upper)
        try engine.apply(.setDraftInspectionPolicy(setupID: upper, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: upper), actor: "Lead")
        try engine.apply(.draftSetup(part: "p", drawing: "C", machine: "M1", revision: "S1", expected: expected,
                                     dimensions: dimensions, notes: ""), actor: "Lead", operationID: lower)
        try engine.apply(.setDraftInspectionPolicy(setupID: lower, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: lower), actor: "Lead")
        XCTAssertEqual(engine.state.setups[upper]?.status, .approved)
        XCTAssertEqual(engine.state.setups[lower]?.status, .approved)
        XCTAssertThrowsError(try engine.apply(.draftSetup(part: "P\u{0}X", drawing: "D", machine: "M1", revision: "S2",
                                                      expected: expected, dimensions: dimensions, notes: ""), actor: "Lead"))
    }
    func testAcceptedFirstPieceCannotBeOverwrittenWhileHeld() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try running(&engine, setupID: id)
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 2, reason: "before hold"), actor: "Op")
        try engine.apply(.issue(runID: run, detail: "inspect fixture"), actor: "Op")
        XCTAssertThrowsError(try engine.apply(.review(runID: run, decision: .reject, reviewer: "Other", reason: "later"), actor: "Other"))
        XCTAssertEqual(engine.state.runs[run]?.firstPiece.decision, .accept)
        XCTAssertEqual(engine.state.runs[run]?.firstPiece.reviewer, "QC")
        XCTAssertEqual(engine.state.runs[run]?.count(.good), 2)
    }
    func testSecondRepositoryConflictsInsteadOfOverwriting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = try BenchRepository(url: url), second = try BenchRepository(url: url)
        let a = UUID(), b = UUID()
        try await first.apply(.draftSetup(part: "A", drawing: "C", machine: "M1", revision: "S1", expected: expected,
                                         dimensions: dimensions, notes: ""), actor: "Lead", operationID: a)
        do {
            _ = try await second.apply(.draftSetup(part: "B", drawing: "C", machine: "M1", revision: "S1", expected: expected,
                                                   dimensions: dimensions, notes: ""), actor: "Lead", operationID: b)
            XCTFail("Second stale repository overwrote the first")
        } catch BenchError.conflict { }
        let refreshed = try await second.refresh()
        XCTAssertNotNil(refreshed.setups[a])
        try await second.apply(.draftSetup(part: "B", drawing: "C", machine: "M1", revision: "S1", expected: expected,
                                         dimensions: dimensions, notes: ""), actor: "Lead", operationID: b)
        let reopened = try BenchRepository(url: url)
        let saved = await reopened.snapshot()
        XCTAssertNotNil(saved.setups[a]); XCTAssertNotNil(saved.setups[b])
    }
    func testUnacknowledgedHandoffBlocksEveryWorkStage() throws {
        var engine = try BenchEngine(); let setupID = try setup(&engine)
        let run = try preparedRun(&engine, setupID: setupID)
        try engine.apply(.handoff(runID: run, to: "Lee", note: "Inspect first piece"), actor: "Op")
        XCTAssertThrowsError(try engine.apply(.measure(runID: run, code: "D1", value: "25.000"), actor: "Op"))
        XCTAssertThrowsError(try engine.apply(.change(runID: run, kind: "offsets", detail: "G54 rev4"), actor: "Op"))
        XCTAssertThrowsError(try engine.apply(.acknowledgeHandoff(runID: run), actor: "Other"))
        XCTAssertThrowsError(try engine.apply(.handoff(runID: run, to: "Op", note: "shortcut"), actor: "Op"))
        try engine.apply(.reassignHandoff(runID: run, to: "New", reason: "Lee unavailable"), actor: "Lead")
        XCTAssertThrowsError(try engine.apply(.acknowledgeHandoff(runID: run), actor: "Lee"))
        try engine.apply(.acknowledgeHandoff(runID: run), actor: "New")
        try engine.apply(.measure(runID: run, code: "D1", value: "25.000"), actor: "New")
        try engine.apply(.review(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.status, .running)
    }
    func testDrawingReplacementRequiresExplicitDecision() throws {
        var engine = try BenchEngine(); let old = try setup(&engine)
        let run = try running(&engine, setupID: old)
        let next = UUID()
        try engine.apply(.draftSetup(part: "P-42", drawing: "D", machine: "M1", revision: "S1",
                                     expected: expected, dimensions: dimensions, notes: "New drawing"), actor: "Lead", operationID: next)
        XCTAssertThrowsError(try engine.apply(.approveSetup(setupID: next), actor: "Lead"))
        XCTAssertEqual(engine.state.setups[old]?.status, .approved)
        try engine.apply(.setDraftInspectionPolicy(setupID: next, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try engine.apply(.replaceDrawing(setupID: next, previousDrawing: "C", reason: "Engineering release D"), actor: "Lead")
        XCTAssertEqual(engine.state.setups[old]?.status, .superseded)
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        XCTAssertThrowsError(try engine.apply(.start(job: "old order", part: "P-42", drawing: "C", machine: "M1", setupID: old, targetGood: 1), actor: "Op"))
        let other = UUID()
        try engine.apply(.draftSetup(part: "P-42", drawing: "E", machine: "M1", revision: "S1",
                                     expected: expected, dimensions: dimensions, notes: "Parallel contract"), actor: "Lead", operationID: other)
        try engine.apply(.setDraftInspectionPolicy(setupID: other, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try engine.apply(.approveCoexistingDrawing(setupID: other, reason: "Two customer orders intentionally active"), actor: "Lead")
        XCTAssertEqual(engine.state.setups[next]?.status, .approved)
        XCTAssertEqual(engine.state.setups[other]?.status, .approved)
    }
    func testArchiveRoundTripAndCorruptArchiveRejection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BenchRepository(url: directory.appendingPathComponent("state.json"))
        let setupID = UUID(), runID = UUID()
        try await store.apply(.draftSetup(part: "P", drawing: "A", machine: "M", revision: "1",
                                          expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: setupID)
        try await store.apply(.setDraftInspectionPolicy(setupID: setupID, everyGood: nil, reason: "Manual only"), actor: "Lead")
        try await store.apply(.approveSetup(setupID: setupID), actor: "Lead")
        try await store.apply(.start(job: "J", part: "P", drawing: "A", machine: "M", setupID: setupID,
                                     targetGood: 1), actor: "Op", operationID: runID)
        for key in Checkpoint.allCases {
            try await store.apply(.confirm(runID: runID, checkpoint: key, observed: expected[key]!), actor: "Op")
        }
        try await store.apply(.measure(runID: runID, code: "D1", value: "25.000"), actor: "Op")
        try await store.apply(.review(runID: runID, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        try await store.apply(.recordCount(runID: runID, disposition: .good, quantity: 1, reason: "done"), actor: "Op")
        try await store.apply(.close(runID: runID, reason: "complete"), actor: "Lead")
        let before = await store.snapshot()
        let path = directory.appendingPathComponent("closed.json")
        let receipt = try await store.archive([runID], to: path, actor: "Lead", expectedAuditCount: before.audit.count)
        let archived = await store.snapshot()
        XCTAssertNil(archived.runs[runID]); XCTAssertNotNil(archived.setups[setupID])
        XCTAssertEqual(archived.archiveReceipts.count, 1)
        XCTAssertTrue(archived.archivedOperationIDs.contains(runID))
        let beforeRetry = archived.audit.count
        try await store.apply(.setLocale("en-CA"), actor: "Op", operationID: runID)
        let afterRetry = await store.snapshot()
        XCTAssertEqual(afterRetry.audit.count, beforeRetry)
        XCTAssertEqual(afterRetry.locale, "en-US")
        let bytes = try Data(contentsOf: path)
        var bad = bytes; bad.append(0)
        do { _ = try await store.restoreArchive(bad, receiptID: receipt.id, actor: "Lead", expectedAuditCount: archived.audit.count); XCTFail("Altered archive accepted") } catch { }
        let stillArchived = await store.snapshot()
        XCTAssertNil(stillArchived.runs[runID])
        try await store.restoreArchive(bytes, receiptID: receipt.id, actor: "Lead", expectedAuditCount: archived.audit.count)
        let restored = await store.snapshot()
        XCTAssertEqual(restored.runs[runID]?.count(.good), 1)
        XCTAssertEqual(restored.runs[runID]?.status, .closed)
        XCTAssertFalse(restored.archivedOperationIDs.contains(runID))
    }
    func testBackupRejectsUndocumentedHandoffRedirection() throws {
        var engine = try BenchEngine(); let setupID = try setup(&engine)
        let runID = try preparedRun(&engine, setupID: setupID)
        try engine.apply(.handoff(runID: runID, to: "Lee", note: "next shift"), actor: "Op")
        var forged = engine.state
        forged.runs[runID]!.handoffs.append(Handoff(id: UUID(), to: "Op", by: "Op", at: now,
            status: .firstPiece, remainingGood: 10, unresolvedIssueIDs: [], note: "redirected",
            acknowledgedBy: "Op", acknowledgedAt: now))
        XCTAssertThrowsError(try BenchEngine(state: forged))
    }
    func testBackupRejectsImpossibleCorrectionAndWhitespaceReference() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let runID = try running(&engine, setupID: id)
        try engine.apply(.recordCount(runID: runID, disposition: .good, quantity: 10, reason: "ten"), actor: "Op")
        var tampered = engine.state
        tampered.runs[runID]!.counts.append(CountEntry(id: UUID(), disposition: .good, delta: -9,
                                                      reason: "forged", actor: "Op", at: now, corrects: nil))
        XCTAssertThrowsError(try BenchEngine(state: tampered))
        var spaced = engine.state
        spaced.setups[id]!.expected[.stock] = " 6061-T6 25mm "
        XCTAssertThrowsError(try BenchEngine(state: spaced))
        var input = expected; input[.stock] = " 6061-T6 25mm "
        let new = UUID()
        try engine.apply(.draftSetup(part: "Other", drawing: "A", machine: "M2", revision: "1",
                                     expected: input, dimensions: dimensions, notes: ""), actor: "Lead", operationID: new)
        XCTAssertEqual(engine.state.setups[new]?.expected[.stock], expected[.stock])
    }
    func testArchiveOutputCannotOverwriteAnotherArchive() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("export.json")
        let first = try BenchRepository(url: dir.appendingPathComponent("one.json"))
        let second = try BenchRepository(url: dir.appendingPathComponent("two.json"))
        for (store, part) in [(first, "A"), (second, "B")] {
            let setupID = UUID(), runID = UUID()
            try await store.apply(.draftSetup(part: part, drawing: "1", machine: "M", revision: "1",
                                              expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: setupID)
            try await store.apply(.setDraftInspectionPolicy(setupID: setupID, everyGood: nil, reason: "Manual only"), actor: "Lead")
            try await store.apply(.approveSetup(setupID: setupID), actor: "Lead")
            try await store.apply(.start(job: "J", part: part, drawing: "1", machine: "M",
                                         setupID: setupID, targetGood: 1), actor: "Op", operationID: runID)
            try await store.apply(.abort(runID: runID, reason: "test"), actor: "Lead")
            let before = await store.snapshot()
            if part == "A" {
                try await store.archive([runID], to: output, actor: "Lead", expectedAuditCount: before.audit.count)
            } else {
                do { _ = try await store.archive([runID], to: output, actor: "Lead", expectedAuditCount: before.audit.count)
                     XCTFail("Existing archive overwritten") } catch BenchError.conflict { }
                let after = await store.snapshot()
                XCTAssertNotNil(after.runs[runID])
            }
        }
    }
    func testAcceleratedThousandYearLifecycle() throws {
        var engine = try BenchEngine(); let setupID = try setup(&engine)
        let secondsPerYear = 365.2425 * 86_400.0
        for year in stride(from: 0, through: 1_000, by: 10) {
            let time = now.addingTimeInterval(Double(year) * secondsPerYear)
            let id = UUID()
            try engine.apply(.start(job: "Repeat-\(year)", part: "P-42", drawing: "C", machine: "M1",
                                    setupID: setupID, targetGood: 1), actor: "Op", at: time, operationID: id)
            for key in Checkpoint.allCases {
                try engine.apply(.confirm(runID: id, checkpoint: key, observed: expected[key]!), actor: "Op", at: time)
            }
            try engine.apply(.measure(runID: id, code: "D1", value: "25.000"), actor: "Op", at: time)
            try engine.apply(.review(runID: id, decision: .accept, reviewer: "QC", reason: ""), actor: "QC", at: time)
            try engine.apply(.recordCount(runID: id, disposition: .good, quantity: 1, reason: "complete"), actor: "Op", at: time)
            try engine.apply(.close(runID: id, reason: "one accepted"), actor: "Lead", at: time)
            XCTAssertEqual(engine.state.runs[id]?.status, .closed)
        }
        try BenchEngine.validate(engine.state)
        XCTAssertEqual(engine.state.runs.count, 101)
    }
    func testGeneratedCountSequences10000() throws {
        var fixture = try BenchEngine(); let setupID = try setup(&fixture)
        let runID = try running(&fixture, setupID: setupID)
        for seed in 0..<10_000 {
            var candidate = fixture
            let quantity = (seed * 7 % 13)
            let originalID = UUID()
            do {
                try candidate.apply(.recordCount(runID: runID, disposition: .good, quantity: quantity, reason: "generated"),
                                    actor: "Test", operationID: originalID)
                XCTAssertTrue((1...10).contains(quantity))
                let replacement = (seed * 11 % 13)
                do {
                    try candidate.apply(.correctCount(runID: runID, entryID: originalID, replacementQuantity: replacement, reason: "generated"), actor: "Test")
                    XCTAssertLessThanOrEqual(replacement, 10)
                } catch { XCTAssertGreaterThan(replacement, 10) }
            } catch { XCTAssertFalse((1...10).contains(quantity)) }
            try BenchEngine.validate(candidate.state)
            XCTAssertLessThanOrEqual(candidate.state.runs[runID]!.count(.good), 10)
        }
    }
    func testScheduledInspectionStopsAtBoundaryAndRequiresReview() throws {
        var engine = try BenchEngine()
        let id = UUID()
        try engine.apply(.draftSetup(part: "P-42", drawing: "C", machine: "M1", revision: "S1",
                                     expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: id)
        XCTAssertThrowsError(try engine.apply(.approveSetup(setupID: id), actor: "Lead"))
        try engine.apply(.setDraftInspectionPolicy(setupID: id, everyGood: 5, reason: "Check bore drift every five good"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: id), actor: "Lead")
        let run = try running(&engine, setupID: id)
        XCTAssertThrowsError(try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 6, reason: "overshoot"), actor: "Op"))
        XCTAssertEqual(engine.state.runs[run]?.count(.good), 0)
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 5, reason: "at threshold"), actor: "Op")
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        XCTAssertEqual(engine.state.runs[run]?.pendingInspection?.trigger, "scheduled")
        XCTAssertThrowsError(try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 1, reason: "bypass"), actor: "Op"))
        XCTAssertThrowsError(try engine.apply(.close(runID: run, reason: "bypass"), actor: "Lead"))
        try engine.apply(.measureInspection(runID: run, code: "D1", value: "25.010", repeatReason: nil), actor: "Op")
        try engine.apply(.reviewInspection(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.status, .paused)
        XCTAssertEqual(engine.state.runs[run]?.nextInspectionGood, 10)
        XCTAssertEqual(engine.state.runs[run]?.inspections?.count, 1)
        try engine.apply(.resume(runID: run), actor: "Op")
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 5, reason: "second interval"), actor: "Op")
        XCTAssertEqual(engine.state.runs[run]?.pendingInspection?.dueGood, 10)
    }
    func testManualInspectionRejectionCannotBeClearedWithoutNewPass() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try running(&engine, setupID: id)
        try engine.apply(.requestInspection(runID: run, reason: "Tool wear suspected"), actor: "Op")
        try engine.apply(.measureInspection(runID: run, code: "D1", value: "25.030", repeatReason: nil), actor: "Op")
        XCTAssertThrowsError(try engine.apply(.reviewInspection(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC"))
        try engine.apply(.reviewInspection(runID: run, decision: .reject, reviewer: "QC", reason: "bore high"), actor: "QC")
        let issue = try XCTUnwrap(engine.state.runs[run]?.unresolvedIssues.first?.id)
        XCTAssertThrowsError(try engine.apply(.measureInspection(runID: run, code: "D1", value: "25.000", repeatReason: "corrected"), actor: "Op"))
        try engine.apply(.resolve(runID: run, issueID: issue, resolution: "Insert replaced"), actor: "Lead")
        XCTAssertEqual(engine.state.runs[run]?.status, .held)
        XCTAssertEqual(engine.state.runs[run]?.inspections?.first?.decision, .reject)
        try engine.apply(.measureInspection(runID: run, code: "D1", value: "25.000", repeatReason: nil), actor: "Op")
        try engine.apply(.reviewInspection(runID: run, decision: .accept, reviewer: "QC", reason: ""), actor: "QC")
        XCTAssertEqual(engine.state.runs[run]?.status, .paused)
        XCTAssertEqual(engine.state.runs[run]?.inspections?.count, 2)
    }
    func testCountCorrectionCannotSkipInspectionBoundary() throws {
        var engine = try BenchEngine(); let id = UUID()
        try engine.apply(.draftSetup(part: "P-42", drawing: "C", machine: "M1", revision: "S1",
                                     expected: expected, dimensions: dimensions, notes: ""), actor: "Lead", operationID: id)
        try engine.apply(.setDraftInspectionPolicy(setupID: id, everyGood: 5, reason: "Five good"), actor: "Lead")
        try engine.apply(.approveSetup(setupID: id), actor: "Lead")
        let run = try running(&engine, setupID: id), original = UUID()
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 4, reason: "initial"),
                         actor: "Op", operationID: original)
        XCTAssertThrowsError(try engine.apply(.correctCount(runID: run, entryID: original,
            replacementQuantity: 6, reason: "correction"), actor: "Op"))
        XCTAssertEqual(engine.state.runs[run]?.count(.good), 4)
        try engine.apply(.recordCount(runID: run, disposition: .good, quantity: 1, reason: "boundary"), actor: "Op")
        XCTAssertThrowsError(try engine.apply(.correctCount(runID: run, entryID: original,
            replacementQuantity: 3, reason: "while due"), actor: "Op"))
        XCTAssertEqual(engine.state.runs[run]?.pendingInspection?.dueGood, 5)
    }
    func testLegacyStateWithoutInspectionFieldsDecodesWithoutInventingPolicy() throws {
        var engine = try BenchEngine(); let id = try setup(&engine)
        let run = try running(&engine, setupID: id)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(engine.state)) as? [String: Any])
        json.removeValue(forKey: "inspectionPolicies")
        var runs = try XCTUnwrap(json["runs"] as? [String: [String: Any]])
        for key in runs.keys {
            var entry = try XCTUnwrap(runs[key])
            entry.removeValue(forKey: "inspections")
            entry.removeValue(forKey: "pendingInspection")
            entry.removeValue(forKey: "nextInspectionGood")
            runs[key] = entry
        }
        json["runs"] = runs
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(BenchState.self, from: JSONSerialization.data(withJSONObject: json))
        try BenchEngine.validate(restored)
        XCTAssertNil(restored.inspectionPolicies[id])
        XCTAssertNil(restored.runs[run]?.nextInspectionGood)
    }
    func testCSVFormulaGuardAndExactDecimal() throws {
        XCTAssertEqual(try BenchEngine.decimal("25.020"), try BenchEngine.decimal("25.02"))
        XCTAssertThrowsError(try BenchEngine.decimal("NaN"))
        var engine = try BenchEngine(); let id = try setup(&engine)
        try engine.apply(.start(job: "=CMD()", part: "P-42", drawing: "C", machine: "M1", setupID: id, targetGood: 1), actor: "Op")
        XCTAssertTrue(BenchExport.runsCSV(engine.state).contains("\"'=CMD()\""))
    }
}

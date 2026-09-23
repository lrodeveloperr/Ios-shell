import Foundation
import CryptoKit
import Darwin

public struct ArchiveBundle: Codable, Sendable {
    public var schema: Int
    public var createdAt: Date
    public var runs: [Run]
    public var setups: [Setup]
    public var audit: [Audit]
}

/// One local-device database. A sidecar file lock and on-disk fingerprint
/// prevent separate repository instances from silently overwriting each other.
public actor BenchRepository {
    private let url: URL
    private var engine: BenchEngine
    private var baseline: [UInt8]?

    public init(url: URL) throws {
        self.url = url
        let loaded = try Self.withFileLock(url) { try Self.load(url) }
        self.engine = loaded.0
        self.baseline = loaded.1
    }
    public func snapshot() -> BenchState { engine.state }

    /// Reload after a conflict, then re-evaluate the attempted command against current data.
    public func refresh() throws -> BenchState {
        let loaded = try Self.withFileLock(url) { try Self.load(url) }
        engine = loaded.0; baseline = loaded.1
        return engine.state
    }
    @discardableResult public func apply(_ command: BenchCommand, actor: String,
                                         at: Date = Date(), operationID: UUID = UUID(),
                                         access: BenchAccess = .free) throws -> BenchState {
        var candidate = engine
        let result = try candidate.apply(command, actor: actor, at: at, operationID: operationID, access: access)
        if result == engine.state {
            try Self.withFileLock(url) { try Self.requireCurrentFile(url, baseline: baseline) }
        } else {
            let updated = try Self.withFileLock(url) { () throws -> [UInt8] in
                try Self.requireCurrentFile(url, baseline: baseline)
                return try Self.persist(result, at: url)
            }
            engine = candidate; baseline = updated
        }
        return engine.state
    }
    public func backup() throws -> Data {
        try Self.withFileLock(url) { try Self.requireCurrentFile(url, baseline: baseline) }
        return try JSONEncoder.bench.encode(engine.state)
    }

    /// An explicit replacement, with both the caller's audit count and the last
    /// observed on-disk fingerprint checked before the atomic write.
    @discardableResult public func restore(_ backup: Data, expectedAuditCount: Int) throws -> BenchState {
        guard backup.count <= 200_000_000 else { throw BenchError.invalid("Backup exceeds 200 MB.") }
        guard engine.state.audit.count == expectedAuditCount else { throw BenchError.conflict("Local data changed; review before restoring.") }
        let decoded = try JSONDecoder.bench.decode(BenchState.self, from: backup)
        let candidate = try BenchEngine(state: decoded)
        let updated = try Self.withFileLock(url) { () throws -> [UInt8] in
            try Self.requireCurrentFile(url, baseline: baseline)
            return try Self.persist(candidate.state, at: url)
        }
        engine = candidate; baseline = updated
        return engine.state
    }
    @discardableResult public func reset(expectedAuditCount: Int) throws -> BenchState {
        guard engine.state.audit.count == expectedAuditCount else { throw BenchError.conflict("Local data changed; refresh before resetting.") }
        let empty = try BenchEngine()
        let updated = try Self.withFileLock(url) { () throws -> [UInt8] in
            try Self.requireCurrentFile(url, baseline: baseline)
            return try Self.persist(empty.state, at: url)
        }
        engine = empty; baseline = updated
        return engine.state
    }

    /// Export terminal runs to a separate JSON file, verify its bytes, then remove
    /// those runs from the live database. A failed database write leaves a redundant
    /// archive and the original records; it cannot silently discard the only copy.
    @discardableResult public func archive(_ runIDs: [UUID], to archiveURL: URL,
                                            actor: String, expectedAuditCount: Int,
                                            at: Date = Date()) throws -> ArchiveReceipt {
        let recordedActor = try Self.requiredActor(actor)
        let ids = Set(runIDs)
        guard !ids.isEmpty, ids.count == runIDs.count else { throw BenchError.invalid("Select distinct completed or aborted runs.") }
        guard engine.state.audit.count == expectedAuditCount else { throw BenchError.conflict("Local data changed; refresh before archiving.") }
        let archivePath = archiveURL.standardizedFileURL
        guard archivePath != url.standardizedFileURL,
              archivePath != url.appendingPathExtension("lock").standardizedFileURL else {
            throw BenchError.invalid("Archive must use a separate output path.")
        }
        let current = engine.state
        let selected = try runIDs.map { id -> Run in
            guard let run = current.runs[id], run.status == .closed || run.status == .aborted else {
                throw BenchError.blocked("Only completed or aborted runs can be archived.")
            }
            return run
        }
        let setupIDs = Set(selected.map(\.setupID))
        let bundle = ArchiveBundle(schema: 1, createdAt: at, runs: selected,
                                   setups: setupIDs.compactMap { current.setups[$0] },
                                   audit: current.audit.filter { ids.contains($0.subjectID) || setupIDs.contains($0.subjectID) })
        let bytes = try JSONEncoder.bench.encode(bundle)
        guard bytes.count <= 200_000_000 else { throw BenchError.invalid("Archive exceeds 200 MB; use smaller batches.") }
        let hash = Self.hex(Self.fingerprint(bytes))
        let receipt = ArchiveReceipt(id: UUID(), createdAt: at, runIDs: runIDs,
                                     filename: archivePath.lastPathComponent, sha256: hash, bytes: bytes.count)
        var candidate = current
        for id in ids { candidate.runs.removeValue(forKey: id) }
        let removedEvents = candidate.audit.filter { ids.contains($0.subjectID) }
        candidate.archivedOperationIDs.formUnion(removedEvents.map(\.operationID))
        candidate.audit.removeAll { ids.contains($0.subjectID) }
        candidate.archiveReceipts.append(receipt)
        candidate.audit.append(Audit(operationID: receipt.id, at: at, actor: recordedActor,
                                     action: "archiveRuns", subjectID: receipt.id,
                                     detail: "\(receipt.filename) sha256=\(hash)"))
        let verified = try BenchEngine(state: candidate)
        let updated = try Self.withFileLock(url) { () throws -> [UInt8] in
            try Self.requireCurrentFile(url, baseline: baseline)
            try FileManager.default.createDirectory(at: archivePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            let reservation = archivePath.path.withCString {
                Darwin.open($0, O_CREAT | O_EXCL | O_WRONLY, mode_t(0o600))
            }
            guard reservation >= 0 else { throw BenchError.conflict("Archive output already exists or cannot be created.") }
            _ = Darwin.close(reservation)
            var options: Data.WritingOptions = [.atomic]
            #if os(iOS)
            options.insert(.completeFileProtection)
            #endif
            try bytes.write(to: archivePath, options: options)
            let onDisk = try Self.readBounded(archivePath)
            guard Self.fingerprint(onDisk) == Self.fingerprint(bytes) else { throw BenchError.invalid("Archive readback failed; live records were retained.") }
            return try Self.persist(verified.state, at: url)
        }
        engine = verified; baseline = updated
        return receipt
    }

    /// Bring a previously exported batch back into the live searchable database.
    /// The archive must match a receipt in the current database exactly.
    @discardableResult public func restoreArchive(_ data: Data, receiptID: UUID,
                                                    actor: String, expectedAuditCount: Int,
                                                    at: Date = Date()) throws -> BenchState {
        let recordedActor = try Self.requiredActor(actor)
        guard data.count <= 200_000_000 else { throw BenchError.invalid("Archive exceeds 200 MB.") }
        guard engine.state.audit.count == expectedAuditCount,
              let receipt = engine.state.archiveReceipts.first(where: { $0.id == receiptID }),
              receipt.sha256 == Self.hex(Self.fingerprint(data)), receipt.bytes == data.count else {
            throw BenchError.conflict("Archive receipt or local state does not match; refresh or select the correct file.")
        }
        let bundle = try JSONDecoder.bench.decode(ArchiveBundle.self, from: data)
        guard bundle.schema == 1, Set(bundle.runs.map(\.id)) == Set(receipt.runIDs),
              bundle.runs.count == receipt.runIDs.count else { throw BenchError.invalid("Archive contents do not match the receipt.") }
        var candidate = engine.state
        for setup in bundle.setups {
            guard let live = candidate.setups[setup.id], live.part == setup.part,
                  live.drawing == setup.drawing, live.machine == setup.machine,
                  live.revision == setup.revision, live.expected == setup.expected,
                  live.dimensions == setup.dimensions else {
                throw BenchError.conflict("Referenced setup changed or is missing.")
            }
        }
        for run in bundle.runs {
            guard run.status == .closed || run.status == .aborted, candidate.runs[run.id] == nil else {
                throw BenchError.invalid("Archive contains an active or duplicate run.")
            }
            candidate.runs[run.id] = run
        }
        let restoredIDs = Set(bundle.runs.map(\.id))
        let restoredEvents = bundle.audit.filter { restoredIDs.contains($0.subjectID) }
        candidate.archivedOperationIDs.subtract(restoredEvents.map(\.operationID))
        candidate.audit.append(contentsOf: restoredEvents)
        candidate.archiveReceipts.removeAll { $0.id == receiptID }
        candidate.audit.append(Audit(operationID: UUID(), at: at, actor: recordedActor,
                                     action: "restoreArchive", subjectID: receiptID,
                                     detail: "Restored \(bundle.runs.count) runs"))
        let verified = try BenchEngine(state: candidate)
        let updated = try Self.withFileLock(url) { () throws -> [UInt8] in
            try Self.requireCurrentFile(url, baseline: baseline)
            return try Self.persist(verified.state, at: url)
        }
        engine = verified; baseline = updated
        return engine.state
    }

    private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private static func requiredActor(_ actor: String) throws -> String {
        let name = actor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 256,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BenchError.invalid("Actor must contain 1–256 printable characters.")
        }
        return name
    }
    private static func fingerprint(_ data: Data) -> [UInt8] { Array(SHA256.hash(data: data)) }
    private static func load(_ url: URL) throws -> (BenchEngine, [UInt8]?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (try BenchEngine(), nil) }
        let data = try readBounded(url)
        return (try BenchEngine(state: JSONDecoder.bench.decode(BenchState.self, from: data)), fingerprint(data))
    }
    private static func requireCurrentFile(_ url: URL, baseline: [UInt8]?) throws {
        let actual: [UInt8]?
        if FileManager.default.fileExists(atPath: url.path) { actual = fingerprint(try readBounded(url)) }
        else { actual = nil }
        guard actual == baseline else { throw BenchError.conflict("Local data was changed by another writer. Refresh and retry.") }
    }
    private static func readBounded(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.int64Value > 200_000_000 { throw BenchError.invalid("Database exceeds 200 MB.") }
        return try Data(contentsOf: url)
    }
    @discardableResult private static func persist(_ state: BenchState, at url: URL) throws -> [UInt8] {
        let data = try JSONEncoder.bench.encode(state)
        guard data.count <= 200_000_000 else { throw BenchError.invalid("Database exceeds 200 MB; export and archive older work.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try data.write(to: url, options: options)
        return fingerprint(data)
    }
    private static func withFileLock<T>(_ url: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = lockURL.path.withCString { Darwin.open($0, O_CREAT | O_RDWR, mode_t(0o600)) }
        guard descriptor >= 0 else { throw BenchError.conflict("Cannot open the database lock.") }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.flock(descriptor, LOCK_EX) == 0 else { throw BenchError.conflict("Cannot lock the database.") }
        defer { _ = Darwin.flock(descriptor, LOCK_UN) }
        return try body()
    }
}

private extension JSONEncoder {
    static var bench: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
private extension JSONDecoder {
    static var bench: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

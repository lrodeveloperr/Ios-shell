import Foundation
import Observation
import Security

enum UsageRecordingResult: Equatable, Sendable {
    case recorded(remaining: Int)
    case duplicate(remaining: Int)
    case limitReached
    case invalidIdentifier
    case persistenceFailed
    case notMetered
}

enum UsageLoadResult: Sendable {
    /// Records keyed by action ID with the time each action succeeded.
    case loaded([String: Date])
    /// Storage could not be read (for example before first unlock). Nothing may
    /// be written until a later read succeeds, or real usage would be erased.
    case unavailable
}

protocol UsagePersisting: Sendable {
    func load() -> Set<String>
    func save(_ actionIDs: Set<String>) throws
    /// Dated records. The default bridges to `load()` and treats every legacy
    /// record as outside any calendar window, while still counting it for a
    /// lifetime limit.
    func loadRecords() -> UsageLoadResult
    func saveRecords(_ records: [String: Date]) throws
}

extension UsagePersisting {
    func loadRecords() -> UsageLoadResult {
        .loaded(Dictionary(uniqueKeysWithValues: load().map { ($0, Date.distantPast) }))
    }

    func saveRecords(_ records: [String: Date]) throws {
        try save(Set(records.keys))
    }
}

struct KeychainUsageStore: UsagePersisting {
    let service: String
    let accessGroup: String?
    let legacyAccount = "successful-actions-v1"
    let account = "successful-actions-v2"

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.goodusestudios.shell",
        accessGroup: String? = ShellConfiguration.keychainAccessGroup
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func load() -> Set<String> {
        if case let .loaded(records) = loadRecords() { return Set(records.keys) }
        return []
    }

    func save(_ actionIDs: Set<String>) throws {
        try saveRecords(Dictionary(uniqueKeysWithValues: actionIDs.map { ($0, Date.distantPast) }))
    }

    func loadRecords() -> UsageLoadResult {
        switch read(account: account) {
        case let .success(data?):
            // Undecodable data is replaced, matching the version 1 behavior.
            return .loaded((try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:])
        case .failure:
            return .unavailable
        case .success(nil):
            break
        }
        // Migrate the version 1 identifier list without losing counted usage.
        switch read(account: legacyAccount) {
        case let .success(data?):
            let values = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            return .loaded(Dictionary(values.map { ($0, Date.distantPast) }, uniquingKeysWith: { first, _ in first }))
        case .success(nil):
            return .loaded([:])
        case .failure:
            return .unavailable
        }
    }

    func saveRecords(_ records: [String: Date]) throws {
        let data = try JSONEncoder().encode(records)
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw UsageStoreError.status(insertStatus) }
        } else if status != errSecSuccess {
            throw UsageStoreError.status(status)
        }
    }

    private func read(account: String) -> Result<Data?, UsageStoreError> {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return .success(result as? Data)
        case errSecItemNotFound: return .success(nil)
        default: return .failure(.status(status))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

struct UserDefaultsUsageStore: UsagePersisting, @unchecked Sendable {
    let defaults: UserDefaults
    let key: String

    func load() -> Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }
    func save(_ actionIDs: Set<String>) throws { defaults.set(actionIDs.sorted(), forKey: key) }

    func loadRecords() -> UsageLoadResult {
        if let data = defaults.data(forKey: key + ".v2"),
           let records = try? JSONDecoder().decode([String: Date].self, from: data) {
            return .loaded(records)
        }
        return .loaded(Dictionary(uniqueKeysWithValues: load().map { ($0, Date.distantPast) }))
    }

    func saveRecords(_ records: [String: Date]) throws {
        defaults.set(try JSONEncoder().encode(records), forKey: key + ".v2")
    }
}

@MainActor
@Observable
final class UsageLedger {
    private let store: any UsagePersisting
    private let limit: Int
    private let window: UsageWindow
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private(set) var records: [String: Date]
    private(set) var persistenceHealthy: Bool
    /// Observed reference time so calendar-window counts update on refresh.
    private(set) var referenceDate: Date

    init(
        limit: Int,
        window: UsageWindow = .lifetime,
        store: any UsagePersisting = KeychainUsageStore(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.limit = max(0, limit)
        self.window = window
        self.store = store
        self.calendar = calendar
        self.now = now
        referenceDate = now()
        records = [:]
        persistenceHealthy = false
        reload()
    }

    var successfulActionIDs: Set<String> { Set(records.keys) }
    var successfulActionCount: Int { countedRecords.count }
    var remaining: Int { max(0, limit - successfulActionCount) }
    var hasFreeActionRemaining: Bool { persistenceHealthy && remaining > 0 }

    /// Re-reads storage when it was previously unavailable and advances the
    /// calendar window. Call when the app becomes active.
    func refresh() {
        referenceDate = now()
        if !persistenceHealthy { reload() }
    }

    /// Call only after the product action has completed successfully. A stable,
    /// product-owned UUID makes retries idempotent and prevents double charging.
    @discardableResult
    func recordSuccessfulAction(id rawID: String) -> UsageRecordingResult {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.utf8.count <= 128 else { return .invalidIdentifier }
        if !persistenceHealthy { reload() }
        referenceDate = now()
        if records[id] != nil { return .duplicate(remaining: remaining) }
        guard hasFreeActionRemaining else { return .limitReached }

        var revised = pruned(records)
        revised[id] = referenceDate
        do {
            try store.saveRecords(revised)
            records = revised
            return .recorded(remaining: remaining)
        } catch {
            persistenceHealthy = false
            return .persistenceFailed
        }
    }

    private var countedRecords: [String: Date] {
        guard let start = windowStart(for: referenceDate) else { return records }
        return records.filter { $0.value >= start }
    }

    private func windowStart(for date: Date) -> Date? {
        switch window {
        case .lifetime: nil
        case .day: calendar.dateInterval(of: .day, for: date)?.start
        case .month: calendar.dateInterval(of: .month, for: date)?.start
        }
    }

    /// Drops records from past calendar windows so storage stays bounded.
    private func pruned(_ records: [String: Date]) -> [String: Date] {
        guard let start = windowStart(for: referenceDate) else { return records }
        return records.filter { $0.value >= start }
    }

    private func reload() {
        switch store.loadRecords() {
        case let .loaded(loaded):
            records = loaded
            do {
                try store.saveRecords(loaded)
                persistenceHealthy = true
            } catch {
                persistenceHealthy = false
            }
        case .unavailable:
            persistenceHealthy = false
        }
    }
}

enum UsageStoreError: Error {
    case status(OSStatus)
}

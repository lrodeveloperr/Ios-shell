import Foundation
import GymDayAppleAdapters
import GymDayCore
import Observation
import SwiftData

/// MainActor-observable wrapper around the `GymDayEngine` actor so SwiftUI
/// views can bind to its state the same way they bind to `ShellModel`.
///
/// The movement catalog is empty and no entitlement is pushed into the
/// engine yet - this is infrastructure wiring only. Real movement content
/// and the shell-to-engine entitlement bridge (`replaceEntitlement`) are
/// separate, not-yet-started work.
@MainActor
@Observable
final class GymDayStore {
    private(set) var snapshot: EngineSnapshot?
    private(set) var startupError: String?
    private var engine: GymDayEngine?

    func start() async {
        guard engine == nil else { return }
        do {
            let configuration = ModelConfiguration(
                schema: Schema(versionedSchema: GymDaySchemaV1.self),
                cloudKitDatabase: .none
            )
            let modelContainer = try ModelContainer(
                for: Schema(versionedSchema: GymDaySchemaV1.self),
                migrationPlan: GymDaySchemaMigrationPlan.self,
                configurations: [configuration]
            )
            let repository = SwiftDataEngineRepository(modelContainer: modelContainer)
            let catalog = try MovementCatalog(movements: [])
            let engine = try await GymDayEngine.open(repository: repository, catalog: catalog, now: Date())
            self.engine = engine
            snapshot = await engine.currentSnapshot()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func refresh() async {
        guard let engine else { return }
        snapshot = await engine.currentSnapshot()
    }
}

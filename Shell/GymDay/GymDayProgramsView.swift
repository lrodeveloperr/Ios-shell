import GymDayCore
import SwiftUI

/// The real Programs screen: the active program's weeks and sessions, with
/// a lock badge on any week the engine's own entitlement policy currently
/// pauses (`.pausedRequiresPro`) rather than a client-side approximation.
struct GymDayProgramsView: View {
    @Environment(GymDayStore.self) private var store
    @Environment(\.locale) private var locale
    @State private var weekAccess: [Int: ProgramWeekAccessState] = [:]

    var body: some View {
        Group {
            if let program = store.activeProgram {
                List {
                    ForEach(program.weeks, id: \.index) { week in
                        Section {
                            ForEach(week.sessions) { session in
                                sessionRow(session)
                            }
                        } header: {
                            weekHeader(week)
                        }
                    }
                }
            } else {
                ContentUnavailableView("progress.needsSetup", systemImage: "calendar")
            }
        }
        .task {
            if let program = store.activeProgram {
                weekAccess = await store.weekAccessStates(programID: program.id)
            }
        }
    }

    private func weekHeader(_ week: ProgramWeek) -> some View {
        HStack {
            Text("第\(week.index + 1)週")
            if weekAccess[week.index] == .pausedRequiresPro {
                Spacer()
                Label("upgrade", systemImage: "lock.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sessionRow(_ session: PlannedSession) -> some View {
        HStack {
            Text(session.scheduledDate.formatted(.dateTime.locale(locale).month().day().weekday(.abbreviated)))
            Spacer()
            Text("\(session.items.count)種目")
                .foregroundStyle(.secondary)
            if store.sessionRecord(forPlannedSessionID: session.id)?.status == .completed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.subheadline)
    }
}

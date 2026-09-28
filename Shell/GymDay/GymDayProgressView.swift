import GymDayCore
import SwiftUI

/// The real Progress screen: weekly adherence/volume from the engine's own
/// `progressAnalytics`, which already resolves free-vs-pro history length
/// through entitlement - this view doesn't need to know the tier itself.
struct GymDayProgressView: View {
    @Environment(GymDayStore.self) private var store
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report = store.progressReport {
                    if let latest = report.weekly.last {
                        thisWeekCard(latest)
                    }
                    ForEach(report.weekly.reversed(), id: \.weekStarting) { point in
                        weekRow(point)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .task { await store.loadProgress() }
    }

    private func thisWeekCard(_ point: WeeklyProgressPoint) -> some View {
        HStack(spacing: 8) {
            statTile(value: "\(point.completedSessionCount)/\(point.plannedSessionCount)", caption: "今週の実施")
            statTile(value: "\(point.adherenceBasisPoints / 100)%", caption: "達成率")
            statTile(value: "\(Int(point.bestEstimatedOneRepMaxGrams / 1000))kg", caption: "自己ベスト")
        }
    }

    private func statTile(value: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold))
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func weekRow(_ point: WeeklyProgressPoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(point.weekStarting.formatted(.dateTime.locale(locale).month().day()))の週")
                    .font(.subheadline.weight(.semibold))
                Text("\(point.completedSessionCount)/\(point.plannedSessionCount)回・\(volumeKilograms(point))kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(point.adherenceBasisPoints / 100)%")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(point.adherenceBasisPoints >= 7500 ? Color.accentColor : .secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func volumeKilograms(_ point: WeeklyProgressPoint) -> Int {
        Int(point.strengthVolumeGramRepetitions / 1000)
    }
}

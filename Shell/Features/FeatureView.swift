import SwiftUI

/// Conventional stack presentation used by derived apps that don't provide the
/// optional list-detail split contract.
struct FeatureView: View {
    let destination: ShellDestination
    let context: FeatureCanvasContext
    @Environment(ShellModel.self) private var model
    @State private var completedActions = 0

    var body: some View {
        switch activeContentState {
        case .loading:
            ProgressView("loading").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("empty.title", systemImage: "tray", description: Text("empty.message"))
        case .error:
            ContentUnavailableView {
                Label("error.title", systemImage: "wifi.exclamationmark")
            } description: {
                Text("error.message")
            } actions: {
                Button("tryAgain", action: recoverFromDemoError).buttonStyle(.borderedProminent)
            }
        case .populated:
            featureList
        }
    }

    private var activeContentState: SampleContentState {
#if DEBUG
        model.contentState
#else
        .populated
#endif
    }

    private func recoverFromDemoError() {
#if DEBUG
        model.contentState = .populated
#endif
    }

    private var featureList: some View {
        List {
            featureHeader
            featureActionSection

            Section {
                ForEach(1...8, id: \.self) { index in
                    NavigationLink {
                        PlaceholderDetail(title: "Item \(index)")
                    } label: {
                        featureRow(index)
                    }
                    .accessibilityIdentifier("shell.feature.item.\(index)")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var featureHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("feature.today").font(.largeTitle.bold())
                Text("feature.boundary.message").foregroundStyle(.secondary)
                if let remaining = context.remainingFreeActions() {
                    Text("usage.remaining \(remaining)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var featureActionSection: some View {
        Section("feature.access.section") {
            Button("feature.completeSample") { completeSampleAction() }
            LabeledContent("feature.completed", value: "\(completedActions)")
        }
    }

    private func featureRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(destination.titleKey)) + Text(" · \(index)")
            Text("feature.supporting").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func completeSampleAction() {
        let result = context.recordSuccessfulAction(UUID().uuidString)
        if case .invalidIdentifier = result { return }
        completedActions += 1
    }
}

/// Sidebar used by the shell-owned NavigationSplitView. Stable String
/// selection keeps iPad selection highlighted and allows per-scene restoration.
struct FeatureSplitSidebar: View {
    let destination: ShellDestination
    let context: FeatureCanvasContext
    @Binding var selection: String?
    @Environment(ShellModel.self) private var model
    @State private var completedActions = 0

    var body: some View {
        switch activeContentState {
        case .loading:
            ProgressView("loading").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("empty.title", systemImage: "tray", description: Text("empty.message"))
        case .error:
            ContentUnavailableView {
                Label("error.title", systemImage: "wifi.exclamationmark")
            } description: {
                Text("error.message")
            } actions: {
                Button("tryAgain", action: recoverFromDemoError).buttonStyle(.borderedProminent)
            }
        case .populated:
            featureList
        }
    }

    private var activeContentState: SampleContentState {
#if DEBUG
        model.contentState
#else
        .populated
#endif
    }

    private var featureList: some View {
        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("feature.today").font(.largeTitle.bold())
                    Text("feature.boundary.message").foregroundStyle(.secondary)
                    if let remaining = context.remainingFreeActions() {
                        Text("usage.remaining \(remaining)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
            }

            Section("feature.access.section") {
                Button("feature.completeSample") { completeSampleAction() }
                LabeledContent("feature.completed", value: "\(completedActions)")
            }

            Section {
                ForEach(1...8, id: \.self) { index in
                    let id = "item-\(index)"
                    NavigationLink(value: id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(destination.titleKey)) + Text(" · \(index)")
                            Text("feature.supporting").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("shell.feature.item.\(index)")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func recoverFromDemoError() {
#if DEBUG
        model.contentState = .populated
#endif
    }

    private func completeSampleAction() {
        let result = context.recordSuccessfulAction(UUID().uuidString)
        if case .invalidIdentifier = result { return }
        completedActions += 1
    }
}

struct FeatureSplitDetail: View {
    let selection: String?

    var body: some View {
        if let selection, let index = selection.split(separator: "-").last {
            PlaceholderDetail(title: "Item \(index)")
        } else {
            ContentUnavailableView(
                "select.title",
                systemImage: "rectangle.split.2x1",
                description: Text("select.message")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }
}

private struct PlaceholderDetail: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "square.dashed", description: Text("feature.replaceDetail"))
            .navigationTitle(title)
    }
}

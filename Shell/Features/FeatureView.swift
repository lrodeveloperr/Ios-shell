import SwiftUI

struct FeatureView: View {
    let destination: ShellDestination
    @Environment(ShellModel.self) private var model

    var body: some View {
        GeometryReader { geometry in
            switch model.contentState {
            case .loading:
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("Your app’s primary empty state belongs here."))
            case .error:
                ContentUnavailableView {
                    Label("Couldn’t load content", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Keep the explanation human and offer one clear recovery action.")
                } actions: {
                    Button("Try again") { model.contentState = .populated }.buttonStyle(.borderedProminent)
                }
            case .populated:
                if geometry.size.width >= 700 {
                    HStack(spacing: 0) {
                        featureList.frame(width: min(420, geometry.size.width * 0.42))
                        Divider()
                        ContentUnavailableView("Select an item", systemImage: "rectangle.split.2x1", description: Text("List-detail uses tablet space instead of stretching the phone layout."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground))
                    }
                } else {
                    featureList
                }
            }
        }
    }

    private var featureList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today").font(.largeTitle.bold())
                    Text("This is the replaceable feature area. Shell chrome stays untouched.").foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 8)
            }
            Section {
                ForEach(1...8, id: \.self) { index in
                    NavigationLink {
                        PlaceholderDetail(title: "Item \(index)")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(destination.title) item \(index)")
                            Text("Useful supporting information").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct PlaceholderDetail: View {
    let title: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "square.dashed", description: Text("Replace with feature-specific content."))
            .navigationTitle(title)
    }
}

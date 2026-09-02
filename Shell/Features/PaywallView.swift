import SwiftUI

struct PaywallView: View {
    @State private var purchases = PurchaseService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
                Text("Make the useful thing unlimited.").font(.largeTitle.bold())
                Text("One focused value statement, transparent pricing, restore access, and legal links—without dark patterns.").foregroundStyle(.secondary)
                ForEach(["Unlimited core actions", "No advertising", "Supports continued development"], id: \.self) { benefit in
                    Label(benefit, systemImage: "checkmark.circle.fill").symbolRenderingMode(.hierarchical)
                }
                Button(purchases.primaryProduct.map { "Continue · \($0.displayPrice)" } ?? "Continue · configured price") {
                    Task { await purchases.purchasePrimary() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                Button("Restore purchases") { Task { await purchases.restore() } }
                    .frame(maxWidth: .infinity)
                HStack {
                    Link("Privacy", destination: ShellConfiguration.privacyURL)
                    Spacer()
                    Link("Terms", destination: ShellConfiguration.termsURL)
                }
                .font(.footnote)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Upgrade")
        .task { await purchases.load() }
        .alert("Store", isPresented: $purchases.showingError) { Button("OK") {} } message: { Text(purchases.message) }
    }
}

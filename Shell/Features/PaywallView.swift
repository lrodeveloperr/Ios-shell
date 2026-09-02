import SwiftUI

struct PaywallView: View {
    @Environment(ShellModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
                Text("paywall.title").font(.largeTitle.bold())
                Text("paywall.message").foregroundStyle(.secondary)
                ForEach(["paywall.benefit.unlimited", "paywall.benefit.noAds", "paywall.benefit.support"], id: \.self) { benefit in
                    Label(LocalizedStringKey(benefit), systemImage: "checkmark.circle.fill").symbolRenderingMode(.hierarchical)
                }

                if let product = model.access.purchases.primaryProduct {
                    Button {
                        Task { await model.access.purchases.purchasePrimary() }
                    } label: {
                        Text("\(product.displayName) · \(product.displayPrice)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    ProgressView("paywall.loadingProduct").frame(maxWidth: .infinity)
                }

                Button("paywall.restore") { Task { await model.access.purchases.restore() } }
                    .frame(maxWidth: .infinity)

                HStack {
                    Link("privacy", destination: ShellConfiguration.legal.privacyURL)
                    Spacer()
                    Link("terms", destination: ShellConfiguration.legal.termsURL)
                }
                .font(.footnote)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("upgrade")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } } }
        .onChange(of: model.access.purchases.isEntitled) { _, entitled in
            if entitled { dismiss() }
        }
        .alert("store", isPresented: purchaseErrorBinding) {
            Button("ok") {}
        } message: {
            Text(model.access.purchases.message)
        }
    }

    private var purchaseErrorBinding: Binding<Bool> {
        Binding(
            get: { model.access.purchases.showingError },
            set: { model.access.purchases.showingError = $0 }
        )
    }
}

import SwiftUI

/// Commerce surfaces deliberately contain no app icon, logo, custom image
/// asset, or brand mark. One-time purchases only; subscriptions start directly
/// through StoreKit from their upgrade controls.
struct PaywallView: View {
    @Environment(ShellModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var legalDocument: LegalDocument?
    let showsDoneButton: Bool

    init(showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("paywall.title")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("paywall.message")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ForEach(["paywall.benefit.unlimited", "paywall.benefit.noAds", "paywall.benefit.support"], id: \.self) { benefit in
                    Label(LocalizedStringKey(benefit), systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }

                if let product = model.access.purchases.primaryProduct {
                    Button {
                        Task { await model.access.purchases.purchasePrimary() }
                    } label: {
                        VStack(spacing: 2) {
                            Text(product.displayName)
                                .font(.headline)
                            Text(product.displayPrice)
                                .font(.title2.bold())
                            Text("paywall.purchase")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.access.purchases.isPurchasing || model.access.purchases.isRestoring)
                    .accessibilityIdentifier("shell.paywall.purchase")
                } else if model.access.purchases.isLoadingProducts {
                    ProgressView("paywall.loadingProduct").frame(maxWidth: .infinity)
                } else {
                    Button("paywall.retryProduct") {
                        Task { await model.access.purchases.start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("shell.paywall.retryProduct")
                }

                Button("paywall.restore") { Task { await model.access.purchases.restore() } }
                    .disabled(model.access.purchases.isPurchasing || model.access.purchases.isRestoring)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("shell.paywall.restore")

                HStack {
                    Button("privacy") { legalDocument = .privacy }
                    Spacer()
                    Button("terms") { legalDocument = .terms }
                }
                .font(.footnote)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("upgrade")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("shell.paywall")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } }
            }
        }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document)
                .ignoresSafeArea()
        }
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

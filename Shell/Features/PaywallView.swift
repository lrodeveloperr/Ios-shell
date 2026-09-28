import StoreKit
import SwiftUI

/// Commerce surfaces deliberately contain no app icon, logo, custom image
/// asset, or brand mark. Pricing always comes live from StoreKit.
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

                storeOffer

                Button("paywall.restore") { Task { await model.access.purchases.restore() } }
                    .disabled(purchaseIsBusy)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("shell.paywall.restore")

                HStack {
                    Button("privacy") { legalDocument = .privacy }
                    Spacer()
                    Button("terms") { legalDocument = .terms }
                }
                .font(.footnote)
                .frame(minHeight: 44)
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

    @ViewBuilder
    private var storeOffer: some View {
        if let product = model.access.purchases.primaryProduct {
            if let subscription = product.subscription {
                VStack(alignment: .leading, spacing: 10) {
                    Text(product.displayName)
                        .font(.headline)

                    Text(product.displayPrice)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text(subscriptionPeriodKey(subscription.subscriptionPeriod))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !product.description.isEmpty {
                        Text(product.description)
                            .foregroundStyle(.secondary)
                    }

                    Button("subscription.subscribe") {
                        Task { await model.access.purchases.purchasePrimary() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(purchaseIsBusy)
                    .accessibilityIdentifier("shell.paywall.purchase")

                    Text("paywall.subscriptionDisclosure")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)
            } else {
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
                .disabled(purchaseIsBusy)
                .accessibilityIdentifier("shell.paywall.purchase")
            }
        } else if model.access.purchases.isLoadingProducts {
            ProgressView("paywall.loadingProduct")
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("purchase.productUnavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("paywall.retryProduct") {
                    Task { await model.access.purchases.start() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("shell.paywall.retryProduct")
            }
        }
    }

    private var purchaseIsBusy: Bool {
        model.access.purchases.isPurchasing ||
            model.access.purchases.isRestoring ||
            model.access.purchases.isLoadingProducts
    }

    private var purchaseErrorBinding: Binding<Bool> {
        Binding(
            get: { model.access.purchases.showingError },
            set: { model.access.purchases.showingError = $0 }
        )
    }

    private func subscriptionPeriodKey(_ period: Product.SubscriptionPeriod) -> LocalizedStringKey {
        switch (period.unit, period.value) {
        case (.day, 1):
            "paywall.period.day.one"
        case (.day, let value):
            "paywall.period.day.other \(value)"
        case (.week, 1):
            "paywall.period.week.one"
        case (.week, let value):
            "paywall.period.week.other \(value)"
        case (.month, 1):
            "paywall.period.month.one"
        case (.month, let value):
            "paywall.period.month.other \(value)"
        case (.year, 1):
            "paywall.period.year.one"
        case (.year, let value):
            "paywall.period.year.other \(value)"
        @unknown default:
            "paywall.period.unknown"
        }
    }
}

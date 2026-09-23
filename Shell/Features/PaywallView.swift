import StoreKit
import SwiftUI

/// Commerce surfaces deliberately contain no app icon, logo, custom image
/// asset, or brand mark. Keep all benefits factual and product-specific.
struct PaywallView: View {
    @Environment(ShellModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var legalDocument: LegalDocument?
    @State private var showingManageSubscriptions = false
    @State private var showingOfferCodeRedemption = false
    let showsDoneButton: Bool

    init(showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
    }

    private var purchases: PurchaseService { model.access.purchases }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("paywall.title")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("paywall.message")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ForEach(ShellConfiguration.paywallBenefitKeys, id: \.self) { benefit in
                    Label(LocalizedStringKey(benefit), systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }

                if purchases.subscriptionCondition == .billingRetry {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("paywall.billingRetry.title", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text("paywall.billingRetry.message").foregroundStyle(.secondary)
                        Button("subscription.manage") { showingManageSubscriptions = true }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
                } else if !purchases.purchasableProducts.isEmpty {
                    ForEach(purchases.purchasableProducts, id: \.id) { product in
                        purchaseButton(for: product)
                    }
                } else if purchases.isLoadingProducts {
                    ProgressView("paywall.loadingProduct").frame(maxWidth: .infinity)
                } else {
                    Button("paywall.retryProduct") {
                        Task { await purchases.start(userInitiated: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("shell.paywall.retryProduct")
                }

                if purchases.primaryProduct?.subscription != nil {
                    Text("paywall.subscriptionDisclosure")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("paywall.restore") { Task { await purchases.restore() } }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("shell.paywall.restore")

                if model.access.configuration.offersCodeRedemption,
                   model.access.configuration.includesSubscription {
                    Button("paywall.redeemCode") { showingOfferCodeRedemption = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("shell.paywall.redeemCode")
                }

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
        .navigationTitle(AppLocalization.string("upgrade", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("shell.paywall")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } }
            }
        }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document, languageID: model.language.resolvedLanguageID)
                .ignoresSafeArea()
        }
        .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        .offerCodeRedemption(isPresented: $showingOfferCodeRedemption) { _ in
            Task { await purchases.refreshEntitlements() }
        }
        .onAppear { purchases.clearError() }
        .onChange(of: purchases.isEntitled) { _, entitled in
            if entitled { dismiss() }
        }
        .alert("store", isPresented: purchaseErrorBinding) {
            Button("ok") {}
        } message: {
            Text(purchases.message)
        }
    }

    private func purchaseButton(for product: Product) -> some View {
        Button {
            Task { await purchases.purchase(product) }
        } label: {
            VStack(spacing: 2) {
                Text(product.displayName)
                    .font(.headline)
                Group {
                    if let subscription = product.subscription {
                        Text(product.displayPrice) + Text(" · ") + Text(periodKey(subscription.subscriptionPeriod))
                    } else {
                        Text(product.displayPrice)
                    }
                }
                .font(.title2.bold())
                if let introOffer = introOfferText(for: product) {
                    Text(introOffer)
                        .font(.subheadline)
                }
                Text("paywall.purchase")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(product.id == purchases.primaryProduct?.id ? "shell.paywall.purchase" : "shell.paywall.purchase.\(product.id)")
    }

    private var purchaseErrorBinding: Binding<Bool> {
        Binding(
            get: { purchases.showingError },
            set: { purchases.showingError = $0 }
        )
    }

    /// Guideline 3.1.2 disclosure of an introductory offer the customer can
    /// redeem. Nil when the product has no offer or the customer is ineligible.
    private func introOfferText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              purchases.introOfferEligibleProductIDs.contains(product.id) else { return nil }
        let duration = offerDuration(offer)
        switch offer.paymentMode {
        case .freeTrial:
            return AppLocalization.string("paywall.intro.freeTrial %@", locale: locale, duration)
        case .payUpFront:
            return AppLocalization.string("paywall.intro.payUpFront %@ %@", locale: locale, offer.displayPrice, duration)
        case .payAsYouGo:
            return AppLocalization.string("paywall.intro.payAsYouGo %@ %@", locale: locale, offer.displayPrice, duration)
        default:
            return AppLocalization.string("paywall.intro.generic %@", locale: locale, duration)
        }
    }

    private func offerDuration(_ offer: Product.SubscriptionOffer) -> String {
        let total = offer.period.value * max(1, offer.periodCount)
        var components = DateComponents()
        switch offer.period.unit {
        case .day: components.day = total
        case .week: components.weekOfMonth = total
        case .month: components.month = total
        case .year: components.year = total
        @unknown default: components.day = total
        }
        var calendar = Calendar.current
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? ""
    }

    private func periodKey(_ period: Product.SubscriptionPeriod) -> LocalizedStringKey {
        switch period.unit {
        case .day: period.value == 1 ? "paywall.period.day.one" : "paywall.period.day.other \(period.value)"
        case .week: period.value == 1 ? "paywall.period.week.one" : "paywall.period.week.other \(period.value)"
        case .month: period.value == 1 ? "paywall.period.month.one" : "paywall.period.month.other \(period.value)"
        case .year: period.value == 1 ? "paywall.period.year.one" : "paywall.period.year.other \(period.value)"
        @unknown default: "paywall.period.unknown"
        }
    }
}

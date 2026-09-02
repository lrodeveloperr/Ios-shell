import SwiftUI

#if ADS_ENABLED
import GoogleMobileAds
import UIKit

struct AdaptiveAdBanner: View {
    let adUnitID: String

    var body: some View {
        GeometryReader { geometry in
            let width = max(320, geometry.size.width)
            let adSize = largeAnchoredAdaptiveBanner(width: width)
            BannerContainer(adSize: adSize, adUnitID: adUnitID)
                .frame(width: adSize.size.width, height: adSize.size.height)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 60)
    }
}

private struct BannerContainer: UIViewRepresentable {
    let adSize: AdSize
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.rootViewController = rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.adSize.size != adSize.size {
            banner.adSize = adSize
            banner.load(Request())
        }
        if banner.rootViewController == nil { banner.rootViewController = rootViewController }
    }

    private var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
#else
/// Keeps root composition identical while producing no advertising view.
struct AdaptiveAdBanner: View {
    let adUnitID: String
    var body: some View { EmptyView() }
}
#endif

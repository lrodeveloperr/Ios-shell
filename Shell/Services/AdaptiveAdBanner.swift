import GoogleMobileAds
import SwiftUI
import UIKit

struct AdaptiveAdBanner: View {
    var body: some View {
        GeometryReader { geometry in
            let width = max(320, geometry.size.width)
            let adSize = largeAnchoredAdaptiveBanner(width: width)
            BannerContainer(adSize: adSize)
                .frame(width: adSize.size.width, height: adSize.size.height)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 60)
    }
}

private struct BannerContainer: UIViewRepresentable {
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = ShellConfiguration.demoBannerUnitID
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        if banner.adSize.size != adSize.size {
            banner.adSize = adSize
            banner.load(Request())
        }
        if banner.rootViewController == nil {
            banner.rootViewController = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }
    }
}

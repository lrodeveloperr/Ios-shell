#!/usr/bin/env bash
set -euo pipefail

mode="${1:---template}"
case "$mode" in
  --template|--release|--release-ads) ;;
  *) echo "Usage: $0 [--template|--release|--release-ads]" >&2; exit 64 ;;
esac

fail() { echo "VALIDATION FAILED: $*" >&2; exit 1; }
# Every tool a check depends on must exist; a missing tool fails the run
# instead of silently skipping the check.
require_tool() { command -v "$1" >/dev/null 2>&1 || fail "Required tool '$1' is not installed"; }
for tool in grep sed python3 ruby plutil /usr/libexec/PlistBuddy; do require_tool "$tool"; done
require_file() { [[ -f "$1" ]] || fail "Missing $1"; }
require_text() { grep -Fq "$2" "$1" || fail "$1 must contain: $2"; }
reject_text() { ! grep -Fq "$2" "$1" || fail "$1 contains forbidden text: $2"; }

[[ -x scripts/validate-shell.sh ]] || fail "scripts/validate-shell.sh must retain its executable bit"

for path in project.yml Config/App.xcconfig StoreKit/Shell.storekit AGENTS.md docs/APPLE_STORE_COMPLIANCE.md docs/DERIVED_APP_RELEASE_WIRING.md docs/UI_REGRESSION_MATRIX.md SHELL_CHANGELOG.md MIGRATIONS.md Shell/App/ShellConfiguration.swift Shell/App/ShellContract.swift Shell/App/FeatureCanvasBoundary.swift Shell/Services/AppLocalization.swift Shell/Services/PurchaseService.swift Shell/Services/AccessController.swift Shell/Services/NativeBackup.swift Shell/Services/AdConsentService.swift Shell/Resources/Info.plist Shell/Resources/Info-Ads.plist Shell/Resources/PrivacyInfo.xcprivacy Shell/Resources/LocalizationBaseline.swift Shell/Resources/gooduse-common-localization-v1.json Shell/Resources/Assets.xcassets/AppIcon.appiconset/ShellIcon-1024.png scripts/check-commerce-branding.sh; do
  require_file "$path"
done

# grep exits 0 on a match, 1 on no match and 2 on an error; only 1 passes.
set +e
grep -rnE 'import (Flutter|React|ReactNative)|FlutterViewController|RCTRootView' Shell
cross_platform_status=$?
set -e
case "$cross_platform_status" in
  1) ;;
  0) fail "Cross-platform runtime detected; this shell must remain native Swift/SwiftUI" ;;
  *) fail "Cross-platform runtime scan could not run" ;;
esac

bash scripts/check-commerce-branding.sh
python3 scripts/validate-localizations.py

# The default product is physically ad-free. Advertising symbols are compiled
# only for ShellAds, which alone links Google Mobile Ads.
reject_text Shell/Resources/Info.plist 'GADApplicationIdentifier'
reject_text Shell/Resources/Info.plist 'SKAdNetworkIdentifier'
require_text project.yml 'ShellAds:'
require_text project.yml 'SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) ADS_ENABLED"'
require_text project.yml 'package: GoogleMobileAds'
require_text Shell/Services/AdConsentService.swift '#if ADS_ENABLED'
require_text Shell/Services/AdaptiveAdBanner.swift '#if ADS_ENABLED'

for mode_name in free ads adsWithRemovePurchase adsWithSubscription oneTimeUnlock subscription usageCapWithOneTimeUnlock usageCapWithSubscription; do
  require_text Shell/App/ShellConfiguration.swift "case $mode_name"
done
for seam in 'Transaction.updates' 'Transaction.currentEntitlements' 'AppStore.sync()' 'revocationDate' 'expirationDate'; do
  require_text Shell/Services/PurchaseService.swift "$seam"
done
require_text Shell/Services/AdConsentService.swift 'ConsentForm.loadAndPresentIfRequired'
require_text Shell/App/ShellRootView.swift '.safeAreaInset(edge: .bottom, spacing: 0) { adBanner }'
require_text Shell/Services/AdaptiveAdBanner.swift '.frame(height: adSize.size.height)'
require_text Shell/Features/PaywallView.swift 'paywall.retryProduct'
require_text Shell/Services/LanguageController.swift 'supported.contains(stored)'
require_text Shell/Services/LanguageController.swift 'SupportedLocaleResolver.isRightToLeft'
require_text Shell/App/ShellRootView.swift '.environment(\.layoutDirection, model.language.layoutDirection)'
require_text docs/LOCALIZATION_RELEASE_CHECKLIST.md 'Automated translation, if used to create a draft, is never treated as approval.'
require_text Shell/Services/NativeBackup.swift 'current free/paid limits'
require_text .github/workflows/testflight.yml 'date -u +%y%m%d%H%M'
require_text .github/workflows/testflight.yml 'Run unit tests before upload'
require_text .github/workflows/testflight.yml 'ENABLE_TESTABILITY=YES'
reject_text .github/workflows/testflight.yml 'SCREENSHOT_BUILD'
# App-specific bridges are optional; when present they must stay separated from
# production-logic uploads.
screenshot_workflow=.github/workflows/welding-wallet-screenshot-testflight.yml
if [[ -f "$screenshot_workflow" ]]; then
  require_text "$screenshot_workflow" 'UPLOAD WELDING WALLET SCREENSHOT'
  require_text "$screenshot_workflow" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=SCREENSHOT_BUILD'
  require_text "$screenshot_workflow" 'Run unit tests before upload'
  reject_text "$screenshot_workflow" 'production_test_ads'
  reject_text "$screenshot_workflow" 'ca-app-pub-'
  reject_text "$screenshot_workflow" 'UPLOAD WELDING WALLET PRODUCTION TEST'
fi
reject_text Shell/Features/SettingsView.swift 'NavigationLink { PaywallView() }'
require_text Shell/Features/OnboardingView.swift 'Toggle(isOn: $accepted)'
require_text Shell/Services/LegalConsentStore.swift 'acceptedLegalVersion'
require_text Shell/App/ShellConfiguration.swift 'static let onboarding: OnboardingProfile?'
require_text Shell/App/ShellRootView.swift 'if let onboarding = ShellConfiguration.onboarding'
require_text Shell/App/ShellRootView.swift 'private var requiresOnboarding: Bool'
require_text Shell/Services/UsageLedger.swift 'KeychainUsageStore'
require_text Shell/Services/UsageLedger.swift 'revised[id] = referenceDate'
require_text Shell/Services/PurchaseService.swift 'OfflineCachePolicy.mayBridge'
require_text Shell/Services/PurchaseService.swift 'runStoreOperation'
require_text Shell/Services/UsageLedger.swift 'id.utf8.count <= 128'
require_text Shell/App/FeatureCanvasBoundary.swift 'switch model.access.decision'
require_text Shell/App/ShellRootView.swift '.tabItem { Label('
require_text Shell/App/ShellRootView.swift 'SettingsView(model: model'
require_text Shell/Features/SettingsView.swift '.environment(\.layoutDirection, model.language.layoutDirection)'
require_text Shell/Features/ShellLabView.swift '#if DEBUG'
require_text Shell/Features/SettingsView.swift '#if DEBUG'
require_text Shell/Features/SettingsView.swift 'SubscriptionSettingsPresentation.resolve'
require_text Shell/Features/SettingsView.swift 'shell.settings.subscription.manage'
require_text Shell/Features/SettingsView.swift '.buttonStyle(.plain)'
require_text Shell/App/ShellModel.swift '#if DEBUG'
require_text Shell/App/ShellContract.swift 'currentVersion = "2.0.0"'
require_text Shell/App/ShellConfiguration.swift 'BackupConfiguration(enabled: false)'

plutil -lint Shell/Resources/Info.plist >/dev/null
plutil -lint Shell/Resources/Info-Ads.plist >/dev/null
plutil -lint Shell/Resources/PrivacyInfo.xcprivacy >/dev/null
for stringsdict in Shell/Resources/*.lproj/*.stringsdict; do
  [[ -e "$stringsdict" ]] || continue
  plutil -lint "$stringsdict" >/dev/null
done
for info_plist in Shell/Resources/Info.plist Shell/Resources/Info-Ads.plist; do
  display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$info_plist")"
  [[ "$display_name" == '$(APP_DISPLAY_NAME)' ]] || fail "$info_plist must read CFBundleDisplayName from APP_DISPLAY_NAME in Config/App.xcconfig"
done
for identity_setting in 'PRODUCT_BUNDLE_IDENTIFIER: com.' 'MARKETING_VERSION:' 'CURRENT_PROJECT_VERSION:' 'DEVELOPMENT_TEAM:'; do
  reject_text project.yml "$identity_setting"
done

for info_plist in Shell/Resources/Info.plist Shell/Resources/Info-Ads.plist; do
  export_flag="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_plist" 2>/dev/null || true)"
  [[ "$export_flag" == "false" ]] || fail "$info_plist must declare ITSAppUsesNonExemptEncryption=false unless the derived app adds non-exempt encryption"
done

ruby <<'RUBY'
require "json"
def keys(path)
  File.readlines(path, encoding: "UTF-8").filter_map { |line| line[/^\s*"([^"]+)"\s*=/, 1] }.sort
end
base = keys("Shell/Resources/en.lproj/Localizable.strings")
Dir["Shell/Resources/*.lproj/Localizable.strings"].each do |path|
  abort "Localization key mismatch in #{path}" unless keys(path) == base
end
abort "Duplicate English localization keys" unless base.length == base.uniq.length

common = JSON.parse(File.read("Shell/Resources/gooduse-common-localization-v1.json", encoding: "UTF-8"))
abort "Shared localization baseline must contain exactly 31 locales" unless common.fetch("locales").length == 31
common.fetch("entries").each do |key, entry|
  abort "Shared localization width mismatch for #{key}" unless entry.fetch("translations").length == 31
end
RUBY

# Read the PNG header directly so the check never depends on an optional tool.
python3 - Shell/Resources/Assets.xcassets/AppIcon.appiconset/ShellIcon-1024.png <<'PY' || fail "App icon must be a 1024x1024 PNG"
import struct, sys
with open(sys.argv[1], "rb") as icon:
    header = icon.read(24)
if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
    sys.exit(1)
width, height = struct.unpack(">II", header[16:24])
sys.exit(0 if (width, height) == (1024, 1024) else 1)
PY

if [[ "$mode" == "--release" || "$mode" == "--release-ads" ]]; then
  reject_text Shell/App/ShellConfiguration.swift 'support@example.com'
  reject_text Shell/App/ShellConfiguration.swift 'https://example.com/'
  reject_text Shell/App/ShellConfiguration.swift 'shell.pro.'
  reject_text Config/App.xcconfig 'APP_DISPLAY_NAME = Shell'
  reject_text Config/App.xcconfig 'com.goodusestudios.shelllab'
  reject_text project.yml 'PRODUCT_NAME: Shell'
  # Template copy that the shell displays in every derived app.
  for catalog in Shell/Resources/*.lproj/Localizable.strings; do
    reject_text "$catalog" 'Version information and app-specific notices belong here.'
    reject_text "$catalog" 'Aquí van la versión y los avisos específicos de la aplicación.'
    reject_text "$catalog" 'Clear value, transparent App Store pricing, restore access, and no dark patterns.'
    reject_text "$catalog" 'Valor claro, precio transparente de App Store, restauración de acceso y sin patrones engañosos.'
  done
  onboarding_profile="$(sed -n 's/.*static let onboarding: OnboardingProfile? = \(.*\)$/\1/p' Shell/App/ShellConfiguration.swift | head -1)"
  [[ -n "$onboarding_profile" ]] || fail "Could not read ShellConfiguration.onboarding"
  if [[ "$onboarding_profile" == ".guidedTour" ]]; then
    for catalog in Shell/Resources/*.lproj/Localizable.strings; do
      reject_text "$catalog" 'Replace only the feature canvas after the product logic is settled.'
      reject_text "$catalog" 'Sustituye únicamente el área funcional cuando la lógica del producto esté definida.'
    done
  fi
  if [[ "$onboarding_profile" == ".singleScreen" ]]; then
    for catalog in Shell/Resources/*.lproj/Localizable.strings; do
      reject_text "$catalog" 'One focused introduction. The app is ready after you accept the legal documents.'
      reject_text "$catalog" 'Una introducción breve. La aplicación estará lista cuando aceptes los documentos legales.'
    done
  fi
  reject_text Shell/Resources/en.lproj/Localizable.strings 'REPLACE_WITH_REVIEWED_'
  reject_text Shell/Resources/es.lproj/Localizable.strings 'REPLACE_WITH_REVIEWED_'
  reject_text Shell/Resources/en.lproj/Localizable.strings 'Make the useful thing unlimited.'
  reject_text Shell/Resources/en.lproj/Localizable.strings 'Unlimited core actions'
  reject_text Shell/Resources/es.lproj/Localizable.strings 'Usa la función sin límites.'
  reject_text Shell/Resources/es.lproj/Localizable.strings 'Acciones principales ilimitadas'
  reject_text Shell/App/ShellApp.swift 'PlaceholderFeatureCanvasProvider()'
  grep -Fq 'privacyURL: URL(string: "https://' Shell/App/ShellConfiguration.swift || fail "Privacy URL must use HTTPS"
  grep -Fq 'termsURL: URL(string: "https://' Shell/App/ShellConfiguration.swift || fail "Terms URL must use HTTPS"
fi

selected_mode="$(sed -n 's/.*mode: \.\([A-Za-z]*\).*/\1/p' Shell/App/ShellConfiguration.swift | head -1)"
[[ -n "$selected_mode" ]] || fail "Could not read the monetization mode from ShellConfiguration.swift"
if [[ "$mode" == "--release-ads" ]]; then
  [[ "$selected_mode" == "ads" || "$selected_mode" == "adsWithRemovePurchase" || "$selected_mode" == "adsWithSubscription" ]] || fail "--release-ads requires an advertising monetization mode"
  reject_text Shell/App/ShellConfiguration.swift 'ca-app-pub-3940256099942544/'
  reject_text Shell/Resources/Info-Ads.plist 'ca-app-pub-3940256099942544~'
  if grep -A1 -F '<key>NSPrivacyCollectedDataTypes</key>' Shell/Resources/PrivacyInfo.xcprivacy | grep -Fq '<array/>'; then
    fail "Advertising release must declare reviewed collected-data types"
  fi
elif [[ "$mode" == "--release" ]]; then
  [[ "$selected_mode" != "ads" && "$selected_mode" != "adsWithRemovePurchase" && "$selected_mode" != "adsWithSubscription" ]] || fail "Advertising mode must use --release-ads and the ShellAds target"
fi

echo "iOS shell validation passed ($mode)."

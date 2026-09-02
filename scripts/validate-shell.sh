#!/usr/bin/env bash
set -euo pipefail

mode="${1:---template}"
case "$mode" in
  --template|--release) ;;
  *) echo "Usage: $0 [--template|--release]" >&2; exit 64 ;;
esac

fail() { echo "VALIDATION FAILED: $*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "Missing $1"; }
require_text() { grep -Fq "$2" "$1" || fail "$1 must contain: $2"; }
reject_text() { ! grep -Fq "$2" "$1" || fail "$1 still contains forbidden placeholder: $2"; }

for path in project.yml Shell/App/ShellConfiguration.swift Shell/App/FeatureCanvasBoundary.swift Shell/Services/PurchaseService.swift Shell/Services/AccessController.swift Shell/Services/AdConsentService.swift Shell/Resources/Info.plist Shell/Resources/PrivacyInfo.xcprivacy Shell/Resources/Assets.xcassets/AppIcon.appiconset/ShellIcon-1024.png; do
  require_file "$path"
done

if rg -n 'import (Flutter|React|ReactNative)|FlutterViewController|RCTRootView' Shell; then
  fail "Cross-platform runtime detected; this shell must remain native Swift/SwiftUI"
fi

for mode_name in free ads adsWithRemovePurchase oneTimeUnlock subscription usageCapWithOneTimeUnlock usageCapWithSubscription; do
  require_text Shell/App/ShellConfiguration.swift "case $mode_name"
done
for seam in 'Transaction.updates' 'Transaction.currentEntitlements' 'AppStore.sync()' 'revocationDate' 'expirationDate'; do
  require_text Shell/Services/PurchaseService.swift "$seam"
done
require_text Shell/Services/AdConsentService.swift 'ConsentForm.loadAndPresentIfRequired'
require_text Shell/Services/AdConsentService.swift 'canRequestAds'
require_text Shell/Features/OnboardingView.swift 'Toggle(isOn: $accepted)'
require_text Shell/Services/LegalConsentStore.swift 'acceptedLegalVersion'
require_text Shell/Services/UsageLedger.swift 'KeychainUsageStore'
require_text Shell/Services/UsageLedger.swift 'revised.insert(id)'

plutil -lint Shell/Resources/Info.plist >/dev/null
plutil -lint Shell/Resources/PrivacyInfo.xcprivacy >/dev/null

ruby <<'RUBY'
def keys(path)
  File.readlines(path).filter_map { |line| line[/^\s*"([^"]+)"\s*=/, 1] }.sort
end
base = keys("Shell/Resources/en.lproj/Localizable.strings")
Dir["Shell/Resources/*.lproj/Localizable.strings"].each do |path|
  abort "Localization key mismatch in #{path}" unless keys(path) == base
end
abort "Duplicate English localization keys" unless base.length == base.uniq.length
RUBY

if command -v sips >/dev/null 2>&1; then
  dimensions="$(sips -g pixelWidth -g pixelHeight Shell/Resources/Assets.xcassets/AppIcon.appiconset/ShellIcon-1024.png 2>/dev/null)"
  grep -Fq 'pixelWidth: 1024' <<<"$dimensions" || fail "App icon width must be 1024"
  grep -Fq 'pixelHeight: 1024' <<<"$dimensions" || fail "App icon height must be 1024"
fi

if [[ "$mode" == "--release" ]]; then
  reject_text Shell/App/ShellConfiguration.swift 'appName = "Shell"'
  reject_text Shell/App/ShellConfiguration.swift 'support@example.com'
  reject_text Shell/App/ShellConfiguration.swift 'https://example.com/'
  reject_text Shell/App/ShellConfiguration.swift 'shell.pro.'
  reject_text Shell/App/ShellConfiguration.swift 'ca-app-pub-3940256099942544/'
  reject_text Shell/Resources/Info.plist 'ca-app-pub-3940256099942544~'
  reject_text Shell/Resources/Info.plist '<string>Shell</string>'
  reject_text project.yml 'com.goodusestudios.shelllab'
  reject_text project.yml 'PRODUCT_NAME: Shell'
  reject_text Shell/Resources/en.lproj/Localizable.strings 'REPLACE_WITH_REVIEWED_'
  reject_text Shell/Resources/es.lproj/Localizable.strings 'REPLACE_WITH_REVIEWED_'
  reject_text Shell/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json 'ShellIcon-1024.png'
  grep -Fq 'privacyURL: URL(string: "https://' Shell/App/ShellConfiguration.swift || fail "Privacy URL must use HTTPS"
  grep -Fq 'termsURL: URL(string: "https://' Shell/App/ShellConfiguration.swift || fail "Terms URL must use HTTPS"

  selected_mode="$(sed -n 's/.*mode: \.\([A-Za-z]*\).*/\1/p' Shell/App/ShellConfiguration.swift | head -1)"
  if [[ "$selected_mode" == "ads" || "$selected_mode" == "adsWithRemovePurchase" ]]; then
    if grep -A1 -F '<key>NSPrivacyCollectedDataTypes</key>' Shell/Resources/PrivacyInfo.xcprivacy | grep -Fq '<array/>'; then
      fail "Advertising release must declare reviewed collected-data types in PrivacyInfo.xcprivacy"
    fi
  fi
fi

echo "iOS shell validation passed ($mode)."

#!/bin/zsh
# Builds flowstate for TestFlight and uploads it to App Store Connect.
#
#   scripts/testflight.sh              archive, sign and upload
#   scripts/testflight.sh --no-upload  archive and sign only (.ipa in build/testflight)
#
# Uses the "Flowstate TestFlight" scheme: everything except app blocking, which needs Apple's
# Family Controls distribution approval first. Signing uses the certificate and profiles that
# scripts/setup-signing.py created; run that again if signing fails because something expired.
#
# The App Store Connect API key stays outside the repo, in ~/.appstoreconnect/flowstate.env:
#   ASC_KEY_ID=...
#   ASC_ISSUER_ID=...
#   ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="$HOME/.appstoreconnect/flowstate.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE (see the top of this script)." >&2
  exit 1
fi
source "$ENV_FILE"

UPLOAD=true
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=false

TEAM_ID=$(awk '/DEVELOPMENT_TEAM:/ { print $2; exit }' project.yml)
# Every upload needs a higher build number than the last; the date and time always is.
BUILD_NUMBER=$(date +%y%m%d%H%M)
OUT=build/testflight
ARCHIVE="$OUT/Flowstate-$BUILD_NUMBER.xcarchive"
EXPORT="$OUT/export-$BUILD_NUMBER"

mkdir -p "$OUT"
xcodegen generate --quiet

echo "→ Archiving build $BUILD_NUMBER…"
xcodebuild archive \
  -project Flowstate.xcodeproj \
  -scheme "Flowstate TestFlight" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

# The monitor extension only re-blocks apps, and without the Family Controls entitlement it can't,
# so App Store Connect flags it (ITMS-90897). Leave it out until Apple approves the entitlement;
# the export below signs the app again anyway.
rm -rf "$ARCHIVE/Products/Applications/Flowstate.app/PlugIns/FlowstateMonitor.appex"
rmdir "$ARCHIVE/Products/Applications/Flowstate.app/PlugIns" 2>/dev/null || true

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.lukakaroli.flowstate</key><string>flowstate App Store</string>
    <key>com.lukakaroli.flowstate.widgets</key><string>flowstate widgets App Store</string>
  </dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

echo "→ Signing for App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$EXPORT" \
  -quiet

IPA=$(ls "$EXPORT"/*.ipa)
if [[ "$UPLOAD" == false ]]; then
  echo "✓ Signed $IPA"
  exit 0
fi

echo "→ Uploading to App Store Connect…"
# altool looks for AuthKey_<id>.p8 in ~/.appstoreconnect/private_keys.
xcrun altool --upload-app --type ios --file "$IPA" \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "✓ Uploaded build $BUILD_NUMBER. It appears in App Store Connect → TestFlight once Apple has processed it (usually 5–30 min)."

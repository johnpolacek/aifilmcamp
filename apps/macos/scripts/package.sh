#!/bin/bash
# Build a Release copy of AI Film Camp and package it as a DMG for download.
#
# Usage:
#   ./scripts/package.sh                 # ad-hoc signed DMG (Gatekeeper will warn)
#   MACOS_SIGN_IDENTITY="Developer ID Application: ..." \
#   NOTARY_PROFILE=aifilmcamp ./scripts/package.sh   # signed + notarized
#
# Output: .build/dist/AI-Film-Camp.dmg
#
# The website links to the latest GitHub release asset named AI-Film-Camp.dmg:
#   gh release create v0.1.0 .build/dist/AI-Film-Camp.dmg --title "AI Film Camp 0.1.0"
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "package: $*" >&2
  exit 1
}

for required_command in xcodegen xcodebuild hdiutil codesign; do
  command -v "$required_command" >/dev/null \
    || fail "missing command: $required_command"
done

app_name="AI Film Camp"
dmg_name="AI-Film-Camp.dmg"
sign_identity="${MACOS_SIGN_IDENTITY:--}"
derived_data=".build/DerivedData"
dist_dir=".build/dist"
staging_dir="$dist_dir/staging"

echo "Generating the Xcode project..."
xcodegen generate --spec project.yml >/dev/null

echo "Building $app_name (Release)..."
xcodebuild \
  -quiet \
  -project "$app_name.xcodeproj" \
  -scheme "$app_name" \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="$sign_identity" \
  build

app_path="$derived_data/Build/Products/Release/$app_name.app"
[[ -d "$app_path" ]] || fail "the build did not produce $app_path"

if [[ "$sign_identity" != "-" ]]; then
  echo "Signing with $sign_identity..."
  codesign --force --deep --options runtime --timestamp \
    --sign "$sign_identity" "$app_path"
  codesign --verify --deep --strict "$app_path"
fi

echo "Creating the DMG..."
rm -rf "$staging_dir" "$dist_dir/$dmg_name"
mkdir -p "$staging_dir"
cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -quiet -volname "$app_name" -srcfolder "$staging_dir" \
  -ov -format UDZO "$dist_dir/$dmg_name"
rm -rf "$staging_dir"

if [[ "$sign_identity" != "-" ]]; then
  codesign --force --timestamp --sign "$sign_identity" "$dist_dir/$dmg_name"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "$sign_identity" != "-" ]] \
    || fail "notarization requires MACOS_SIGN_IDENTITY (a Developer ID Application certificate)"
  echo "Notarizing with keychain profile $NOTARY_PROFILE..."
  xcrun notarytool submit "$dist_dir/$dmg_name" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dist_dir/$dmg_name"
else
  echo "Skipping notarization (set NOTARY_PROFILE to notarize)."
fi

echo "Packaged: $dist_dir/$dmg_name"

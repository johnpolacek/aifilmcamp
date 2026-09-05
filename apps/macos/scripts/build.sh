#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "build: $*" >&2
  exit 1
}

for required_command in xcodegen xcodebuild swift; do
  command -v "$required_command" >/dev/null \
    || fail "missing command: $required_command"
done

test "$(xcodegen --version)" = "Version: 2.46.0" \
  || fail "XcodeGen 2.46.0 is required"
test "$(xcodebuild -version | sed -n '1p')" = "Xcode 26.6" \
  || fail "Xcode 26.6 is required"

./scripts/check-docs.sh

echo "Building FilmCore..."
swift build --package-path Packages/FilmCore

echo "Building FilmBrain..."
swift build --package-path Packages/FilmBrain

echo "Generating the Xcode project..."
xcodegen generate --spec project.yml >/dev/null

echo "Building AI Film Camp..."
xcodebuild \
  -quiet \
  -project "AI Film Camp.xcodeproj" \
  -scheme "AI Film Camp" \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  build

echo "Build complete."

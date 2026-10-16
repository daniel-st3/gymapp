#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Install full Xcode, open it once, then run this script again.' >&2
  exit 1
fi
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py'
swift test
xcodebuild -project LittleLift.xcodeproj -scheme LittleLift -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LittleLift.xcodeproj -scheme LittleLiftWatch -configuration Debug \
  -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
echo 'Core tests and both simulator builds passed. Device sync, permissions and haptics need paired-device checks.'

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" != Darwin ]; then
  echo 'Open this project on your Mac with Xcode.' >&2
  exit 1
fi
open -a Xcode LittleLift.xcodeproj
echo 'In Xcode, choose the LittleLift scheme and an iPhone simulator, then press Run.'
echo 'For devices, select your signing team on both targets and use unique bundle identifiers.'

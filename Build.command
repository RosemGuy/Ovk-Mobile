#!/bin/bash
set -eu
cd "$(dirname "$0")"
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'Нужен Xcode 5.1.1 в OS X. Команда xcodebuild не найдена.' >&2
    exit 1
fi
set -o pipefail
xcodebuild -project OpenVKClassic.xcodeproj -scheme OpenVKClassic -configuration Debug -sdk iphonesimulator build 2>&1 | tee build.log

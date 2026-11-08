#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-video-sound.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework AVFoundation -framework CoreMedia -framework AudioToolbox \
    -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKVideoSound.m" "$project_dir/tools/VideoSoundTests.m" -o "$test_dir/test"
"$test_dir/test" "$project_dir/OpenVK/AboutSecret.mp4" "$test_dir/merged.mov"

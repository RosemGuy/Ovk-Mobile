#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-local-audio-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cc -c -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKAudioDuration.c" -o "$test_dir/duration.o"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework AVFoundation -framework AudioToolbox \
  -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKLocalAudio.m" "$test_dir/duration.o" \
  "$project_dir/tools/LocalAudioTests.m" -o "$test_dir/local-audio-tests"
"$test_dir/local-audio-tests" "$project_dir/OpenVK/DemoAudio.wav"

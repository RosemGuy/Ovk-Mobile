#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-music-files.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cc -c -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKMediaFormat.c" -o "$test_dir/format.o"
xcrun clang -fobjc-arc -fblocks -framework Foundation -I "$project_dir/OpenVK" \
 "$project_dir/OpenVK/OVKMusicFiles.m" "$project_dir/OpenVK/OVKLanguage.m" "$project_dir/tools/MusicFilesTests.m" "$test_dir/format.o" -o "$test_dir/files"
"$test_dir/files" "$project_dir/OpenVK/DemoAudio.wav"

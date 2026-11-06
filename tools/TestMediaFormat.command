#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-format-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cc -Wall -Wextra -Werror -I "$project_dir/OpenVK" \
 "$project_dir/OpenVK/OVKMediaFormat.c" "$project_dir/tools/MediaFormatTests.c" -o "$test_dir/formats"
"$test_dir/formats" "$project_dir/OpenVK/DemoAudio.wav" wav
"$test_dir/formats" "$project_dir/OpenVK/DemoClip.mp4" mp4

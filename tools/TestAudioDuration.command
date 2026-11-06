#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-duration-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cc -std=c99 -Wall -Wextra -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKAudioDuration.c" "$project_dir/tools/AudioDurationTests.c" -lm -o "$test_dir/test"
"$test_dir/test"

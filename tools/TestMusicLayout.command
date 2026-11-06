#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-player-layout.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cc -std=c99 -Wall -Wextra -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKMusicLayout.c" "$project_dir/tools/MusicLayoutTests.c" -lm -o "$test_dir/test"
"$test_dir/test"

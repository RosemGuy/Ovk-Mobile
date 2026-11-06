#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-feed-layout.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cc -Wall -Wextra -Werror -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKFeedLayout.c" "$project_dir/tools/FeedLayoutTests.c" -lm -o "$test_dir/layout"
"$test_dir/layout"

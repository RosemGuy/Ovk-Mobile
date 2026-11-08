#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-image-requests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -I "$project_dir/OpenVK" \
 "$project_dir/OpenVK/OVKImageRequests.m" "$project_dir/tools/ImageRequestsTests.m" -o "$test_dir/test"
"$test_dir/test"

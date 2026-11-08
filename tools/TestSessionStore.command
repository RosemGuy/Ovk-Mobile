#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-session-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework Security \
 -DSecItemCopyMatching=OVKTestCopyMatching -DSecItemUpdate=OVKTestUpdate \
 -DSecItemAdd=OVKTestAdd -DSecItemDelete=OVKTestDelete \
 -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKAPI.m" "$project_dir/OpenVK/OVKTrust.m" \
 "$project_dir/tools/SessionStoreTests.m" -o "$test_dir/session-tests"
"$test_dir/session-tests"

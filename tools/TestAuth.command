#!/bin/bash
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-auth-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework Security \
    -I "$project_dir/OpenVK" "$project_dir/OpenVK/OVKAPI.m" "$project_dir/OpenVK/OVKTrust.m" \
    "$project_dir/tools/AuthParserTests.m" -o "$test_dir/auth-tests"
"$test_dir/auth-tests"

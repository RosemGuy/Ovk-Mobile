#!/bin/bash
# OS X 10.9 / Xcode 5.1.1. Jailbroken iOS 6-10, 32-bit application.
set -eu
set -o pipefail
cd "$(dirname "$0")"
project_dir="$PWD"
stage='toolchain'
package_dir=''
result_file="$project_dir/Build-result.txt"
cleanup() {
    result=$?
    if [ -n "$package_dir" ]; then rm -rf "$package_dir"; fi
    if [ "$result" -ne 0 ]; then
        echo "FAILED at: $stage (exit $result)" >&2
        echo "Build log: $project_dir/build-ipa.log" >&2
        {
            echo "Ovk-Mobile alpha — IPA build failed"
            echo "Stage: $stage; exit: $result"
            echo "Xcode directory: ${DEVELOPER_DIR:-not selected}"
            echo 'Last build output:'
            if [ -f "$project_dir/build-ipa.log" ]; then tail -n 35 "$project_dir/build-ipa.log"; else echo 'Compilation has not started.'; fi
        } > "$result_file"
        if [ "$(uname -s)" = Darwin ]; then open -a TextEdit "$result_file" >/dev/null 2>&1 || true; fi
    fi
}
trap cleanup EXIT
# Select only this process's toolchain; do not change the system xcode-select setting.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    selected_developer="$(xcode-select -p 2>/dev/null || true)"
    if [ -d "$selected_developer/Platforms/iPhoneOS.platform" ]; then
        export DEVELOPER_DIR="$selected_developer"
    else
        for candidate in /Applications/Xcode*.app/Contents/Developer; do
            if [ -d "$candidate/Platforms/iPhoneOS.platform" ]; then
                export DEVELOPER_DIR="$candidate"; break
            fi
        done
    fi
fi
if ! command -v xcodebuild >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
    echo 'Run inside OS X with Xcode installed.' >&2; exit 1
fi
xcrun --sdk iphoneos --show-sdk-path >/dev/null
# Standalone codesign on Mavericks needs the allocator from the selected Xcode.
export CODESIGN_ALLOCATE="$(xcrun --find codesign_allocate)"
if [ ! -x "$CODESIGN_ALLOCATE" ]; then echo 'codesign_allocate is unavailable.' >&2; exit 1; fi
stage='device build'
echo 'Building for a real iPhone (armv7 / armv7s)...'
set +e
xcodebuild -project OpenVKClassic.xcodeproj -scheme OpenVKClassic \
    -configuration Release -sdk iphoneos \
    ARCHS='armv7 armv7s' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY='' 'CODE_SIGN_IDENTITY[sdk=iphoneos*]=' \
    CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS='' \
    CONFIGURATION_BUILD_DIR="$project_dir/build-ipa/Release-iphoneos" \
    build 2>&1 | tee "$project_dir/build-ipa.log"
build_results=("${PIPESTATUS[@]}")
set -e
if [ "${build_results[0]}" -ne 0 ] || [ "${build_results[1]}" -ne 0 ]; then
    echo 'No IPA was created. Last build messages:' >&2
    tail -n 35 "$project_dir/build-ipa.log" >&2
    exit 1
fi
app_path="$project_dir/build-ipa/Release-iphoneos/OpenVKClassic.app"
if [ ! -f "$app_path/OpenVKClassic" ] || [ ! -f "$app_path/Info.plist" ]; then
    echo 'Device application is missing; read build-ipa.log.' >&2; exit 1
fi
stage='architecture check'
architectures="$(xcrun lipo -archs "$app_path/OpenVKClassic")"
case " $architectures " in *' armv7 '*|*' armv7s '*) ;; *) echo "Wrong architecture: $architectures" >&2; exit 1;; esac
stage='ad-hoc signature'
package_dir="$(mktemp -d "${TMPDIR:-/tmp}/ovk-ipa.XXXXXX")"
mkdir "$package_dir/Payload"
ditto "$app_path" "$package_dir/Payload/OpenVKClassic.app"
codesign --force --sign - "$package_dir/Payload/OpenVKClassic.app"
codesign --verify --verbose=2 "$package_dir/Payload/OpenVKClassic.app"
stage='IPA packaging'
mkdir -p "$project_dir/dist"
(cd "$package_dir" && zip -qry Ovk-Mobile-alpha.ipa Payload)
unzip -tq "$package_dir/Ovk-Mobile-alpha.ipa"
cp "$package_dir/Ovk-Mobile-alpha.ipa" "$project_dir/dist/Ovk-Mobile-alpha.ipa"
echo "IPA created: $project_dir/dist/Ovk-Mobile-alpha.ipa"
echo 'Installation requires AppSync or another compatible jailbreak signing method.'

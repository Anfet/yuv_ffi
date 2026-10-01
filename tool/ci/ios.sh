#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"

for tool_directory in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "$tool_directory" ]]; then
    PATH="$tool_directory:$PATH"
  fi
done
export PATH

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  flutter_command="$(command -v flutter || true)"
  if [[ -n "$flutter_command" ]]; then
    FLUTTER_ROOT="$(cd -- "$(dirname -- "$flutter_command")/.." && pwd)"
  elif [[ -x "$HOME/storage/flutter_3.44/flutter/bin/flutter" ]]; then
    FLUTTER_ROOT="$HOME/storage/flutter_3.44/flutter"
  else
    echo 'Flutter was not found on PATH or at ~/storage/flutter_3.44/flutter.' >&2
    exit 1
  fi
fi
export FLUTTER_ROOT
PATH="$FLUTTER_ROOT/bin:$PATH"
export PATH

cd "$repository_root/example"
flutter pub get

cd "$repository_root/example/ios"
LANG=en_US.UTF-8 pod install

# ML Kit in the example has no arm64 slice for the iOS 26+ Simulator, so pin an iOS 18.x runtime.
simulator_id="$(xcrun simctl list devices available -j | jq -r '
  [.devices | to_entries | sort_by(.key) | reverse | .[]
   | select(.key | startswith("com.apple.CoreSimulator.SimRuntime.iOS-18-"))
   | .value[] | select(.name | startswith("iPhone"))][0].udid // empty')"
if [[ -z "$simulator_id" ]]; then
  echo 'No available iPhone simulator with an iOS 18.x runtime was found (ML Kit has no arm64 slice for the iOS 26+ Simulator).' >&2
  exit 1
fi

xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b

xcodebuild -quiet \
  -workspace Runner.xcworkspace \
  -scheme Pods-Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  CODE_SIGNING_ALLOWED=NO

cd "$repository_root/example"
flutter build ios --simulator --debug --no-codesign
if grep -q 'yuv_ffi' ios/Podfile.lock; then
  echo 'yuv_ffi is listed in example/ios/Podfile.lock: the plugin was not built through Swift Package Manager.' >&2
  exit 1
fi
bash "$repository_root/tool/ci/drive.sh" \
  integration_test/native_app_runtime_smoke_test.dart "$simulator_id" --no-pub

shopt -s nullglob
targets=(integration_test/*_native_test.dart)
if (( ${#targets[@]} == 0 )); then
  echo 'No native integration-test targets were found.' >&2
  exit 1
fi

for target_path in "${targets[@]}"; do
  bash "$repository_root/tool/ci/drive.sh" \
    "$target_path" "$simulator_id" --no-pub
done

flutter build ios --debug --no-codesign

# CocoaPods fallback: build a copy of the example with Swift Package Manager disabled and run only the runtime smoke test.
cocoapods_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/yuv-ffi-ios-cocoapods.XXXXXX")"
trap 'rm -rf "$cocoapods_root"' EXIT
mkdir -p "$cocoapods_root/tool/ci"
rsync -a \
  --exclude build --exclude .dart_tool --exclude Pods --exclude ephemeral \
  "$repository_root/example/" "$cocoapods_root/example/"
cp "$repository_root/tool/ci/drive.sh" "$cocoapods_root/tool/ci/drive.sh"
sed -i.bak \
  -e "s|^    path: \.\./\$|    path: $repository_root|" \
  -e 's|enable-swift-package-manager: true|enable-swift-package-manager: false|' \
  "$cocoapods_root/example/pubspec.yaml"
rm -f "$cocoapods_root/example/pubspec.yaml.bak"
grep -Fq "path: $repository_root" "$cocoapods_root/example/pubspec.yaml"
grep -Fq 'enable-swift-package-manager: false' "$cocoapods_root/example/pubspec.yaml"

cd "$cocoapods_root/example"
flutter pub get
flutter build ios --simulator --debug --no-codesign
if ! grep -q 'yuv_ffi' ios/Podfile.lock; then
  echo 'yuv_ffi is missing from the CocoaPods copy Podfile.lock: the plugin was not built through CocoaPods.' >&2
  exit 1
fi
bash "$cocoapods_root/tool/ci/drive.sh" \
  integration_test/native_app_runtime_smoke_test.dart "$simulator_id" --no-pub

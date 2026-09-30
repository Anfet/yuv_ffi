#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"

cd "$repository_root/example"
flutter pub get

cd "$repository_root/example/ios"
LANG=en_US.UTF-8 pod install

simulator_id="$(xcrun simctl list devices available -j | jq -r '[.devices[][] | select(.name | startswith("iPhone"))][0].udid')"
if [[ -z "$simulator_id" || "$simulator_id" == "null" ]]; then
  echo 'No available iPhone simulator was found.' >&2
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

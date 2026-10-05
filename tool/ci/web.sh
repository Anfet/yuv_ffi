#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
command_log="$(mktemp "${TMPDIR:-/tmp}/yuv-ffi-ci.XXXXXX")"
driver_pid=

run_quiet() {
  local started ended
  started="$(date +%s)"
  if "$@" >"$command_log" 2>&1; then
    ended="$(date +%s)"
    if [[ "${YUV_CI_VERBOSE:-}" == 1 ]]; then cat "$command_log"; fi
    printf 'ok %s (%s s)\n' "$*" "$((ended - started))"
  else
    local status=$?
    printf '%s failed with exit code %s\n' "$*" "$status" >&2
    tail -n 80 "$command_log" >&2
    return "$status"
  fi
}

stop_driver() {
  if [[ -n "$driver_pid" ]] && kill -0 "$driver_pid" 2>/dev/null; then
    kill "$driver_pid" 2>/dev/null || true
    wait "$driver_pid" 2>/dev/null || true
  fi
  driver_pid=
}
trap 'stop_driver; rm -f "$command_log"' EXIT

for tool_directory in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "$tool_directory" ]]; then PATH="$tool_directory:$PATH"; fi
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

chrome="${CHROME_EXECUTABLE:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
chrome_driver="${CHROMEDRIVER_EXE:-$HOME/bin/chromedriver}"
emsdk_root="${EMSDK_ROOT:-$HOME/storage/emsdk-3.1.74}"
emsdk_version=3.1.74

for required_path in "$chrome" "$chrome_driver"; do
  if [[ ! -x "$required_path" ]]; then
    echo "Required Web CI executable is missing: $required_path" >&2
    exit 1
  fi
done

chrome_version="$("$chrome" --version | grep -Eo '[0-9]+(\.[0-9]+){3}' | head -n1)"
driver_version="$("$chrome_driver" --version | grep -Eo '[0-9]+(\.[0-9]+){3}' | head -n1)"
if [[ "${chrome_version%%.*}" != "${driver_version%%.*}" ]]; then
  echo "Chrome $chrome_version and ChromeDriver $driver_version have different major versions" >&2
  exit 1
fi
export CHROME_EXECUTABLE="$chrome"
export CHROMEDRIVER_EXE="$chrome_driver"

start_driver() {
  pkill -f "$chrome_driver" 2>/dev/null || true
  "$chrome_driver" --port=4444 >/dev/null 2>&1 &
  driver_pid=$!
  local attempt
  for attempt in $(seq 1 15); do
    if curl -fsS --max-time 2 http://127.0.0.1:4444/status 2>/dev/null | grep -Eq '"ready" *: *true'; then
      return 0
    fi
    sleep 1
  done
  echo 'ChromeDriver did not become ready on port 4444' >&2
  return 1
}

drive_web() {
  local target="$1"
  shift
  bash "$script_directory/drive.sh" "$target" web-server --browser-name=chrome --headless "$@"
}

assert_web_source_matrix() {
  local combined=all_web_test.dart
  local separate=(
    wasm_bootstrap_web_test.dart
    wasm_loader_lifecycle_web_test.dart
    wasm_swap_nv_atomicity_web_test.dart
    yuv_web_capabilities_web_test.dart
    shader_probe_web_test.dart
  )
  local aggregate=(
    getbytes_contract_web_test.dart
    image_cache_key_web_test.dart
    nv_chroma_order_web_test.dart
    padded_bgra_constructor_web_test.dart
    probe_web_test.dart
    serialization_contract_web_test.dart
    wasm_abi_v1_descriptor_staging_web_test.dart
    wasm_parity_edge_cases_web_test.dart
    web_ownership_regression_web_test.dart
  )
  # Execution source -> sources it must import and invoke (empty: nothing to check).
  local execution_targets=(
    wasm_bootstrap_web_test.dart
    wasm_loader_lifecycle_web_test.dart
    wasm_swap_nv_atomicity_web_test.dart
    fake_loader_web_tests.dart
    shader_probe_web_test.dart
  )
  local baseline_total=64 baseline_sources=14
  local baseline_case_files=(
    getbytes_contract_web_test.dart
    image_cache_key_web_test.dart
    nv_chroma_order_web_test.dart
    padded_bgra_constructor_web_test.dart
    probe_web_test.dart
    serialization_contract_web_test.dart
    shader_probe_web_test.dart
    wasm_abi_v1_descriptor_staging_web_test.dart
    wasm_bootstrap_web_test.dart
    wasm_loader_lifecycle_web_test.dart
    wasm_parity_edge_cases_web_test.dart
    wasm_swap_nv_atomicity_web_test.dart
    web_ownership_regression_web_test.dart
    yuv_web_capabilities_web_test.dart
  )
  local baseline_case_counts=(
    4 1 2 1 1 1 1 29 1 9 2 3 4 5
  )
  local integration_directory="$repository_root/example/integration_test"

  local discovered mapped unmapped missing
  discovered="$(cd "$integration_directory" && ls -1 ./*_web_test.dart | sed 's|^\./||' | grep -Fxv "$combined" | sort)"
  mapped="$(printf '%s\n' "${aggregate[@]}" "${separate[@]}" | sort -u)"
  unmapped="$(comm -23 <(printf '%s\n' "$discovered") <(printf '%s\n' "$mapped"))"
  missing="$(comm -13 <(printf '%s\n' "$discovered") <(printf '%s\n' "$mapped"))"
  if [[ -n "$unmapped" || -n "$missing" ]]; then
    echo "Web source mapping mismatch: unmapped=[$(echo $unmapped)]; missing=[$(echo $missing)]" >&2
    return 1
  fi
  if [[ "$(printf '%s\n' "$discovered" | wc -l | tr -d ' ')" != "$baseline_sources" || "${#baseline_case_files[@]}" != "$baseline_sources" || "${#baseline_case_counts[@]}" != "$baseline_sources" ]]; then
    echo "Web source case baseline must cover all $baseline_sources sources and total $baseline_total cases." >&2
    return 1
  fi
  local total_cases=0 index=0
  while IFS= read -r source; do
    if [[ "$source" != "${baseline_case_files[$index]}" ]]; then
      echo "Web source case baseline mismatch: expected ${baseline_case_files[$index]}, found $source." >&2
      return 1
    fi
    total_cases=$((total_cases + baseline_case_counts[$index]))
    index=$((index + 1))
  done <<< "$discovered"
  if [[ "$total_cases" != "$baseline_total" ]]; then
    echo "Web source case baseline must cover all $baseline_sources sources and total $baseline_total cases." >&2
    return 1
  fi

  local aggregator_path="$integration_directory/$combined" source alias
  if [[ ! -f "$aggregator_path" ]]; then
    echo "Missing combined Web target: $combined" >&2
    return 1
  fi
  for source in "${aggregate[@]}"; do
    alias="$(sed -nE "s|^import[[:space:]]+'${source//./\\.}'[[:space:]]+as[[:space:]]+([A-Za-z0-9_]+);.*|\1|p" "$aggregator_path" | head -n1)"
    if [[ -z "$alias" ]]; then
      echo "Aggregated Web source is not imported and invoked: $source" >&2
      return 1
    fi
    if ! grep -Eq "${alias}\.main\(\);" "$aggregator_path"; then
      echo "Aggregated Web source is not invoked: $source" >&2
      return 1
    fi
  done
  if grep -Eq '\bgroup\(' "$aggregator_path"; then
    echo 'Aggregated Web target must not wrap source mains in groups.' >&2
    return 1
  fi

  # Only the *_web_tests.dart wrapper (fake_loader_web_tests.dart) imports its source.
  local wrapper_path="$integration_directory/fake_loader_web_tests.dart" wrapped=yuv_web_capabilities_web_test.dart
  alias="$(sed -nE "s|^import[[:space:]]+'${wrapped//./\\.}'[[:space:]]+as[[:space:]]+([A-Za-z0-9_]+);.*|\1|p" "$wrapper_path" | head -n1)"
  if [[ -z "$alias" ]] || ! grep -Eq "${alias}\.main\(\);" "$wrapper_path"; then
    echo "Separate Web source is not imported and invoked by fake_loader_web_tests.dart: $wrapped" >&2
    return 1
  fi
  if grep -Eq '\bgroup\(' "$wrapper_path"; then
    echo 'Separate Web target must not wrap source mains in groups: fake_loader_web_tests.dart' >&2
    return 1
  fi

  printf '%s\n' "$combined" "${execution_targets[@]}" | sort
}

cd "$repository_root"

run_quiet flutter config --enable-web
run_quiet flutter pub get

for asset in assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm; do
  if [[ ! -s "$asset" ]]; then
    echo "WASM package asset is missing or empty: $asset" >&2
    exit 1
  fi
done
chmod 644 assets/wasm/yuv_ffi.wasm
git add --refresh -- assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm
if ! flutter pub publish --dry-run >"$command_log" 2>&1; then
  tail -n 40 "$command_log"
  echo 'pub publish dry-run failed' >&2
  exit 1
fi
if ! grep -Eq 'yuv_ffi\.js \(' "$command_log" || ! grep -Eq 'yuv_ffi\.wasm \(' "$command_log"; then
  echo 'pub dry-run did not list both committed WASM assets' >&2
  exit 1
fi

if [[ ! -f "$emsdk_root/emsdk" ]]; then
  # Python 3.9 hosts need an emsdk checkout from the pinned release tag.
  run_quiet git clone https://github.com/emscripten-core/emsdk.git "$emsdk_root"
  run_quiet git -C "$emsdk_root" checkout "$emsdk_version"
fi
run_quiet "$emsdk_root/emsdk" install "$emsdk_version"
run_quiet "$emsdk_root/emsdk" activate "$emsdk_version"
EMSDK_QUIET=1 source "$emsdk_root/emsdk_env.sh"
emcc --version | head -n1
run_quiet sh ./tool/wasm/build_wasm.sh --profile release
# emcc writes the module as executable on macOS; the committed mode is 0644.
chmod 644 assets/wasm/yuv_ffi.wasm
git diff --exit-code -- assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm

(cd example && run_quiet flutter pub get)

targets_output="$(assert_web_source_matrix)"
targets=()
while IFS= read -r target; do targets+=("$target"); done <<< "$targets_output"

start_driver
for target in "${targets[@]}"; do
  drive_web "integration_test/$target"
done
stop_driver

start_driver
drive_web integration_test/reference_web_conversions_test.dart --profile
stop_driver

start_driver
drive_web integration_test/camera_source_web_smoke_test.dart \
  --web-browser-flag=--use-fake-device-for-media-stream \
  --web-browser-flag=--use-fake-ui-for-media-stream
stop_driver

wasm_targets=(
  integration_test/probe_web_test.dart
  integration_test/shader_probe_web_test.dart
  integration_test/all_web_test.dart
)
wasm_started="$(date +%s)"
start_driver
for target in "${wasm_targets[@]}"; do
  drive_web "$target" --wasm
done
stop_driver
wasm_elapsed=$(($(date +%s) - wasm_started))
printf 'Web WASM CI passed: targets=%s; elapsed=%ss.\n' "${#wasm_targets[@]}" "$wasm_elapsed"

git add --refresh -- assets/wasm/yuv_ffi.js assets/wasm/yuv_ffi.wasm

echo "Web CI passed: Chrome $chrome_version; sources=14; integration cases=64; reference matrix=119; camera smoke=1."

#!/usr/bin/env bash
set -euo pipefail
wrapper="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/drive.sh"
repository_root="$(cd -- "$(dirname -- "$wrapper")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/bin" "$scratch/logs"
cat >"$scratch/bin/flutter" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$@" >"$MOCK_RECORD"
cat "$MOCK_STDOUT"
cat "$MOCK_STDERR" >&2
exit "$MOCK_EXIT"
MOCK
chmod +x "$scratch/bin/flutter"
export PATH="$scratch/bin:$PATH" TMPDIR="$scratch/logs"
export MOCK_RECORD="$scratch/argv" MOCK_STDOUT="$scratch/stdout" MOCK_STDERR="$scratch/stderr" MOCK_EXIT=0
target='integration_test/mock target.dart'
device='mock device'
count=0
failures=0
run_case() {
  local name="$1" expected="$2" stdout="$3" stderr="$4" exit_code="$5" actual=0 verdict=0
  printf '%s\n' "$stdout" >"$MOCK_STDOUT"
  printf '%s\n' "$stderr" >"$MOCK_STDERR"
  export MOCK_EXIT="$exit_code"
  bash "$wrapper" "$target" "$device" '--dart-define=label=with space' >"$scratch/result" 2>&1 || actual=$?
  if grep -Fxq "PASS $target on $device" "$scratch/result"; then verdict=1; fi
  count=$((count + 1))
  if { [[ "$expected" == success ]] && (( actual != 0 || verdict != 1 )); } ||
     { [[ "$expected" == failure ]] && (( actual == 0 || verdict != 0 )); }; then
    echo "FAIL $name: expected $expected; actual exit=$actual wrapper PASS=$verdict" >&2
    failures=$((failures + 1))
  fi
  printf '%s\n' "$repository_root/example" drive --driver=test_driver/integration_test.dart "--target=$target" -d "$device" '--dart-define=label=with space' >"$scratch/expected"
  if ! cmp -s "$scratch/expected" "$MOCK_RECORD" || [[ -n "$(ls -A "$TMPDIR")" ]]; then
    echo "FAIL $name: argv/cwd mismatch or temporary log leaked" >&2
    failures=$((failures + 1))
  fi
}
run_case clean success 'All tests passed' '' 0
run_case exit7 failure 'All tests passed' '' 7
run_case missing failure 'ordinary output' '' 0
run_case failed-after failure $'All tests passed\nSome tests failed' '' 0
run_case failed-before failure $'Some tests failed\nAll tests passed' '' 0
run_case details-after failure $'All tests passed\nFailure Details:' '' 0
run_case details-before failure $'Failure Details:\nAll tests passed' '' 0
run_case stderr failure 'All tests passed' 'Some tests failed' 0
run_case recovery success $'Error is ordinary output\nAll tests passed' '' 0
if (( failures > 0 )); then echo "drive_contract Bash: $failures failures / $count cases" >&2; exit 1; fi
echo "drive_contract Bash: $count cases passed"

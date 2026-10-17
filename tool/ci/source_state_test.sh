#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helper="$script_directory/source_state.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

run_case() {
  local name="$1" path="$2" expected_exit="$3" expected_result="$4"
  local output status
  if output="$(bash "$helper" "$path" 2>&1)"; then status=0; else status=$?; fi
  if [[ "$status" -ne "$expected_exit" || "$output" != *"$expected_result"* ]]; then
    printf '%s FAILED\nExpected exit: %s; result: %s\nActual exit: %s; output: %s\n' \
      "$name" "$expected_exit" "$expected_result" "$status" "$output" >&2
    return 1
  fi
  printf '%s Passed\n' "$name"
}

init_repo() {
  git -C "$1" init -q
  git -C "$1" config core.autocrlf false
  git -C "$1" -c core.autocrlf=false -c user.name='Test' -c user.email='test@example.invalid' \
    commit --allow-empty -qm 'initial commit'
}

clean="$scratch/clean"
mkdir "$clean"
init_repo "$clean"
run_case 'clean checkout' "$clean" 0 'CHECKOUT_CLEAN'

tracked_dirty="$scratch/tracked-dirty"
mkdir "$tracked_dirty"
init_repo "$tracked_dirty"
printf 'dirty\n' > "$tracked_dirty/tracked.txt"
git -C "$tracked_dirty" add tracked.txt
git -C "$tracked_dirty" -c core.autocrlf=false -c user.name='Test' -c user.email='test@example.invalid' \
  commit -qm 'tracked file'
printf 'changed\n' > "$tracked_dirty/tracked.txt"
run_case 'tracked dirty checkout' "$tracked_dirty" 1 'CHECKOUT_DIRTY'

untracked_dirty="$scratch/untracked-dirty"
mkdir "$untracked_dirty"
init_repo "$untracked_dirty"
printf 'untracked\n' > "$untracked_dirty/untracked.txt"
run_case 'untracked dirty checkout' "$untracked_dirty" 1 'CHECKOUT_DIRTY'

archive="$scratch/archive"
mkdir "$archive"
run_case 'archive outside repository' "$archive" 0 'ARCHIVE_CLEANLINESS_NOT_APPLICABLE'

parent_repo="$scratch/parent-repository"
mkdir "$parent_repo"
init_repo "$parent_repo"
mkdir "$parent_repo/archive"
run_case 'archive inside parent repository' "$parent_repo/archive" 0 'ARCHIVE_CLEANLINESS_NOT_APPLICABLE'

broken="$scratch/broken-git"
mkdir "$broken"
mkdir "$broken/.git"
run_case 'damaged git metadata' "$broken" 128 'CHECKOUT_ERROR'

printf '6/6 passed\n'

#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo 'Usage: source_state.sh <source-root>' >&2
  exit 2
fi

source_root="$1"
if [[ ! -e "$source_root/.git" ]]; then
  echo 'ARCHIVE_CLEANLINESS_NOT_APPLICABLE'
  exit 0
fi

if status="$(git -C "$source_root" status --porcelain --untracked-files=all)"; then
  :
else
  result=$?
  echo 'CHECKOUT_ERROR' >&2
  exit "$result"
fi

if [[ -n "$status" ]]; then
  echo 'CHECKOUT_DIRTY' >&2
  printf '%s\n' "$status" >&2
  exit 1
fi

echo 'CHECKOUT_CLEAN'

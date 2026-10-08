#!/bin/bash
# Smoke: the wrapper validates the tracked specification on a bare Apple Silicon macOS runner.
# No emulator, sealed golden or credentials; the private tree is a throwaway directory.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

SPEC="specs/hvordan-bruger-jeg-os2faktor.android.json"

fail() {
  printf 'smoke: %s\n' "$*" >&2
  exit 1
}

private_root="$(mktemp -d)"
trap 'rm -rf -- "$private_root"' EXIT

status=0
output="$(GUIDE_CAPTURE_PRIVATE="$private_root" bin/guide-capture validate "$SPEC")" || status=$?
[[ "$status" -eq 0 ]] || fail "validate exited with $status: $output"

# The expected values come from the spec itself, read by jq rather than the Python helper.
jq -e --slurpfile spec "$SPEC" '
  .ok == true and .command == "validate"
  and .slug == $spec[0].slug
  and .start_type == $spec[0].start.type
  and .steps == ($spec[0].steps | length)
' <<<"$output" >/dev/null || fail "unexpected validate result: $output"

grep -q ' command=validate outcome=success$' "$private_root/runtime/logs/guide-capture.log" \
  || fail "validate did not log its success"

printf 'smoke: %s validated (%s)\n' "$SPEC" "$output"

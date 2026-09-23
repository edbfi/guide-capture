# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Guide Capture drives a disposable, encrypted Android emulator to produce redacted screenshots for
Danish education-service guides. No manifest, no build, no dependency lock: a Bash wrapper, a
stdlib-only Python helper, and a Node DevTools helper, all run from the repository root.

## Verify a change

What `prek.toml` runs on every commit (CI runs `prek run --all-files` on macOS 26 ARM64):

```bash
/bin/bash -n bin/guide-capture && /bin/bash -n bin/check-sensitive-files
shellcheck bin/guide-capture bin/check-sensitive-files
python3 -m unittest discover -s tests -v
node --check lib/web_tap.mjs
```

One file, one case, or by name substring:

```bash
python3 -m unittest tests.test_guide_capture
python3 -m unittest tests.test_guide_capture.AnnotationPipelineTests.test_report_records_relative_paths_only
python3 -m unittest discover -s tests -k relative_paths
```

- `AnnotationPipelineTests` shell out to `/opt/homebrew/bin/magick` with no skip guard; without
  ImageMagick they error rather than skip.
- CI also runs `bin/check-sensitive-files --all` (the hook checks only staged paths) and fails on
  any tracked-file mutation (`git diff --exit-code HEAD`).
- `bin/guide-capture doctor` checks the live machine and needs the sealed golden; it is not a test.
- `.agents/rules/python-3_14-core.md` describes a uv/Ruff/basedpyright/pytest stack this repo does
  not use. Keep tests on stdlib `unittest`, add no third-party imports or `pyproject.toml`, and
  match the existing files (both keep `from __future__ import annotations`).

## Ownership

- `bin/guide-capture` owns every side effect: emulator, ADB, `age`, run state, evidence files,
  permissions, logging. Never call `adb`, `emulator`, `age`, or `magick` directly, including from
  your own shell during a task; go through a wrapper command.
- `lib/guide_capture.py` owns pure logic: parsers, schema validation, protected input-script
  generation, AVD rewriting, the ImageMagick command builder. New testable behavior goes here with
  a unit test, not in the wrapper.
- `lib/web_tap.mjs` performs one exact DOM click over Chrome DevTools, gated by a hardcoded HTTPS
  host allowlist that must stay in sync with `docs/login-flow-ishoj.md`.
- `profiles/android-phone.json` is the environment pin; the wrapper derives the system image,
  package IDs, expected versions, and status-bar expectation from it.
- `specs/<slug>.android.json` is the only place capture coordinates live. `validate`/`annotate`
  reject a spec outside `specs/`.

## Adding a wrapper command

Derived from `fdfdc87`, `f2227ce`, `288031d`:

1. Pure logic as a function in `lib/guide_capture.py`; if the wrapper calls it, add a
   `command_<name>` handler (prints one JSON object, returns an exit code) and a subparser in
   `build_parser()`.
2. `command_<name>()` in `bin/guide-capture`, calling `"$PYTHON" "$HELPER" <subcommand>`.
3. A line in `usage()` and an arm in the final `case "$COMMAND_NAME"` dispatch.
4. Unit tests in `tests/test_guide_capture.py`; wrapper-level tests go in `WrapperContractTests`,
   which sets `GUIDE_CAPTURE_PRIVATE` to a temp dir.
5. Document it in `skills/guide-capture/SKILL.md`; credential-touching commands also update
   `docs/login-flow-ishoj.md`.

## Command contract

Every action command writes exactly one JSON object to stdout for success and for handled failure
(`fail` emits `{ok:false, command, error}`); prose goes to stderr. Tests assert the JSON and these
exit codes, so pick the matching one rather than `1`:

| Code | Meaning |
|---:|---|
| `0` | Success, including idempotent `kill` |
| `1` | `doctor` finished with failing checks |
| `2` / `3` | Selector matched zero (or `wait` timed out) / more than one enabled node |
| `64` | Invalid arguments, selector, or specification |
| `65` | Invalid data, profile, run state, or annotation input |
| `66` | Required input or Android package missing |
| `69` | Tool or device unavailable, run already/not active, or state unverifiable |
| `70` | Path-safety refusal |
| `73` | Would overwrite a capture, reviewed output, or sealed archive |

## Gotchas

- Both scripts use `#!/bin/bash`, i.e. macOS Bash 3.2: no `declare -A`, `${var^^}`, or `mapfile`.
  Use 3.2 constructs or move the logic into the Python helper.
- The wrapper overwrites `PATH` and calls every tool through an absolute constant at the top of the
  file. A new tool needs a constant plus an entry in `command_doctor`'s binary loop.
- `boot` exits 69 while `private/runtime/current-run.json` exists. After any error or interruption
  run `bin/guide-capture kill android`; it removes the decrypted run and keeps raw captures and logs.
- Spec and profile schemas reject unknown keys (`_require_exact_keys`). A new spec field needs an
  entry in `validate_annotation_spec` and a consumer, or `validate` rejects the whole file.
- `annotate` exits 73 if reviewed output exists. Archive `private/reviewed-output/<slug>/` beneath
  `private/runtime/`, then run `bin/guide-capture annotate <spec> <retained-run-id>`; never reboot
  to fix image bounds.
- Annotation-report paths go through `_report_path` and stay relative; the report ships beside
  published screenshots and an absolute path leaks the operator's home directory.
- `examples/` is frozen: `test_worked_example_hashes_match_its_report` pins each PNG's SHA-256 to
  `examples/hvordan-bruger-jeg-os2faktor/annotation-report.json`. Replace images and report together.
- A Homebrew upgrade of the emulator or platform-tools makes `doctor` fail by design. Re-pin
  `profiles/android-phone.json` to the verified versions instead of loosening the check.
- Everything sensitive or generated lives under `private/` (or `$GUIDE_CAPTURE_PRIVATE`);
  `bin/check-sensitive-files` rejects commits of `private/`, `.env*` (except `.env.example`),
  `*.age`, `*.ini`, `*.avd/`, keystores, `auth-state*`, and `current-run.json`.
- Secrets never go into arguments, logs, or evidence. The only authorized entry paths are
  `login-ishoj android` and `unlock-os2faktor android`, which read `private/.env` themselves.

## Reference

- `skills/guide-capture/SKILL.md` — binding capture procedure (selectors, evidence, verification,
  shutdown). Read before running a capture or changing any capture flow or wrapper command.
- `skills/guide-capture/references/annotation-redaction.md` — highlight/redaction fit rules and the
  four review passes. Read before editing spec bounds or reviewing images.
- `docs/login-flow-ishoj.md` — standing credential authorization and host allowlist. Read before
  touching `login-ishoj`, `unlock-os2faktor`, `.env` handling, or `lib/web_tap.mjs`.
- `docs/status-bar-fallback.md` — why demo mode is reported unsupported (`live-short-run`). Read
  when status bars differ within a capture set or after a system-image update.
- `CI.md` — CI, Renovate, and PR-policy behavior. Read before editing `.github/workflows/`,
  `renovate.json`, or `prek.toml`.

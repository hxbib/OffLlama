#!/usr/bin/env bash
# Pre-submission verification (run from repo root). Exits non-zero on any hard failure.
#   scripts/verify_submission.sh            # full: model, docs, secrets, Python, Swift in Docker
#   SKIP_SWIFT=1 scripts/verify_submission.sh
# Exit 0 means every required check ran and passed, and the release visibility is PUBLIC.
# Exit 1 means a core check failed. Exit 2 means a required check was skipped or the
# release is incomplete (for example the repo is still PRIVATE).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0
skipped=0
release_incomplete=0
note() { printf '%s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*"; fail=1; }
skip() { printf 'SKIP: %s\n' "$*"; skipped=1; }

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    return 127
  fi
}

file_size() { wc -c < "$1" | tr -d '[:space:]'; }

note "== 1. shipping GGUF sha256 (LEDGER 15)"
want=a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2
f=models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf
if [ -s "$f" ]; then
  size=$(file_size "$f")
  if [ "$size" -lt 1000000 ]; then
    skip "shipping GGUF is an LFS pointer ($size bytes); run git lfs pull"
  elif [ "$size" -ne 807694080 ]; then
    bad "shipping GGUF size is $size; expected 807694080"
  else
    got=$(hash_file "$f" 2>/dev/null) || got=""
    if [ -z "$got" ]; then bad "no shasum or sha256sum available"
    elif [ "$got" = "$want" ]; then note "ok $got"
    else bad "sha mismatch $got"
    fi
  fi
else
  skip "shipping GGUF missing; run git lfs pull"
fi

note "== 2. placeholders left in submission-facing docs (PHONE_* allowed only in FINAL_HOURS.md / DEMO_SCRIPT.md)"
if git grep -nE '\[AFTER_|\[PLACEHOLDER|\[TBD' -- README.md docs/SUBMISSION.md docs/DEMO_SCRIPT.md docs/LAUNCH_CHECKLIST.md 2>/dev/null; then bad "placeholders remain"; else note "ok none"; fi
if git grep -nE '\[PHONE_' -- README.md docs/SUBMISSION.md 2>/dev/null; then bad "[PHONE_*] in README/SUBMISSION"; else note "ok no PHONE_ in README/SUBMISSION"; fi

note "== 3. forbidden claims"
if git grep -niE 'temperature[- ]scal(ed|ing) (is|was) (used|applied)|well[- ]calibrated out of the box|guaranteed (win|placing)' -- README.md docs/ 2>/dev/null | grep -viE 'never|no temperature|not used|not certified|is not used|no scaling'; then bad "forbidden claim wording"; else note "ok"; fi

note "== 4. secrets (tracked files + history)"
pat='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|hf_[A-Za-z0-9]{30,}|ak-[A-Za-z0-9]{20,}|as-[A-Za-z0-9]{20,})'
tracked=$(git grep -lIE "$pat" -- . ':!core/Sources/CSQLite/*' 2>/dev/null)
scan_rc=$?
if [ "$scan_rc" -eq 0 ]; then
  printf '%s\n' "$tracked"
  bad "key-like string in the files above (values redacted)"
elif [ "$scan_rc" -eq 1 ]; then note "ok tracked"
else bad "tracked-file secret scan could not run"
fi
history_count=$(mktemp) || exit 1
git log -p --all -- . ':!core/Sources/CSQLite/*' 2>/dev/null | grep -aEc "$pat" > "$history_count"
scan_status=("${PIPESTATUS[@]}")
if [ "${scan_status[0]}" -ne 0 ] || [ "${scan_status[1]}" -gt 1 ]; then
  bad "history secret scan could not run"
elif [ "$(cat "$history_count")" -gt 0 ]; then
  bad "key-like strings in history (values redacted; inspect with a redacting scanner)"
else note "ok history"
fi
rm -f "$history_count"
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --redact -q 2>/dev/null; then note "ok gitleaks"; else bad "gitleaks findings"; fi
else
  note "gitleaks not installed (optional)"
fi

note "== 5. Python unit tests"
if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not installed"
else
  py_log=$(mktemp)
  if ( cd training && python3 -m unittest discover -s tests ) >"$py_log" 2>&1; then
    tail -3 "$py_log"
    note "ok python tests"
  else
    tail -20 "$py_log"
    bad "python tests"
  fi
  rm -f "$py_log"
fi

if [ -n "${SKIP_SWIFT:-}" ]; then
  skip "Swift check skipped by SKIP_SWIFT=1"
else
  note "== 6. Swift core build + tests"
  swift_log=$(mktemp)
  if command -v swift >/dev/null 2>&1; then
    if ( cd core && swift build && swift test ) >"$swift_log" 2>&1; then
      tail -5 "$swift_log"
      if grep -qE 'Executed [0-9]+ tests, with( [0-9]+ tests? skipped and)? 0 failures' "$swift_log"; then
        note "ok swift"
      else
        bad "no passing Swift test summary"
      fi
    else
      tail -30 "$swift_log"
      bad "swift build/test"
    fi
  elif command -v docker >/dev/null 2>&1; then
    if docker image inspect swift:6.1-noble >/dev/null 2>&1; then
      note "using Docker swift:6.1-noble"
      if docker run --rm -v "$PWD/core:/src" -w /src swift:6.1-noble \
        bash -c 'set -o pipefail; swift build && swift test' >"$swift_log" 2>&1; then
        tail -5 "$swift_log"
        if grep -qE 'Executed [0-9]+ tests, with( [0-9]+ tests? skipped and)? 0 failures' "$swift_log"; then
          note "ok swift (Docker)"
        else
          bad "no passing Swift test summary"
        fi
      else
        tail -30 "$swift_log"
        bad "swift build/test (Docker)"
      fi
    else
      skip "Docker image swift:6.1-noble is not present; pulling it is a large download, do it yourself"
    fi
  else
    skip "no Swift toolchain and no Docker; cannot verify the required core build"
  fi
  rm -f "$swift_log"
fi

note "== 7. repo hygiene"
if git status --short | grep -q .; then note "warning: uncommitted changes present"; else note "ok clean tree"; fi
[ "$(git rev-parse --abbrev-ref HEAD)" = master ] || note "warning: not on master"

note "== 8. release visibility"
vis=$(gh repo view --json visibility --jq '.visibility' 2>/dev/null || true)
case "$vis" in
  PUBLIC) note "ok repository is PUBLIC" ;;
  PRIVATE)
    note "RELEASE INCOMPLETE: repository is PRIVATE; make it public before submission"
    note "This is a release step, not a core build or test failure."
    release_incomplete=1
    ;;
  *)
    note "RELEASE INCOMPLETE: repository visibility could not be checked (gh missing, logged out, or no remote)"
    release_incomplete=1
    ;;
esac

if [ "$fail" -ne 0 ]; then
  note "CORE CHECKS FAILED"
  exit 1
fi
if [ "$skipped" -ne 0 ]; then
  note "INCOMPLETE: a required check was skipped; this is not ALL CHECKS PASSED"
  exit 2
fi
if [ "$release_incomplete" -ne 0 ]; then
  note "CORE CHECKS PASSED; RELEASE INCOMPLETE: repository visibility is not PUBLIC"
  exit 2
fi
note "AUTOMATED CHECKS PASSED: model, document scans, secret scans, core tests, and repository visibility"
note "This script does not verify Xcode, a signed device build, video playback, or form submission."

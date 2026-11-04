#!/usr/bin/env bash
# Pre-submission verification (run from repo root). Exits non-zero on any hard failure.
#   scripts/verify_submission.sh            # full: Swift build+tests in Docker, Python tests, placeholders, secrets, LFS sha
#   SKIP_SWIFT=1 scripts/verify_submission.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0; note() { printf '%s\n' "$*"; }; bad() { printf 'FAIL: %s\n' "$*"; fail=1; }

note "== 1. shipping GGUF sha256 (LEDGER 15)"
want=a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2
f=models/SHIPPING-ep1-Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf
if [ -s "$f" ] && [ "$(stat -c %s "$f")" -gt 100000000 ]; then
  got=$(sha256sum "$f" | cut -d' ' -f1); [ "$got" = "$want" ] && note "ok $got" || bad "sha mismatch $got"
else note "skip (LFS pointer only; run git lfs pull)"; fi

note "== 2. placeholders left in submission-facing docs (PHONE_* allowed only in FINAL_HOURS.md / DEMO_SCRIPT.md)"
if git grep -nE '\[AFTER_|\[PLACEHOLDER|\[TBD' -- README.md docs/SUBMISSION.md docs/DEMO_SCRIPT.md docs/LAUNCH_CHECKLIST.md 2>/dev/null; then bad "placeholders remain"; else note "ok none"; fi
if git grep -nE '\[PHONE_' -- README.md docs/SUBMISSION.md 2>/dev/null; then bad "[PHONE_*] in README/SUBMISSION"; else note "ok no PHONE_ in README/SUBMISSION"; fi

note "== 3. forbidden claims"
if git grep -niE 'temperature[- ]scal(ed|ing) (is|was) (used|applied)|well[- ]calibrated out of the box|guaranteed (win|placing)' -- README.md docs/ 2>/dev/null | grep -viE 'never|no temperature|not used|not certified|is not used|no scaling'; then bad "forbidden claim wording"; else note "ok"; fi

note "== 4. secrets (tracked files + history)"
pat='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|hf_[A-Za-z0-9]{30,}|ak-[A-Za-z0-9]{20,}|as-[A-Za-z0-9]{20,})'
if git grep -nIE "$pat" -- . ':!core/Sources/CSQLite/*' 2>/dev/null | head -3 | grep .; then bad "key-like string in tracked files"; else note "ok tracked"; fi
if git log -p --all -- . ':!core/Sources/CSQLite/*' 2>/dev/null | grep -aEo "$pat" | sort -u | head -3 | grep .; then bad "key-like string in history"; else note "ok history"; fi
command -v gitleaks >/dev/null && { gitleaks detect --no-banner -q 2>/dev/null && note "ok gitleaks" || bad "gitleaks findings"; } || note "gitleaks not installed (optional)"

note "== 5. Python unit tests"
( cd training && python3 -m unittest discover -s tests 2>&1 | tail -3 ) || bad "python tests"

if [ -z "${SKIP_SWIFT:-}" ]; then
  note "== 6. Swift core build + tests (Docker swift:6.1-noble)"
  if command -v swift >/dev/null; then ( cd core && swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E 'Executed|error' | tail -2 ) || bad "swift"
  elif command -v docker >/dev/null; then
    docker run --rm -v "$PWD/core:/src" -w /src swift:6.1-noble bash -c "swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E 'Executed .* tests' | tail -1" | tee /tmp/pg_swift_verify.txt
    grep -qE 'Executed [0-9]+ tests, with 0 failures' /tmp/pg_swift_verify.txt || bad "swift tests"
  else note "skip (no swift, no docker)"; fi
fi

note "== 7. repo hygiene"
git status --short | grep -q . && note "warning: uncommitted changes present" || note "ok clean tree"
[ "$(git rev-parse --abbrev-ref HEAD)" = master ] || note "warning: not on master"
note "== 8. visibility: $(gh repo view --json visibility -q .visibility 2>/dev/null || echo unknown) (must be PUBLIC at submission)"

[ $fail -eq 0 ] && note "ALL CHECKS PASSED" || { note "SOME CHECKS FAILED"; exit 1; }

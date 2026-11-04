#!/usr/bin/env bash
# Apply the signed-off [AFTER_*] values (shipping ep1 Q4_K_M, numbers from LEDGER section 6).
# Usage: TAU=0.90 scripts/apply_after_fill.sh   (Option A, chosen Nov 4 2026; certified threshold)
#        TAU=0.80 scripts/apply_after_fill.sh   (Option B; no certificate at that threshold)
# Idempotent: once the placeholders are gone it changes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TAU:?set TAU=0.90 or TAU=0.80}"
case "$TAU" in
  0.90|0.9)
    TAU_TXT='0.90'
    SHARE_TXT='36% at τ=0.90 (64\/180 calibration rows, 0 errors)'
    BOUND_TXT='≤10.2% (calibration N=180, τ=0.90, 64\/180 handled, 0 errors; assumes exchangeability)'
    ;;
  0.80|0.8)
    TAU_TXT='0.80'
    SHARE_TXT='51% at τ=0.8 (61\/120, frozen test split)'
    BOUND_TXT='not certified at τ=0.80 (the tightest certified bound is ≤10.2% at τ=0.90 on calibration N=180)'
    ;;
  *) echo "TAU must be 0.90 or 0.80" >&2; exit 2 ;;
esac
for f in docs/SUBMISSION.md docs/DEMO_SCRIPT.md README.md; do
  sed -i \
    -e "s/on-device share \[AFTER_COVERAGE\]/on-device share ${SHARE_TXT}/g" \
    -e 's/\[AFTER_ACC_HANDLED\]/92% (56\/61)/g' \
    -e 's/\[AFTER_ACC\]/82% (98\/120)/g' \
    -e 's/\[AFTER_COVERAGE\]/51% at τ=0.8 (61\/120)/g' \
    -e 's/\[AFTER_ECE\]/0.064/g' \
    -e "s/\[AFTER_TAU\]/${TAU_TXT}/g" \
    -e "s/\[AFTER_BOUND\]/${BOUND_TXT}/g" \
    -e 's#\[AFTER_RELIABILITY_CHART\]#`docs/img/reliability_after_floor_test120_v2cc.png`#g' \
    -e 's/\[AFTER_ROUND_SHARES\]/15% untrained to 51% after round 1 (τ=0.8, test N=120)/g' \
    -e 's/\[PLACEHOLDER: N teacher-labeled examples\]/892 Glimmer-labeled examples/g' \
    "$f"
done
if command -v rg >/dev/null; then rg -n '\[AFTER_' docs/SUBMISSION.md docs/DEMO_SCRIPT.md README.md || echo "no AFTER placeholders left"
else grep -n '\[AFTER_' docs/SUBMISSION.md docs/DEMO_SCRIPT.md README.md || echo "no AFTER placeholders left"; fi

#!/usr/bin/env bash
# Apply the signed-off [AFTER_*] values. Usage: TAU=0.90 scripts/apply_after_fill.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TAU:?set TAU=0.90 or TAU=0.80}"
for f in docs/SUBMISSION.md docs/DEMO_SCRIPT.md; do
  sed -i \
    -e 's/\[AFTER_ACC_HANDLED\]/92% (56\/61)/g' \
    -e 's/\[AFTER_ACC\]/82% (98\/120)/g' \
    -e 's/\[AFTER_COVERAGE\]/51% at τ=0.8 (61\/120)/g' \
    -e 's/\[AFTER_ECE\]/0.064/g' \
    -e "s/\[AFTER_TAU\]/${TAU}/g" \
    -e 's/\[AFTER_BOUND\]/≤10.2% (calibration N=180, τ=0.90, 0 errors)/g' \
    -e 's#\[AFTER_RELIABILITY_CHART\]#`docs/img/reliability_after_floor_test120_v2cc.png`#g' \
    -e 's/\[AFTER_ROUND_SHARES\]/15% untrained to 51% after round 1 (τ=0.8, test N=120)/g' \
    "$f"
done
rg -n '\[AFTER_' docs/SUBMISSION.md docs/DEMO_SCRIPT.md || echo "no AFTER placeholders left"

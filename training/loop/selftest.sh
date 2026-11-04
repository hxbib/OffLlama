#!/usr/bin/env bash
# End-to-end check of the closed loop on a Linux box with no phone (≈1 min, $0).
# 1) builds an escalation queue in the EXACT export schema from the pg-cli e2e cases + telemetry DB,
# 2) labels it with a llama-server stand-in teacher (pass a Glimmer server URL to use the real teacher),
# 3) writes phone verdicts and merges a round_train.jsonl, deduped against every eval item.
# Usage: training/loop/selftest.sh [LLAMA_SERVER_URL] [OUTDIR]
set -euo pipefail
cd "$(dirname "$0")/../.."
URL="${1:-http://127.0.0.1:8088}"; OUT="${2:-/tmp/pg_loop_selftest}"; mkdir -p "$OUT"
python3 - "$OUT" <<'EOF'
import json, sys, datetime
out = sys.argv[1]
# The 18 pg-cli e2e cases (core/Sources/pg-cli/main.swift) rendered as escalated decisions with student probs
# (values below are from eval/results/e2e_swift_shipping_tau090_cc.txt, the shipping model at tau 0.9).
cases = [
 ("route", "Network: online\nUser: Move it", ["answer_local","tool","escalate_cloud","clarify"], {"answer_local":0.402,"clarify":0.31,"tool":0.17,"escalate_cloud":0.118}),
 ("route", "Network: online\nUser: Text Maya that I'm on my way", ["answer_local","tool","escalate_cloud","clarify"], {"tool":0.769,"answer_local":0.12,"escalate_cloud":0.07,"clarify":0.041}),
 ("rememberOrNot", "User: What time is it?", ["remember_fact","remember_temporary","no"], {"no":0.491,"remember_temporary":0.3,"remember_fact":0.209}),
 ("memoryConflict", "Existing memory: User lives in Boston\nNew statement: I just moved to Brooklyn last week", ["update","keep_both","ignore_new"], {"update":0.739,"keep_both":0.2,"ignore_new":0.061}),
 ("timing", "User: Every Monday at 9 remind me to submit my timesheet", ["now","at_time","on_arrival","recurring"], {"at_time":0.663,"recurring":0.3,"now":0.02,"on_arrival":0.017}),
 ("nudgeNow", "Trigger: arrive, place: Trader Joe's\nMemory: User needs to buy oat milk", ["nudge","later","skip"], {"nudge":0.68,"later":0.2,"skip":0.12}),
 ("confirmBeforeAct", "Network: online\nUser: Remind me to buy oat milk when I get to the store\nPlanned action: create_reminder title=buy oat milk", ["act","confirm"], {"confirm":0.802,"act":0.198}),
]
with open(f"{out}/decisions_escalated.jsonl", "w") as f:
    for i, (t, ctx, ids, sp) in enumerate(cases, 1):
        f.write(json.dumps({"id": i, "type": t, "context": ctx, "option_ids": ids, "student_probs": sp,
                            "confidence": max(sp.values()), "ts": datetime.datetime.now().isoformat(timespec="seconds"), "source": "linux-e2e"}) + "\n")
print(f"queue: {len(cases)} escalated decisions -> {out}/decisions_escalated.jsonl")
EOF
python3 training/loop/label_queue.py --input "$OUT/decisions_escalated.jsonl" --out "$OUT/queue_labels.jsonl" --teacher student --url "$URL" --scrub
python3 training/loop/verdicts.py --labels "$OUT/queue_labels.jsonl" --out "$OUT/teacher_verdicts.jsonl"
python3 training/loop/merge_round.py --prev training/local_teacher/out/distill_train.jsonl --labels "$OUT/queue_labels.jsonl" --out "$OUT/round_train.jsonl"
echo "selftest OK: $(wc -l < "$OUT/round_train.jsonl") train rows in $OUT/round_train.jsonl"

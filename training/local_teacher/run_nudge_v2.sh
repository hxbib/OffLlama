#!/bin/bash
# Experiment: fix nudgeNow (3/10) with better-covered training scenarios (pg_train _nudge_v2: 7 trigger patterns, nudge/skip/later).
# Chain: dedupe nudge_v2 vs ALL eval items -> wait for RAM (12 GB, same gate as the overnight labeler) -> Glimmer IQ2_M teacher labels
# (label_local --mode train, hint field is NOT used by the labeler) -> build_train on old+new labels -> floor LoRA (bf16/micro 2/grad-ckpt,
# 1 epoch) into a separate dir -> same v2+cc cal+test120 eval as variant floor_nv2. Shipping adapter untouched; pick by CAL split only.
# Gives up (no partial training) if the RAM gate hasn't opened by GATE_GIVEUP. No keys, no network, no spend.
cd "$(dirname "$0")"; PY=/workspace/gate1/.venv/bin/python; G=/workspace/gate1; O=out/nv2; mkdir -p $O
GATE_GIVEUP=${GATE_GIVEUP:-2026-11-02T12:00:00}; DEADLINE=${DEADLINE:-2026-11-02T14:00:00}
log(){ echo "[$(date '+%F %T %Z')] $*"; }
rm -f $O/LABELING_DONE $O/AFTER_DONE $O/AFTER_RC $O/AFTER_EVAL_DONE $O/GAVE_UP
$PY dedupe.py --scenarios out/nudge_v2_scenarios.jsonl --out $O || { log "dedupe failed"; exit 1; }
memok(){ [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -ge 12000000 ]; }
until memok && ! pgrep -f 'llama-server|lora_cpu.py' >/dev/null; do
  [ "$(date +%s)" -ge "$(date -d $GATE_GIVEUP +%s)" ] && { log "RAM gate never opened by $GATE_GIVEUP; giving up"; touch $O/GAVE_UP; exit 2; }
  log "gate wait MemAvail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB"; sleep 300; done
log "gate open; starting Glimmer"
$G/llama.cpp/build/bin/llama-server -m $G/Muse-Glimmer-30B-IQ2_M.gguf -c 2048 -t 8 -np 1 --port 8091 > $O/server_glimmer.log 2>&1 & SP=$!
until curl -sf localhost:8091/health >/dev/null; do sleep 10; kill -0 $SP || { log "server died"; exit 1; }; done
$PY label_local.py --mode train --input $O/scenarios_dedup.jsonl --out $O/nv2_labels.jsonl --deadline $DEADLINE
kill $SP; wait $SP 2>/dev/null; touch $O/LABELING_DONE; log "labeling stopped: $(wc -l < $O/nv2_labels.jsonl) labels"
cat out/train_labels.jsonl $O/nv2_labels.jsonl > $O/all_labels.jsonl
$PY build_train.py $O/all_labels.jsonl out/qc_report.json $O/distill_train.jsonl | tee $O/build_stats.json
while [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -lt 4500000 ]; do log "lora gate wait"; sleep 120; done
log "starting floor LoRA nv2"
/workspace/pg-lora-venv/bin/python lora_cpu.py --train $O/distill_train.jsonl --out out/lora-llama1b-glimmer-nv2 --test ../../eval/gold/gold_test.jsonl \
  --dtype bfloat16 --micro 2 --grad-ckpt --max-hours 3
rc=$?; log "nv2 train rc=$rc"; echo $rc > $O/AFTER_RC; [ $rc -eq 0 ] || exit $rc
sed -e 's#out/lora-llama1b-glimmer-ep2;#out/lora-llama1b-glimmer-nv2;#' -e 's#out/ep2/#out/nv2/#g' -e 's#V=floor_ep2#V=floor_nv2#' \
    run_after_eval_ep2.sh > run_after_eval_nv2.sh
touch $O/AFTER_DONE; bash run_after_eval_nv2.sh; log "nv2 eval rc=$?"

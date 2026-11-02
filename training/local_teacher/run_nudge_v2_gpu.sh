#!/bin/bash
# GPU-PC (WSL Ubuntu-24.04, RTX 3080 Ti) port of run_nudge_v2.sh: same dedupe -> IQ2_M Glimmer labels (same prompt/soft extraction,
# layers offloaded to GPU) -> build_train old+new -> floor LoRA via lora_gpu.py (bf16, bsz 8, lr 2e-4, r16, 1 epoch; no micro/grad-ckpt,
# which only saved RAM) -> v2+cc cal+test120 eval as floor_nv2 (+ cal-fit temperature scaling). No RAM gate.
cd "$(dirname "$0")"; B=/mnt/c/pocket-glimmer-gpu; LL=$B/llama-b12032; PY=/root/venv/bin/python; O=out/nv2; mkdir -p $O
log(){ echo "[$(date '+%F %T %Z')] $*"; }
$PY dedupe.py --scenarios out/nudge_v2_scenarios.jsonl --out $O || { log "dedupe failed"; exit 1; }
log "starting Glimmer IQ2_M"
for NGL in 99 36 28; do
  LD_LIBRARY_PATH=$LL $LL/llama-server -m $B/models/Muse-Glimmer-30B-IQ2_M.gguf -c 2048 -t 8 -np 1 -ngl $NGL -lm none --port 8091 > $O/server_glimmer.log 2>&1 & SP=$!
  ok=1; until curl -sf localhost:8091/health >/dev/null; do sleep 5; kill -0 $SP 2>/dev/null || { ok=0; break; }; done
  [ $ok = 1 ] && break; log "server died at ngl=$NGL"; done
[ $ok = 1 ] || exit 1; log "server up ngl=$NGL"
$PY label_local.py --mode train --input $O/scenarios_dedup.jsonl --out $O/nv2_labels.jsonl
kill $SP; wait $SP 2>/dev/null; touch $O/LABELING_DONE; log "labeling stopped: $(wc -l < $O/nv2_labels.jsonl) labels"
cat out/train_labels.jsonl $O/nv2_labels.jsonl > $O/all_labels.jsonl
$PY build_train.py $O/all_labels.jsonl out/qc_report.json $O/distill_train.jsonl | tee $O/build_stats.json
log "starting floor LoRA nv2 (GPU)"
$PY lora_gpu.py --base $B/models/base --train $O/distill_train.jsonl --out out/lora-llama1b-glimmer-nv2 --test ../../eval/gold/gold_test.jsonl --dtype bfloat16 --max-hours 3
rc=$?; log "nv2 train rc=$rc"; echo $rc > $O/AFTER_RC; [ $rc -eq 0 ] || exit $rc
touch $O/AFTER_DONE; bash gpu_eval.sh floor_nv2 $(pwd)/out/lora-llama1b-glimmer-nv2; log "nv2 eval rc=$?"
bash gpu_eval.sh floor_ship - $B/backup/models/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf; log "shipping re-eval (for TS) rc=$?"
touch $O/ALL_DONE

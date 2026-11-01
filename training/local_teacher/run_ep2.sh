#!/bin/bash
# Experiment: same floor config (bf16, micro 2, grad-ckpt) but 2 epochs, separate out dir so the 1-epoch floor adapter is untouched.
# Model selection between ep1 and ep2 is by the CALIBRATION split only (test120 stays a held-out report).
cd "$(dirname "$0")"; log(){ echo "[$(date '+%F %T %Z')] $*"; }
O=out/ep2; mkdir -p $O; rm -f $O/AFTER_DONE $O/AFTER_EVAL_DONE
while [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -lt 4500000 ]; do log "ep2 gate wait"; sleep 120; done
log "starting CPU LoRA floor ep2"
/workspace/pg-lora-venv/bin/python lora_cpu.py --train out/distill_train.jsonl --out out/lora-llama1b-glimmer-ep2 --test ../../eval/gold/gold_test.jsonl \
  --dtype bfloat16 --micro 2 --grad-ckpt --epochs 2 --max-hours 2
rc=$?; log "ep2 train rc=$rc"; echo $rc > $O/AFTER_RC; [ $rc -eq 0 ] || exit $rc
sed -e 's#LORA=$TD/out/lora-llama1b-glimmer$#LORA=$TD/out/lora-llama1b-glimmer-ep2;#' \
    -e 's#out/AFTER_DONE#out/ep2/AFTER_DONE#g; s#out/AFTER_RC#out/ep2/AFTER_RC#g; s#out/AFTER_EVAL_DONE#out/ep2/AFTER_EVAL_DONE#g' \
    -e 's#V=$(cat out/AFTER_VARIANT 2>/dev/null || echo fp32)#V=floor_ep2#' -e 's#out/server_after.log#out/ep2/server_after.log#' \
    run_after_eval.sh > run_after_eval_ep2.sh
touch $O/AFTER_DONE; bash run_after_eval_ep2.sh; log "ep2 eval rc=$?"

#!/bin/bash
# FLOOR run (not the plan): low-memory CPU LoRA for when the 8 GB gate never opens on the box.
# bf16 weights + micro-batch 2 (grad accum to bsz 8) + gradient checkpointing, ~4 GB. Stops the fp32 gate-waiter first.
cd "$(dirname "$0")"; log(){ echo "[$(date '+%F %T %Z')] $*"; }
pkill -f rerun_lora.sh 2>/dev/null; rm -f out/AFTER_DONE
while [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -lt 4500000 ]; do log "floor gate wait MemAvail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB"; sleep 120; done
log "starting CPU LoRA FLOOR (bf16, micro 2, grad-ckpt)"
/workspace/pg-lora-venv/bin/python lora_cpu.py --train out/distill_train.jsonl --out out/lora-llama1b-glimmer --test ../../eval/gold/gold_test.jsonl \
  --dtype bfloat16 --micro 2 --grad-ckpt --max-hours ${MAXH:-4}
rc=$?; log "lora floor done rc=$rc"; echo $rc > out/AFTER_RC; echo floor > out/AFTER_VARIANT; [ $rc -eq 0 ] && touch out/AFTER_DONE

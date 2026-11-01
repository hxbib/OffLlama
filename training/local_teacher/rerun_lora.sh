#!/bin/bash
# Relaunch CPU LoRA after the 08:09 path crash (labels already built). Memory-gated like run_after.sh.
cd "$(dirname "$0")"; log(){ echo "[$(date '+%F %T %Z')] $*"; }
rm -f out/AFTER_DONE
while [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -lt 8000000 ]; do log "lora gate wait MemAvail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB"; sleep 120; done
log "starting CPU LoRA (rerun)"
/workspace/pg-lora-venv/bin/python lora_cpu.py --train out/distill_train.jsonl --out out/lora-llama1b-glimmer --test ../../eval/gold/gold_test.jsonl --max-hours ${MAXH:-4}
rc=$?; log "lora done rc=$rc"; echo $rc > out/AFTER_RC; [ $rc -eq 0 ] && touch out/AFTER_DONE

#!/bin/bash
# After labeling: build distillation rows, then (memory-gated: no other llama-server/model process, MemAvailable>=9GB)
# CPU LoRA of Llama 3.2 1B with a time budget; scores base vs student on eval/gold/gold_test.jsonl (frozen test split).
cd "$(dirname "$0")"; log(){ echo "[$(date '+%F %T %Z')] $*"; }
until [ -f out/LABELING_DONE ]; do sleep 300; done
/workspace/gate1/.venv/bin/python build_train.py out/train_labels.jsonl out/qc_report.json out/distill_train.jsonl
busy(){ pgrep -f 'llama-server' >/dev/null && return 0; pgrep -af python | grep -E 'gate1|run_eval|run_mobilemoe|transformers' | grep -v local_teacher >/dev/null; }
while busy || [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -lt 9000000 ]; do log "lora gate wait MemAvail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB"; sleep 300; done
log "starting CPU LoRA"
/workspace/pg-lora-venv/bin/python lora_cpu.py --train out/distill_train.jsonl --out out/lora-llama1b-glimmer --test ../../eval/gold/gold_test.jsonl --max-hours ${MAXH:-4}
log "lora done rc=$?"; touch out/AFTER_DONE

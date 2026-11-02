#!/bin/bash
# Spark-teacher retrain: build distill rows (Spark labels: 892 relabeled + extra weak-type train-only rows) -> same FLOOR
# recipe as the shipping adapter (lora_cpu.py bf16, bsz 8 via micro 2 + grad accum, lr 2e-4, r16, 1 epoch, seed 0) ->
# identical v2+cc eval (cal180 + test120, reliability, conformal). Shipping adapter untouched. No keys, no network.
set -uo pipefail; cd "$(dirname "$0")"; log(){ echo "[$(date '+%F %T %Z')] $*"; }
python3 analyze.py > /dev/null && python3 build_train_spark.py out/train_labels_spark.jsonl out/extra_labels_spark.jsonl out/distill_train_spark.jsonl | tee out/build_stats.json
cd ../local_teacher
/workspace/pg-lora-venv/bin/python lora_cpu.py --train ../spark_teacher/out/distill_train_spark.jsonl --out out/lora-llama1b-spark \
  --test ../../eval/gold/gold_test.jsonl --dtype bfloat16 --micro 2 --grad-ckpt --max-hours 3 || { log "train failed"; exit 1; }
bash run_after_eval_spark.sh; log "spark eval rc=$?"

#!/bin/bash
# After the LoRA finishes (AFTER_DONE): merge -> GGUF f16 -> Q4_K_M, then the SAME frozen eval as the headline baseline:
# run_prompt_variants v2+cc on calibration split + test120, reliability.py (10 bins) on test, conformal tau from calibration.
# Writes eval/results/after_<variant>.*; touches out/AFTER_EVAL_DONE. No keys, no network.
set -uo pipefail
cd "$(dirname "$0")"; TD=$(pwd); ROOT=$(cd ../.. && pwd); log(){ echo "[$(date '+%F %T %Z')] $*"; }
LLAMA=/workspace/gate1/llama.cpp; PY=/workspace/pg-lora-venv/bin/python; LORA=$TD/out/lora-llama1b-glimmer
until [ -f out/AFTER_DONE ]; do
  if [ -f out/AFTER_RC ] && [ "$(cat out/AFTER_RC)" != "0" ] && ! pgrep -f lora_cpu.py >/dev/null && [ out/AFTER_RC -nt "$0" ]; then log "lora failed rc=$(cat out/AFTER_RC); abort"; exit 1; fi
  sleep 60; done
V=$(cat out/AFTER_VARIANT 2>/dev/null || echo fp32); log "AFTER_DONE seen (variant=$V); building llama-quantize"
cmake --build $LLAMA/build --target llama-quantize -j6 >/dev/null || { log "quantize build failed"; exit 1; }
export PYTHONPATH=$LLAMA/gguf-py PATH=/workspace/pg-lora-venv/bin:$PATH
bash $ROOT/training/export_gguf.sh /workspace/pg-lora-venv/llama32-1b-instruct $LORA $LLAMA || { log "export failed"; exit 1; }
GG=$LORA-merged/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf; rm -f $LORA-merged/*f16.gguf
pkill -f 'llama-server.*8088' ; $LLAMA/build/bin/llama-server -m $GG --port 8088 -t 6 -c 4096 > out/server_after.log 2>&1 & SP=$!
for i in $(seq 60); do curl -sf localhost:8088/health >/dev/null && break; sleep 5; done
log "server up; running v2+cc on cal + test"
cd $ROOT && python3 eval/experiments/run_prompt_variants.py --sets cal,test --variants v2+cc --out eval/experiments/after_${V}_results.json
python3 - "$V" <<'PY'
import json,sys; v=sys.argv[1]; d=json.load(open(f"eval/experiments/after_{v}_results.json"))
for k,n in (("test/v2+cc","test"),("cal/v2+cc","calibration_split")): json.dump({"rows":d[k]["rows"]},open(f"eval/results/after_{v}.{n}.json","w"))
PY
/workspace/pg-lora-venv/bin/python training/reliability.py eval/results/after_${V}.test.json --out docs/img/reliability_after_${V}_test120_v2cc.png --title "Llama 3.2 1B Q4_K_M, Glimmer-distilled ($V), test N=120" > eval/results/after_${V}.reliability.txt 2>&1
(cd training && python3 -m pg_train.conformal --results ../eval/results/after_${V}.calibration_split.json --alpha 0.05 --delta 0.1 --out ../eval/results/conformal_after_${V}.calib_split.json) > eval/results/after_${V}.conformal.txt 2>&1
kill $SP; cd $TD; touch out/AFTER_EVAL_DONE; log "after-eval done"

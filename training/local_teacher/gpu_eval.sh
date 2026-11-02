#!/bin/bash
# GPU-PC mirror of run_after_eval_ep2.sh: [merge+GGUF Q4_K_M if LORA given] -> v2+cc on cal+test -> reliability -> conformal; then temp scaling (cal-fit) + conformal/reliability again.
# usage: gpu_eval.sh <variant> <lora_dir|-> [existing_q4.gguf]
set -uo pipefail; cd "$(dirname "$0")"; TD=$(pwd); ROOT=$(cd ../.. && pwd); log(){ echo "[$(date '+%F %T %Z')] $*"; }
V=$1; LORA=$2; GG=${3:-}; B=/mnt/c/pocket-glimmer-gpu; LL=$B/llama-b12032; PY=/root/venv/bin/python; export PATH=/root/venv/bin:$PATH
if [ "$LORA" != "-" ]; then
  PYTHONPATH=$B/llama.cpp-src/gguf-py LD_LIBRARY_PATH=$LL bash -c "sed 's#\"\$LLAMA/build/bin/llama-quantize\"#\$LLAMA/llama-quantize#; s#python \"\$LLAMA/convert#python \"$B/llama.cpp-src/convert#' $ROOT/training/export_gguf.sh > /tmp/exp.sh; bash /tmp/exp.sh $B/models/base $LORA $LL" || { log export failed; exit 1; }
  GG=$LORA-merged/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf; rm -f $LORA-merged/*f16.gguf $LORA-merged/model.safetensors
fi
LD_LIBRARY_PATH=$LL $LL/llama-server -m $GG --port 8088 -t 6 -c 4096 -ngl 0 > $TD/out/server_eval_$V.log 2>&1 & SP=$!
for i in $(seq 60); do curl -sf localhost:8088/health >/dev/null && break; sleep 5; done
log "server up ($V); v2+cc cal+test"
cd $ROOT && $PY eval/experiments/run_prompt_variants.py --sets cal,test --variants v2+cc --out eval/experiments/after_${V}_results.json
$PY - "$V" <<'PY'
import json,sys; v=sys.argv[1]; d=json.load(open(f"eval/experiments/after_{v}_results.json"))
for k,n in (("test/v2+cc","test"),("cal/v2+cc","calibration_split")): json.dump({"rows":d[k]["rows"]},open(f"eval/results/after_{v}.{n}.json","w"))
PY
kill $SP
for S in after_${V} after_${V}_ts; do
  [ $S = after_${V}_ts ] && $PY training/temp_scale.py eval/results/after_${V} > eval/results/after_${V}.temperature.json
  $PY training/reliability.py eval/results/$S.test.json --out docs/img/reliability_${S}_test120_v2cc.png --title "Llama 3.2 1B Q4_K_M ($S), test N=120" > eval/results/$S.reliability.txt 2>&1
  (cd training && $PY -m pg_train.conformal --results ../eval/results/$S.calibration_split.json --alpha 0.05 --delta 0.1 --out ../eval/results/conformal_$S.calib_split.json) > eval/results/$S.conformal.txt 2>&1
done; log "eval done $V"

#!/bin/bash
# Quant identity check: run the SAME frozen eval as training/local_teacher/run_after_eval.sh
# (run_prompt_variants v2+cc on cal180 + test120, reliability.py 10 bins, pg_train.conformal alpha .05 delta .1)
# against several GGUFs of the merged ep1 model. Box CPU, no network. Usage: run_quant_eval.sh <label> <gguf>
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); cd $ROOT
LLAMA=/workspace/gate1/llama.cpp; V=$1; GG=$2
pkill -f 'llama-server.*8088'; sleep 1
$LLAMA/build/bin/llama-server -m $GG --port 8088 -t 6 -c 4096 > /tmp/server_$V.log 2>&1 & SP=$!
for i in $(seq 60); do curl -sf localhost:8088/health >/dev/null && break; sleep 2; done
python3 eval/experiments/run_prompt_variants.py --sets cal,test --variants v2+cc --out eval/quant/${V}_results.json
python3 - "$V" <<'PY'
import json,sys; v=sys.argv[1]; d=json.load(open(f"eval/quant/{v}_results.json"))
for k,n in (("test/v2+cc","test"),("cal/v2+cc","calibration_split")): json.dump({"rows":d[k]["rows"]},open(f"eval/quant/{v}.{n}.json","w"))
PY
/workspace/pg-lora-venv/bin/python training/reliability.py eval/quant/$V.test.json --out /tmp/rel_$V.png --title "$V" > eval/quant/$V.reliability.txt 2>&1
(cd training && python3 -m pg_train.conformal --results ../eval/quant/$V.calibration_split.json --alpha 0.05 --delta 0.1 --out ../eval/quant/conformal_$V.calib_split.json) > eval/quant/$V.conformal.txt 2>&1
kill $SP

#!/bin/bash
# Memory-gated overnight run: waits until no gate1 llama-server/python model process runs AND MemAvailable>=12GB
# (checked every 5 min), then serves Glimmer IQ2_M on :8091, runs the eval QC (50 items), then labels the pool.
cd "$(dirname "$0")"; PY=/workspace/gate1/.venv/bin/python; G=/workspace/gate1
DEADLINE=${DEADLINE:-2026-11-01T08:00:00}
log(){ echo "[$(date '+%F %T %Z')] $*"; }
busy(){ pgrep -f 'llama-server' >/dev/null && return 0
        pgrep -af python | grep -E 'gate1|run_eval|run_mobilemoe|transformers' | grep -v local_teacher >/dev/null && return 0; return 1; }
memok(){ [ $(awk '/MemAvailable/{print $2}' /proc/meminfo) -ge 12000000 ]; }
while busy || ! memok; do log "gate wait: busy=$(busy && echo y || echo n) MemAvail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)MB"; sleep 300; done
log "gate open; starting Glimmer"
$G/llama.cpp/build/bin/llama-server -m $G/Muse-Glimmer-30B-IQ2_M.gguf -c 2048 -t 8 -np 1 --port 8091 > out/server_glimmer.log 2>&1 &
SP=$!; trap "kill $SP 2>/dev/null" EXIT
until curl -sf localhost:8091/health >/dev/null; do sleep 10; kill -0 $SP || { log "server died"; exit 1; }; done
log "server up"
$PY label_local.py --mode qc --input out/qc_items.jsonl --out out/qc_labels.jsonl
$PY qc_score.py out/qc_labels.jsonl out/qc_report.json
$PY label_local.py --mode train --input out/scenarios_dedup.jsonl --out out/train_labels.jsonl --deadline $DEADLINE
log "labeling stopped; peak RSS:"; grep VmHWM /proc/$SP/status
kill $SP; wait $SP 2>/dev/null; log "server stopped"
touch out/LABELING_DONE

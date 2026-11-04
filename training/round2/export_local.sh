#!/usr/bin/env bash
# Local CPU fallback for the in-Modal export: merge LoRA (fp16, as training/export_gguf.sh, no trust_remote_code) ->
# convert_hf_to_gguf.py --outtype f16 -> llama-quantize Q4_K_M, llama.cpp 13ec8f6 at /tmp/gencode/llama.cpp.
# usage: export_local.sh <adapter_dir> <out.gguf>
set -euo pipefail
LORA=$1; OUT=$2; BASE=/tmp/gencode/round2/base; PY=/tmp/gencode/torchcpu/bin/python; LL=/tmp/gencode/llama.cpp
TMP=$(mktemp -d /tmp/gencode/round2/merge.XXXX)
$PY - "$BASE" "$LORA" "$TMP" <<'PY'
import sys, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
base, lora, out = sys.argv[1:]
m = AutoModelForCausalLM.from_pretrained(base, dtype=torch.float16)
m = PeftModel.from_pretrained(m, lora).merge_and_unload()
m.save_pretrained(out)
PY
cp $BASE/tokenizer.json $BASE/tokenizer_config.json $BASE/special_tokens_map.json $BASE/generation_config.json "$TMP/"
$PY $LL/convert_hf_to_gguf.py "$TMP" --outtype f16 --outfile "$TMP/f16.gguf"
$LL/build/bin/llama-quantize "$TMP/f16.gguf" "$OUT" Q4_K_M
rm -rf "$TMP"; sha256sum "$OUT"

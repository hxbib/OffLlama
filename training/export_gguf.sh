#!/usr/bin/env bash
# Merge LoRA -> HF fp16 -> GGUF f16 -> Q4_K_M.   usage: export_gguf.sh <base> <lora_dir> [llama.cpp dir]
# NOTE: MobileMoE has no converter in upstream llama.cpp (as of 2026-10-31). Llama 3.2 1B works today.
set -euo pipefail
BASE=$1; LORA=$2; LLAMA=${3:-${LLAMA_CPP:-../llama.cpp}}
OUT=${LORA%/}-merged
python - "$BASE" "$LORA" "$OUT" <<'PY'
import sys, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
base, lora, out = sys.argv[1:]
m = AutoModelForCausalLM.from_pretrained(base, torch_dtype=torch.float16, trust_remote_code=True)
m = PeftModel.from_pretrained(m, lora).merge_and_unload()
m.save_pretrained(out)
try: tok = AutoTokenizer.from_pretrained(lora)
except Exception: tok = AutoTokenizer.from_pretrained(base)  # adapter dir may hold no tokenizer
tok.save_pretrained(out)
PY
python "$LLAMA/convert_hf_to_gguf.py" "$OUT" --outtype f16 --outfile "$OUT/Llama-3.2-1B-PocketGlimmer-Reflex-f16.gguf"
"$LLAMA/build/bin/llama-quantize" "$OUT/Llama-3.2-1B-PocketGlimmer-Reflex-f16.gguf" "$OUT/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf" Q4_K_M
ls -lh "$OUT"/*.gguf
echo "Copy Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf into the app (see app/README.md 'Model files')."

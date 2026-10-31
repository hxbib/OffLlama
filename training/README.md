# training/ — System 1 ("Reflex") distillation

Teachers (Muse Spark Open, Muse Glimmer 30B) answer the same typed multiple-choice questions the phone asks; we keep
their letter **and** probabilities, turn disagreement into "escalate", fine-tune a small Meta student with LoRA r16
(loss on the answer letter only), calibrate its temperature + per-decision tau on held-out, export GGUF Q4.

Stdlib-only Python for everything except SFT (GPU box). Option sets come from Swift (`config/option_sets.json`,
regenerate with `cd ../core && swift run pg-cli dump-sets > ../training/config/option_sets.json`); a test enforces parity.

```bash
python3 -m unittest discover -s tests                     # 6 tests, no network
python3 -m pg_train.scenarios --n 20000 --seed 0 --out out/scenarios.jsonl
python3 -m pg_train.cost --scenarios out/scenarios.jsonl  # prints expected $ per provider; calls nothing

# --- needs spend approval + keys (refuses otherwise) ---
export PG_ALLOW_SPEND=1 BASETEN_API_KEY=... BASETEN_MODEL=... MODAL_API_KEY=... MODAL_BASE_URL=https://<ws>--<app>.modal.run/v1
python3 -m pg_train.label --scenarios out/scenarios.jsonl --teachers spark-baseten,glimmer-modal --out out

# --- GPU box ---
pip install -r requirements-gpu.txt
python -m pg_train.sft_unsloth --base unsloth/Llama-3.2-1B-Instruct --train out/train.jsonl --out out/lora-llama1b --load-4bit   # RTX 3080 Ti
python -m pg_train.sft_unsloth --base facebook/MobileMoE-L-SFT --train out/train.jsonl --out out/lora-mmoe-l --no-unsloth --bf16  # A100
bash export_gguf.sh unsloth/Llama-3.2-1B-Instruct out/lora-llama1b /path/to/llama.cpp

# --- calibrate the exported student (serve it with llama-server first) ---
llama-server -m out/lora-llama1b-merged/reflex-Q4_K_M.gguf --port 8088 -t 4 &
python3 -m pg_train.calibrate --heldout out/heldout.jsonl --target-acc 0.95 --out out/calibration.json
```

Free dry run (local 1B as stand-in teacher, clearly tagged): see `dryrun_report/`.

Notes
- The answer token after `Answer:` is `" A"`…`" H"`, each a single Llama-3 token (verified: `" A"`→362, `" H"`→473).
- MobileMoE-L-SFT: llama.cpp has no MobileMoE converter/graph upstream (gate-1 finding), so its GGUF export is
  blocked; the phone ships Llama 3.2 1B Q4 until that lands. MobileMoE is under the FAIR Noncommercial Research License.
- Remote teachers request `max_tokens=1, logprobs, top_logprobs=20`. If a provider hides logprobs, the letter is parsed
  from text and `probs=null` (merge treats it as one-hot).
- `config/pricing.json` prices are placeholders marked `verified: false`; fill them in from the provider pages.

## Conformal tau (after every distillation round)
After scoring the new student on held-out data (`eval/score_decisions.py --out ...`), recalibrate the escalation threshold with a
finite-sample guarantee (Learn-Then-Test, exact binomial, Bonferroni over a fixed 0.01..0.99 grid):

    python -m pg_train.conformal --results ../eval/results/<round>.json --alpha 0.05 --delta 0.1 --profile out/calibration.json

Status: implemented; the bound tightens as the phone handles more. The script always reports the tightest bound the
sample supports ("error <= X% among self-handled at confidence 1-delta") plus the self-handled rows needed for the target
alpha (`min_rows_needed`; alpha=0.05, delta=0.1: 135 rows with 0 errors, 589 at 2.5% observed error). alpha is a
target, not a pass/fail. Assumption: calibration rows and future decisions are exchangeable (same distribution); a new
student or a shifted user mix needs fresh calibration rows. If nothing certifies, `defaultTau` is set to 1.01 (escalate everything). With alpha=0.05, delta=0.1 a threshold needs at least
135 accepted held-out rows even with zero errors, so the 36-item gold set alone can never certify; use a larger held-out split.

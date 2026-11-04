# The closed loop: phone telemetry → Meta teacher → next Reflex round

This directory makes the dashed arrow in the architecture diagram ("logged decisions → distillation") a runnable
pipeline. Nothing here is synthetic: the input is the JSON Lines file the app exports from its own on-device
telemetry (Settings → "Export decisions for distillation"; `TelemetryLog.exportDistillationQueue`), which contains
**only the decisions the phone escalated** (confidence < τ). Those are exactly the cases where the student was unsure,
so they are the highest-value rows to have a Meta teacher grade: hard-example mining by construction.

```
iPhone  ──export──▶  decisions_escalated.jsonl        (id, type, context, option_ids, student_probs, confidence, ts, source)
                         │
                         ▼  training/loop/label_queue.py   (Muse Glimmer 30B local letter-logprobs  OR  Muse Spark Open k-vote on Baseten)
                     queue_labels.jsonl                  (same rows + teacher soft label, confidence, agreement with student argmax)
                         │
            ┌────────────┴─────────────┐
            ▼                          ▼
 training/loop/verdicts.py      training/loop/merge_round.py
 teacher_verdicts.jsonl          round_train.jsonl = previous train rows + new teacher-graded rows (deduped vs ALL eval items)
 (id, agreed) → import on the         │
 phone: TelemetryLog.                 ▼  training/local_teacher/lora_gpu.py (or training/round2/lora_r2.py on Modal)
 importTeacherVerdicts → the        new adapter → merge → GGUF Q4_K_M → eval/quant/run_quant_eval.sh chain on cal180
 "teacher-agree" telemetry column     │
                                      ▼  gate (LEDGER §0): ships only if the cal180 LTT bound improves; test120 reported once
```

## Privacy
- The export is written to the app's Documents folder and goes nowhere until the user shares the file.
- The queue contains the decision **context** (the user's utterance plus retrieved memory lines). Run `label_queue.py --scrub`
  to pass it through the same masking the app applies before any cloud call (`PrivacyScrubber` semantics re-implemented
  in Python: names, emails, phones, addresses, card numbers → `[PERSON_n]` etc.). The local Glimmer teacher needs no scrubbing.
- The frozen test split is never labeled; `label_queue.py` refuses any input whose name contains `test`.

## Why this is the frontier claim and not just plumbing
Every earlier distillation round in this repo trained on *generated scenarios*. This loop trains on the phone's own
**escalations**: the student picks which examples the teacher sees (selective-prediction hard-example mining), the teacher
grades them, the student is retrained with soft labels, the conformal threshold is recomputed on cal180, and the
teacher-agreement rate flows back into the on-device telemetry chart. Meta's own Glimmer was built by logit distillation
from Muse Spark (Glimmer tech report, arXiv:2610.24628); this extends that chain one more hop, onto the phone, with the
phone choosing the curriculum.

## Commands
```bash
# 1. label the exported queue (pick ONE teacher)
python3 training/loop/label_queue.py --input decisions_escalated.jsonl --out queue_labels.jsonl --teacher glimmer --url http://127.0.0.1:8091 --scrub
python3 training/loop/label_queue.py --input decisions_escalated.jsonl --out queue_labels.jsonl --teacher spark --k 5 --scrub   # needs BASETEN_API_KEY, PG_ALLOW_SPEND=1
# 2. verdicts for the phone (teacher argmax == student argmax ?)
python3 training/loop/verdicts.py --labels queue_labels.jsonl --out teacher_verdicts.jsonl
# 3. merge into the next round's train file (dedupes against every eval item)
python3 training/loop/merge_round.py --prev training/local_teacher/out/distill_train.jsonl --labels queue_labels.jsonl --out round_train.jsonl
# 4. train + export + gate: see training/round2/ (Modal H100) or training/local_teacher/run_after_eval.sh
```
A tiny end-to-end check on the box (no phone): `training/loop/selftest.sh` exports a queue from the `pg-cli e2e`
telemetry DB, labels it with the shipping model as a stand-in teacher, and runs verdicts + merge.

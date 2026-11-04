"""Ephemeral Modal labeler for phone + broader inputs with Muse Glimmer.

Reuses the frozen Glimmer readout (training/round3/glimmer_common.py):
checkpoint chat template, forced Answer suffix, raw next-token logprobs,
exact probes for censored letters. Adds skillPick rendering and a
persistent reservation ledger (phone_budget.py): every launch is
RESERVED and fsynced before dispatch; failures become UNKNOWN and keep
their worst case as committed spend. Never touches pg-glimmer-vllm.

Run only with `modal run`. GPU from PG_PHONE_GPU (B200 default).
"""
import json
import os
import sys
import time
from pathlib import Path

import modal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glimmer_common as G
import phone_budget as B
import phone_contracts as PC

GPU = os.environ.get("PG_PHONE_GPU", "B200")
APP_NAME = "pg-phone-labels-r1-ephem"
MODEL_DIR = "/weights/Muse-Glimmer-30B"
VLLM_VERSION = "0.33.0"
FUNCTION_TIMEOUT_SECONDS = 1200
CHUNK_SIZE = 128

app = modal.App(APP_NAME)
weights = modal.Volume.from_name("pg-glimmer-weights", create_if_missing=False)

image = (
    modal.Image.from_registry("nvidia/cuda:12.8.1-devel-ubuntu24.04", add_python="3.12")
    .uv_pip_install(f"vllm=={VLLM_VERSION}", "huggingface_hub[hf_xet]")
    .env({"HF_XET_HIGH_PERFORMANCE": "1", "VLLM_USE_V1": "1"})
    .add_local_file(str(Path(__file__).resolve().parent / "glimmer_common.py"), "/root/glimmer_common.py")
    .add_local_file(str(Path(__file__).resolve().parent / "phone_contracts.py"), "/root/phone_contracts.py")
    .add_local_file(str(Path(__file__).resolve().parent / "phone_budget.py"), "/root/phone_budget.py")
)

_LLM = None
_META = None


def _load_meta():
    global _META
    if _META is not None:
        return _META
    import hashlib
    template = Path(MODEL_DIR, "chat_template.jinja").read_bytes()
    files = {}
    for name in sorted(os.listdir(MODEL_DIR)):
        p = Path(MODEL_DIR, name)
        if p.is_file():
            files[name] = p.stat().st_size
    _META = {
        "template_sha256": hashlib.sha256(template).hexdigest(),
        "weight_files_bytes": files,
        "complete_marker": Path(MODEL_DIR, ".complete").read_text().strip()
        if Path(MODEL_DIR, ".complete").exists() else None,
    }
    return _META


def _load_llm():
    global _LLM
    if _LLM is not None:
        return _LLM
    sys.path.insert(0, "/root")
    from vllm import LLM
    kwargs = dict(model=MODEL_DIR, tokenizer=MODEL_DIR, trust_remote_code=False,
                  dtype="bfloat16", max_model_len=4096,
                  gpu_memory_utilization=0.92, enable_prefix_caching=True)
    try:
        _LLM = LLM(language_model_only=True, **kwargs)
    except TypeError:
        _LLM = LLM(**kwargs)
    return _LLM


@app.function(image=image, volumes={"/weights": weights}, timeout=300, cpu=4, memory=8192, max_containers=1)
def preflight_meta():
    sys.path.insert(0, "/root")
    import glimmer_common as GC
    from transformers import AutoTokenizer
    meta = _load_meta()
    tok = AutoTokenizer.from_pretrained(MODEL_DIR, trust_remote_code=False)
    checks = {}
    for letter, ids in GC.LETTER_TOKEN_IDS.items():
        checks[letter] = {
            "expected_ids": ids,
            "plain_encode": tok.encode(letter, add_special_tokens=False),
            "decoded": [tok.decode([t]) for t in ids],
        }
    import vllm
    return {**meta, "vllm_version": vllm.__version__, "token_checks": checks}


@app.function(image=image, gpu=GPU, volumes={"/weights": weights},
              timeout=FUNCTION_TIMEOUT_SECONDS, cpu=4, memory=32768,
              max_containers=1, scaledown_window=60, retries=0)
def label_chunk(items, topk):
    sys.path.insert(0, "/root")
    import glimmer_common as GC
    import torch
    from vllm import LLM, SamplingParams, TokensPrompt
    t_start = time.time()
    llm = _load_llm()
    t_ready = time.time()
    tok = llm.get_tokenizer()
    prompts_ids = [tok.encode(it["prompt"], add_special_tokens=False) for it in items]

    def run_topk(k):
        sp = SamplingParams(temperature=1.0, top_p=1.0, max_tokens=1, logprobs=k, detokenize=False)
        outs = llm.generate([TokensPrompt(prompt_token_ids=ids) for ids in prompts_ids], sp)
        tops, sampled = [], []
        for out in outs:
            comp = out.outputs[0]
            d = {}
            if comp.logprobs:
                for tid, lp in comp.logprobs[0].items():
                    d[int(tid)] = float(lp.logprob)
            tops.append(d)
            sampled.append(int(comp.token_ids[0]) if comp.token_ids else None)
        return tops, sampled

    k_used = int(topk)
    try:
        tops, sampled = run_topk(k_used)
    except Exception as e:
        if "logprobs" not in str(e).lower():
            raise
        k_used = 20
        tops, sampled = run_topk(k_used)
    probe_jobs = []
    for idx, it in enumerate(items):
        legal = sorted(t for ids in GC.legal_token_ids(it["letters"]).values() for t in ids)
        for tid in legal:
            if tid not in tops[idx]:
                probe_jobs.append((idx, tid))
    probes = [dict() for _ in items]
    if probe_jobs:
        sp = SamplingParams(temperature=1.0, top_p=1.0, max_tokens=1, prompt_logprobs=20, detokenize=False)
        probe_prompts = [TokensPrompt(prompt_token_ids=prompts_ids[idx] + [tid]) for idx, tid in probe_jobs]
        outs = llm.generate(probe_prompts, sp)
        for (idx, tid), out in zip(probe_jobs, outs):
            entry = out.prompt_logprobs[-1] if out.prompt_logprobs else None
            if entry and tid in entry:
                probes[idx][int(tid)] = float(entry[tid].logprob)
    t_done = time.time()
    results = []
    for idx, it in enumerate(items):
        results.append({
            "key": it["key"], "top_logprobs": tops[idx],
            "topk_min_logprob": min(tops[idx].values()) if tops[idx] else None,
            "topk_returned": len(tops[idx]), "probe_logprobs": probes[idx],
            "sampled_token_id": sampled[idx], "prompt_tokens": len(prompts_ids[idx]),
        })
    meta = _load_meta()
    return {"results": results, "topk_used": k_used,
            "gpu_name": torch.cuda.get_device_name(0),
            "engine_ready_seconds": t_ready - t_start,
            "inference_seconds": t_done - t_ready,
            "container_seconds": t_done - t_start,
            "template_sha256": meta["template_sha256"],
            "weight_files_bytes": meta["weight_files_bytes"]}


def render_phone(type_name, context, candidates, template_text):
    """glimmer_common.render_prompt with skillPick support."""
    import datetime
    import jinja2
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from pg_train import prompts
    option_set = PC.extended_get_set(type_name, candidates)
    env = jinja2.Environment()
    env.globals["raise_exception"] = lambda m: (_ for _ in ()).throw(Exception(m))
    env.globals["strftime_now"] = lambda f: datetime.datetime(2026, 10, 31).strftime(f)
    tmpl = env.from_string(template_text)
    rendered = tmpl.render(
        messages=prompts.chat_messages(option_set, context),
        tools=None, add_generation_prompt=True, bos_token="",
        reasoning_strength="low", current_date=G.CURRENT_DATE)
    return rendered + G.SUFFIX, option_set


def _read_json(path, default):
    p = Path(path)
    return json.loads(p.read_text()) if p.exists() else default


def _write_json(path, data):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(tmp, p)


@app.local_entrypoint()
def main(input_path: str, out_path: str, status_path: str, template_path: str,
         ledger_path: str, phase: str = "phone", cap_usd: float = 100.0,
         chunk_size: int = CHUNK_SIZE, topk: int = 100):
    template_text = Path(template_path).read_text()
    template_hash = G.sha256_text(template_text)
    if template_hash != G.TEMPLATE_SHA256:
        raise SystemExit(f"template hash mismatch: {template_hash}")
    input_sha = G.sha256_file(input_path)
    status = _read_json(status_path, {})
    # Resume artifact must match this exact input + template.
    if status.get("input_sha256") not in (None, input_sha):
        raise SystemExit("status input hash does not match resume input")
    if status.get("template_sha256") not in (None, template_hash):
        raise SystemExit("status template hash does not match resume template")
    # Preflight is a paid launch with its own durable envelope.
    attempt = B.reserve(ledger_path, cap_usd, f"{phase}-preflight",
                        GPU, 300, note="preflight_meta")
    t_meta = time.time()
    try:
        meta = preflight_meta.remote()
    except Exception:
        B.outcome(ledger_path, attempt, False, GPU, time.time() - t_meta,
                  note="preflight_failed_envelope_retained")
        B.write_status(ledger_path, status_path, cap_usd,
                       {"phase": phase, "stopped": "preflight_failed"})
        raise
    B.outcome(ledger_path, attempt, True, GPU, time.time() - t_meta,
              note="preflight_meta_ok_envelope_until_billed")
    if meta["template_sha256"] != G.TEMPLATE_SHA256:
        raise SystemExit("volume template hash mismatch")
    for letter, check in meta["token_checks"].items():
        if check["plain_encode"] != [G.LETTER_TOKEN_IDS[letter][0]]:
            raise SystemExit(f"tokenizer mismatch {letter}")
    rows = [json.loads(l) for l in open(input_path) if l.strip()]
    def norm(r):
        return {"id": r["id"],
                "type": r.get("type") or r.get("reflex_type") or r.get("decision_type"),
                "context": r["context"], "candidates": r.get("candidates")}
    rows = [norm(r) for r in rows]
    prepared = []
    for row in rows:
        prompt, option_set = render_phone(row["type"], row["context"], row.get("candidates"), template_text)
        prepared.append((row, prompt, option_set, G.sha256_text(prompt)))
    # Verify any resumed output belongs to this input/template/options.
    done = G.load_done_index(out_path)
    want = {hh: (row, oset) for row, _, oset, hh in prepared}
    for hh, rec in done.items():
        if hh not in want:
            raise SystemExit(f"resumed output hash {hh[:12]} not in input; refusing")
        row, oset = want[hh]
        if rec.get("option_ids") != G.option_ids_for(oset):
            raise SystemExit(f"resumed output option map mismatch for {rec.get('id')}")
        if rec.get("teacher", {}).get("template_sha256") != G.TEMPLATE_SHA256:
            raise SystemExit("resumed output template mismatch")
    hashes = [p[3] for p in prepared]
    plan = PC.plan_chunks(hashes, set(done), chunk_size)
    by_hash = {p[3]: p for p in prepared}
    todo_n = sum(1 for hh in hashes if hh not in done)
    print(f"phase={phase} rows={len(rows)} done={len(rows)-todo_n} todo={todo_n} chunks={len(plan)} gpu={GPU}", flush=True)
    status.update({"phase": phase, "gpu": GPU, "input_path": input_path,
                   "input_sha256": input_sha, "template_sha256": template_hash,
                   "todo_at_start": todo_n,
                   "command": f"modal run phone_label.py --phase {phase} (input {input_sha[:12]})"})
    B.write_status(ledger_path, status_path, cap_usd, status)
    for start, part_hashes in plan:
        # Re-read durable output: another writer may have completed it.
        done_now = set(G.load_done_index(out_path))
        need = [hh for hh in part_hashes if hh not in done_now]
        if not need:
            continue
        chunk = [by_hash[hh] for hh in need]
        job_key = f"{phase}-" + PC.chunk_job_key(
            input_sha, template_hash, [r["id"] for r, _, _, _ in chunk])
        try:
            attempt = B.reserve(ledger_path, cap_usd, job_key, GPU,
                                FUNCTION_TIMEOUT_SECONDS,
                                note=f"{phase} chunk@{start} items={len(chunk)}")
        except RuntimeError as e:
            print(f"BUDGET STOP {e}", flush=True)
            status["stopped_reason"] = "budget_worst_case_guard"
            B.write_status(ledger_path, status_path, cap_usd, status)
            return
        items = [{"key": hh, "prompt": prompt, "letters": G.letters_for(option_set)}
                 for _, prompt, option_set, hh in chunk]
        t0 = time.time()
        try:
            payload = label_chunk.remote(items, topk)
        except Exception as e:
            B.outcome(ledger_path, attempt, False, GPU, time.time() - t0,
                      note=f"failed envelope retained: {repr(e)[:300]}")
            status.setdefault("failures", []).append(
                {"phase": phase, "chunk_start": start, "job_key": job_key,
                 "error": repr(e)[:500], "at": time.time()})
            B.write_status(ledger_path, status_path, cap_usd, status)
            raise
        wall = time.time() - t0
        if payload["template_sha256"] != G.TEMPLATE_SHA256:
            B.outcome(ledger_path, attempt, False, GPU, wall,
                      note="template mismatch envelope retained")
            raise SystemExit("container template hash mismatch")
        raw_by_key = {r["key"]: r for r in payload["results"]}
        records = []
        for row, prompt, option_set, hh in chunk:
            raw = raw_by_key[hh]
            letters = G.letters_for(option_set)
            agg = G.aggregate_letter_probs(raw["top_logprobs"], raw["probe_logprobs"], letters, raw["topk_min_logprob"])
            top_letter = max(agg["distribution"], key=agg["distribution"].get) if agg["distribution"] else None
            records.append({
                "id": row["id"], "type": row["type"], "candidates": row.get("candidates"),
                "prompt_hash": hh, "prompt_chars": len(prompt), "prompt_tokens": raw["prompt_tokens"],
                "letters": letters, "option_ids": G.option_ids_for(option_set),
                "teacher": {"model_id": G.MODEL_ID, "revision": G.MODEL_REVISION,
                            "template_sha256": payload["template_sha256"],
                            "weight_files_bytes": payload["weight_files_bytes"]},
                "topk_used": payload["topk_used"], "topk_returned": raw["topk_returned"],
                "topk_min_logprob": raw["topk_min_logprob"], "sampled_token_id": raw["sampled_token_id"],
                "letter_token_logprobs": {str(t): lp for t, lp in sorted({**raw["top_logprobs"], **raw["probe_logprobs"]}.items()) if t in G.ALL_LETTER_TOKEN_IDS},
                "status": agg["status"], "usable": agg["usable"], "invalid_reason": agg["reason"],
                "raw_letter_probs": agg["raw_letter_probs"], "distribution": agg["distribution"],
                "letter_mass": agg["letter_mass"], "missing_token_ids": agg["missing_token_ids"],
                "missing_mass_upper": agg["missing_mass_upper"],
                "top_letter": top_letter,
                "top_option_id": (G.option_ids_for(option_set)[letters.index(top_letter)] if top_letter else None),
                "tokens_in": raw["prompt_tokens"], "tokens_out": 1,
                "gpu": GPU, "phase": phase, "labeled_at_epoch": time.time(),
            })
        # Durable output first; only then record the outcome. A settled
        # call without this append is replanned on resume by design.
        G.append_jsonl(out_path, records)
        B.outcome(ledger_path, attempt, True, GPU, wall,
                  note=f"{phase} chunk@{start} envelope until billed")
        status["last_chunk"] = {"start": start, "job_key": job_key,
                                "rows": len(records), "wall_seconds": wall,
                                "gpu_name": payload["gpu_name"]}
        B.write_status(ledger_path, status_path, cap_usd, status)
        print(f"chunk@{start} rows={len(records)} wall={wall:.1f}s committed=${B.totals(ledger_path)['committed_usd']:.4f}", flush=True)
    final = [json.loads(l) for l in open(out_path)] if Path(out_path).exists() else []
    status["summary"] = G.summarize_records(final)
    B.write_status(ledger_path, status_path, cap_usd, status)
    print(json.dumps(status["summary"], indent=2), flush=True)

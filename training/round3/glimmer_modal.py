"""Ephemeral Modal labeler for Muse Glimmer 30B raw letter probabilities.

Run only with `modal run` (never deploy). It does not touch the deployed
pg-glimmer-vllm app or its cache volume. Weights are read from the existing
pg-glimmer-weights volume and never written. Inference is direct batched
vLLM: one forward per prompt, raw next-token logprobs at temperature 1 with
no logit bias, no penalties, and no top-p/top-k truncation. Legal letter
tokens missing from the top-k are completed with exact prompt-logprob
probes, so missing mass is measured, never assumed to be zero.

GPU choice is hardware only and comes from PG_GLIMMER_GPU (B200 default).
The local entrypoint owns selection, resume, the $20 budget ledger, and all
output writes. Remote calls never retry automatically.
"""
import json
import os
import sys
import time
from pathlib import Path

import modal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glimmer_common as G

GPU = os.environ.get("PG_GLIMMER_GPU", "B200")
APP_NAME = "pg-glimmer-labels-r3-ephem"
MODEL_DIR = "/weights/Muse-Glimmer-30B"
VLLM_VERSION = "0.33.0"
FUNCTION_TIMEOUT_SECONDS = 1200
CHUNK_SIZE = 128
TOPK_DEFAULT = 100

app = modal.App(APP_NAME)
weights = modal.Volume.from_name("pg-glimmer-weights", create_if_missing=False)

image = (
    modal.Image.from_registry("nvidia/cuda:12.8.1-devel-ubuntu24.04", add_python="3.12")
    .uv_pip_install(f"vllm=={VLLM_VERSION}", "huggingface_hub[hf_xet]")
    .env({"HF_XET_HIGH_PERFORMANCE": "1", "VLLM_USE_V1": "1"})
    .add_local_file(str(Path(__file__).resolve().parent / "glimmer_common.py"), "/root/glimmer_common.py")
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
        "complete_marker": Path(MODEL_DIR, ".complete").read_text().strip() if Path(MODEL_DIR, ".complete").exists() else None,
    }
    return _META


def _load_llm():
    global _LLM
    if _LLM is not None:
        return _LLM
    sys.path.insert(0, "/root")
    from vllm import LLM

    kwargs = dict(
        model=MODEL_DIR,
        tokenizer=MODEL_DIR,
        trust_remote_code=False,
        dtype="bfloat16",
        max_model_len=4096,
        gpu_memory_utilization=0.92,
        enable_prefix_caching=True,
    )
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


@app.function(
    image=image,
    gpu=GPU,
    volumes={"/weights": weights},
    timeout=FUNCTION_TIMEOUT_SECONDS,
    cpu=4,
    memory=32768,
    max_containers=1,
    scaledown_window=60,
    retries=0,
)
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
        top = tops[idx]
        results.append(
            {
                "key": it["key"],
                "top_logprobs": top,
                "topk_min_logprob": min(top.values()) if top else None,
                "topk_returned": len(top),
                "probe_logprobs": probes[idx],
                "sampled_token_id": sampled[idx],
                "prompt_tokens": len(prompts_ids[idx]),
            }
        )
    meta = _load_meta()
    return {
        "results": results,
        "topk_used": k_used,
        "gpu_name": torch.cuda.get_device_name(0),
        "engine_ready_seconds": t_ready - t_start,
        "inference_seconds": t_done - t_ready,
        "container_seconds": t_done - t_start,
        "template_sha256": meta["template_sha256"],
        "weight_files_bytes": meta["weight_files_bytes"],
    }


def _read_json(path, default):
    p = Path(path)
    if not p.exists():
        return default
    return json.loads(p.read_text())


def _write_json(path, data):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    os.replace(tmp, p)


@app.local_entrypoint()
def main(
    input_path: str,
    out_path: str,
    status_path: str,
    template_path: str,
    phase: str = "preflight",
    per_type: int = 2,
    chunk_size: int = CHUNK_SIZE,
    topk: int = TOPK_DEFAULT,
):
    status = _read_json(status_path, {})
    ledger = G.BudgetLedger(
        cap_usd=status.get("budget", {}).get("cap_usd", G.CAP_USD),
        settled_usd=status.get("budget", {}).get("settled_usd", 0.0),
        calls=status.get("budget", {}).get("calls", []),
    )
    template_text = Path(template_path).read_text()
    template_hash = G.sha256_text(template_text)
    if template_hash != G.TEMPLATE_SHA256:
        raise SystemExit(f"template hash mismatch: {template_hash} != {G.TEMPLATE_SHA256}")
    t_meta = time.time()
    meta = preflight_meta.remote()
    ledger.settle(GPU, time.time() - t_meta, "preflight_meta_cpu_conservative_gpu_rate")
    if meta["template_sha256"] != G.TEMPLATE_SHA256:
        raise SystemExit("volume template hash mismatch")
    for letter, check in meta["token_checks"].items():
        if check["plain_encode"] != [G.LETTER_TOKEN_IDS[letter][0]]:
            raise SystemExit(f"tokenizer plain encode mismatch for {letter}: {check}")
        decoded = [d.strip() for d in check["decoded"]]
        if decoded != [letter, letter, letter]:
            raise SystemExit(f"tokenizer decoded forms mismatch for {letter}: {check}")
    status["preflight_meta"] = {
        "vllm_version": meta["vllm_version"],
        "template_sha256": meta["template_sha256"],
        "complete_marker": meta["complete_marker"],
        "weight_files_bytes": meta["weight_files_bytes"],
    }
    rows = [json.loads(l) for l in open(input_path) if l.strip()]
    if phase == "preflight":
        rows = G.select_balanced(rows, per_type)
    done = G.load_done_index(out_path)
    prepared = []
    for row in rows:
        prompt, option_set = G.render_prompt(row["type"], row["context"], row.get("candidates"), template_text)
        prepared.append((row, prompt, option_set, G.sha256_text(prompt)))
    todo = [p for p in prepared if p[3] not in done]
    print(f"phase={phase} rows={len(rows)} done={len(prepared) - len(todo)} todo={len(todo)} gpu={GPU}", flush=True)
    status.update(
        {
            "phase": phase,
            "gpu": GPU,
            "input_path": input_path,
            "input_sha256": G.sha256_file(input_path),
            "out_path": out_path,
            "template_sha256": template_hash,
            "budget": ledger.to_dict(),
            "todo_at_start": len(todo),
        }
    )
    _write_json(status_path, status)
    for start in range(0, len(todo), chunk_size):
        chunk = todo[start : start + chunk_size]
        if not ledger.can_launch(GPU, FUNCTION_TIMEOUT_SECONDS):
            print("BUDGET STOP: settled + worst-case would exceed cap", flush=True)
            status["stopped_reason"] = "budget_worst_case_guard"
            status["budget"] = ledger.to_dict()
            _write_json(status_path, status)
            return
        items = [
            {"key": h, "prompt": prompt, "letters": G.letters_for(option_set)}
            for _, prompt, option_set, h in chunk
        ]
        t0 = time.time()
        try:
            payload = label_chunk.remote(items, topk)
        except Exception as e:
            status.setdefault("failures", []).append(
                {"phase": phase, "chunk_start": start, "error": repr(e)[:500], "at": time.time()}
            )
            status["budget"] = ledger.to_dict()
            _write_json(status_path, status)
            raise
        wall = time.time() - t0
        entry = ledger.settle(GPU, wall, f"{phase} chunk@{start}")
        if payload["template_sha256"] != G.TEMPLATE_SHA256:
            raise SystemExit("container template hash mismatch")
        raw_by_key = {r["key"]: r for r in payload["results"]}
        records = []
        for row, prompt, option_set, h in chunk:
            raw = raw_by_key[h]
            letters = G.letters_for(option_set)
            agg = G.aggregate_letter_probs(raw["top_logprobs"], raw["probe_logprobs"], letters, raw["topk_min_logprob"])
            top_letter = None
            if agg["distribution"]:
                top_letter = max(agg["distribution"], key=agg["distribution"].get)
            records.append(
                {
                    "id": row["id"],
                    "type": row["type"],
                    "candidates": row.get("candidates"),
                    "prompt_hash": h,
                    "prompt_chars": len(prompt),
                    "prompt_tokens": raw["prompt_tokens"],
                    "letters": letters,
                    "option_ids": G.option_ids_for(option_set),
                    "teacher": {
                        "model_id": G.MODEL_ID,
                        "revision": G.MODEL_REVISION,
                        "template_sha256": payload["template_sha256"],
                        "weight_files_bytes": payload["weight_files_bytes"],
                    },
                    "topk_used": payload["topk_used"],
                    "topk_returned": raw["topk_returned"],
                    "topk_min_logprob": raw["topk_min_logprob"],
                    "sampled_token_id": raw["sampled_token_id"],
                    "letter_token_logprobs": {
                        str(t): lp
                        for t, lp in sorted({**raw["top_logprobs"], **raw["probe_logprobs"]}.items())
                        if t in G.ALL_LETTER_TOKEN_IDS
                    },
                    "status": agg["status"],
                    "usable": agg["usable"],
                    "invalid_reason": agg["reason"],
                    "raw_letter_probs": agg["raw_letter_probs"],
                    "distribution": agg["distribution"],
                    "letter_mass": agg["letter_mass"],
                    "missing_token_ids": agg["missing_token_ids"],
                    "missing_mass_upper": agg["missing_mass_upper"],
                    "top_letter": top_letter,
                    "top_option_id": (
                        G.option_ids_for(option_set)[letters.index(top_letter)] if top_letter else None
                    ),
                    "tokens_in": raw["prompt_tokens"],
                    "tokens_out": 1,
                    "gpu": GPU,
                    "phase": phase,
                    "labeled_at_epoch": time.time(),
                }
            )
        G.append_jsonl(out_path, records)
        done_now = G.load_done_index(out_path)
        status["budget"] = ledger.to_dict()
        status["last_chunk"] = {
            "start": start,
            "rows": len(records),
            "wall_seconds": wall,
            "engine_ready_seconds": payload["engine_ready_seconds"],
            "inference_seconds": payload["inference_seconds"],
            "gpu_name": payload["gpu_name"],
            "settled_entry": entry,
            "done_total": len(done_now),
        }
        status.setdefault("chunks", []).append(status["last_chunk"])
        _write_json(status_path, status)
        print(f"chunk@{start} rows={len(records)} wall={wall:.1f}s settled=${ledger.settled_usd:.4f} done={len(done_now)}", flush=True)
    final = [json.loads(l) for l in open(out_path)] if Path(out_path).exists() else []
    status["summary"] = G.summarize_records(final)
    status["budget"] = ledger.to_dict()
    _write_json(status_path, status)
    print(json.dumps(status["summary"], indent=2), flush=True)

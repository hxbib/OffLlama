"""Parallel phone student training + Q4_K_M export on Modal.

One ephemeral app, own volume pg-phone-training-v1. The base snapshot is
prepared and validated once before any parallel candidate starts.
Every GPU attempt gets its own durable ledger envelope; a failed B200
attempt keeps its envelope and H100 is reserved separately, only for a
verified compatibility/resource failure. Envelopes close only at
provider-bill reconciliation, never at function timing. Candidate
names are validated and finished candidates are never overwritten.

  modal run training/round3/phone_train_modal.py --manifest <json>
No secrets enter containers (base repo is public).
"""
import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import tarfile
import time

import modal

_P = pathlib.Path(__file__).resolve()
ROOT = _P.parents[2] if len(_P.parents) > 2 else pathlib.Path("/repo")
LLAMA_SHA = "13ec8f614cfef964fe97bbf872bc436dbc484a1f"
TRAIN_CPU = 4.0
TRAIN_MEM_MIB = 49152
img = (modal.Image.debian_slim(python_version="3.11")
       .apt_install("git", "cmake", "build-essential", "ca-certificates")
       .pip_install("torch==2.15.0", "transformers==5.22.1", "peft==0.21.2", "accelerate", "sentencepiece", "huggingface_hub", "safetensors", "numpy")
       .run_commands(
           f"git init /opt/llama.cpp && cd /opt/llama.cpp && git remote add origin https://github.com/ggml-org/llama.cpp && git fetch --depth 1 origin {LLAMA_SHA} && git checkout FETCH_HEAD",
           "cd /opt/llama.cpp && cmake -B build -DGGML_NATIVE=OFF -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF -DBUILD_SHARED_LIBS=OFF && cmake --build build --target llama-quantize -j 16",
           "python -m venv /opt/conv && /opt/conv/bin/pip install -q -r /opt/llama.cpp/requirements/requirements-convert_hf_to_gguf.txt")
       .add_local_dir(str(ROOT / "training"), "/repo/training", ignore=["**/out/**", "**/__pycache__/**"]))
vol = modal.Volume.from_name("pg-phone-training-v1", create_if_missing=True)
app = modal.App("pg-phone-train-r1", image=img)

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,60}$")
COMPAT_MARKERS = ("cuda error", "no kernel image", "invalid device function",
                  "unsupported gpu", "blackwell", "sm_100", "sm_120",
                  "device-side assert", "out of memory", "cuda out of memory")


def is_compat_failure(text):
    t = (text or "").lower()
    return any(m in t for m in COMPAT_MARKERS)


def sh(cmd, log):
    t = time.time(); r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    log.append({"cmd": cmd[:300], "rc": r.returncode, "s": round(time.time() - t, 1), "out": r.stdout[-4000:], "err": r.stderr[-3000:]})
    if r.returncode: raise RuntimeError(f"rc={r.returncode}: {cmd[:200]}\n{r.stderr[-2000:]}")
    return r.stdout


def validate_base():
    base = pathlib.Path("/vol/base")
    need = ["config.json", "tokenizer.json", "tokenizer_config.json"]
    files = sorted(p.name for p in base.glob("*") if p.is_file())
    missing = [n for n in need if n not in files]
    shards = [n for n in files if n.endswith(".safetensors")]
    if missing or not shards:
        raise RuntimeError(f"base incomplete: missing={missing} shards={shards}")
    return {"files": files,
            "safetensors": shards,
            "bytes": {n: (base / n).stat().st_size for n in files}}


@app.function(timeout=1800, volumes={"/vol": vol}, cpu=4.0, memory=8192, max_containers=1)
def prepare_base():
    vol.reload()
    marker = pathlib.Path("/vol/base/BASE_VALIDATED.json")
    if pathlib.Path("/vol/base/DONE").exists() and marker.exists():
        return json.loads(marker.read_text())
    from huggingface_hub import snapshot_download
    snapshot_download("unsloth/Llama-3.2-1B-Instruct", local_dir="/vol/base",
                      allow_patterns=["*.json", "*.safetensors", "tokenizer*", "*.model"])
    info = validate_base()
    info["repo"] = "unsloth/Llama-3.2-1B-Instruct"
    marker.write_text(json.dumps(info, indent=1))
    open("/vol/base/DONE", "w").write(time.ctime())
    vol.commit()
    return info


def _train(name, flags, train_text, cal_text, meta):
    if not NAME_RE.match(name):
        raise ValueError(f"unsafe candidate name: {name}")
    t0 = time.time(); log = []; out = {"name": name, "flags": flags, **meta}
    gguf_path = pathlib.Path(f"/vol/gguf/{name}.gguf")
    log_path = pathlib.Path(f"/vol/logs/{name}.json")
    try:
        vol.reload()
        if gguf_path.exists() and log_path.exists():
            prev = json.loads(log_path.read_text())
            if prev.get("ok"):
                out.update(prev); out["resumed_skip"] = True
                return out
            raise RuntimeError(f"candidate {name} exists but not ok; refusing overwrite")
        if not pathlib.Path("/vol/base/BASE_VALIDATED.json").exists():
            raise RuntimeError("base not prepared; run prepare_base first")
        validate_base()
        out["gpu"] = subprocess.run("nvidia-smi --query-gpu=name --format=csv,noheader", shell=True, capture_output=True, text=True).stdout.strip()
        open("/tmp/train.jsonl", "w").write(train_text); open("/tmp/cal.jsonl", "w").write(cal_text)
        o = sh("cd /repo/training/round3 && python phone_train.py --base /vol/base --train /tmp/train.jsonl --out /tmp/lora --test /tmp/cal.jsonl --skip-before --max-hours 1.2 "
               + " ".join(flags), log)
        out["train_result"] = json.loads(o.strip().splitlines()[-1]); out["train_s"] = round(time.time() - t0, 1)
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as t: t.add("/tmp/lora", arcname=f"lora-{name}")
        out["adapter_tgz"] = buf.getvalue()
        sh("""python - <<'PY'
import torch
from transformers import AutoModelForCausalLM
from peft import PeftModel
m = AutoModelForCausalLM.from_pretrained('/vol/base', dtype=torch.float16)
m = PeftModel.from_pretrained(m, '/tmp/lora').merge_and_unload()
m.save_pretrained('/tmp/merged')
PY
cp /vol/base/tokenizer.json /vol/base/tokenizer_config.json /vol/base/special_tokens_map.json /vol/base/generation_config.json /tmp/merged/""", log)
        sh("/opt/conv/bin/python /opt/llama.cpp/convert_hf_to_gguf.py /tmp/merged --outtype f16 --outfile /tmp/f16.gguf", log)
        os.makedirs("/vol/gguf", exist_ok=True)
        sh(f"/opt/llama.cpp/build/bin/llama-quantize /tmp/f16.gguf /vol/gguf/{name}.gguf Q4_K_M", log)
        sh(f"mkdir -p /vol/lora && cp -r /tmp/lora /vol/lora/{name}", log)
        hh = hashlib.sha256()
        with open(f"/vol/gguf/{name}.gguf", "rb") as f:
            for blk in iter(lambda: f.read(1 << 24), b""): hh.update(blk)
        out["gguf_sha256"] = hh.hexdigest(); out["gguf_bytes"] = os.path.getsize(f"/vol/gguf/{name}.gguf"); out["ok"] = True
    except Exception as e:
        out["ok"] = False; out["error"] = str(e)[-3000:]
    out["total_s"] = round(time.time() - t0, 1); out["log"] = log
    os.makedirs("/vol/logs", exist_ok=True)
    json.dump({k: v for k, v in out.items() if k != "adapter_tgz"}, open(f"/vol/logs/{name}.json", "w"), indent=1); vol.commit()
    return out


@app.function(gpu="B200", timeout=2400, volumes={"/vol": vol}, cpu=TRAIN_CPU, memory=TRAIN_MEM_MIB, max_containers=8, retries=0)
def train_b200(name: str, flags: list, train_text: str, cal_text: str, meta: dict):
    return _train(name, flags, train_text, cal_text, meta)


@app.function(gpu="H100", timeout=2400, volumes={"/vol": vol}, cpu=TRAIN_CPU, memory=TRAIN_MEM_MIB, max_containers=8, retries=0)
def train_h100(name: str, flags: list, train_text: str, cal_text: str, meta: dict):
    return _train(name, flags, train_text, cal_text, meta)


@app.local_entrypoint()
def main(manifest: str):
    import sys as _s
    _s.path.insert(0, str(_P.parent))
    import phone_budget as B
    man = json.loads(pathlib.Path(manifest).read_text())
    ledger, status_path, cap = man["ledger"], man["status"], float(man.get("cap", 100.0))
    mem_gib = TRAIN_MEM_MIB // 1024
    # Prepare the immutable base once, under its own envelope.
    base_attempt = B.reserve(ledger, cap, "train-prepare-base", "B200", 1800,
                             mem_gib=8, cpu_cores=4, note="prepare_base once")
    t0 = time.time()
    try:
        base_info = prepare_base.remote()
    except Exception as e:
        B.outcome(ledger, base_attempt, False, "B200", time.time() - t0, mem_gib=8,
                  note=f"prepare_base failed: {repr(e)[:300]}")
        raise
    B.outcome(ledger, base_attempt, True, "B200", time.time() - t0, mem_gib=8,
              note="prepare_base ok envelope until billed")
    print(f"base ready: {base_info.get('repo')} shards={base_info.get('safetensors')}", flush=True)
    jobs = []
    for cand in man["candidates"]:
        if not NAME_RE.match(cand["name"]):
            raise SystemExit(f"unsafe candidate name {cand['name']}")
        train_text = pathlib.Path(cand["train"]).read_text()
        cal_text = pathlib.Path(cand["cal"]).read_text()
        meta = {"train_sha256": hashlib.sha256(train_text.encode()).hexdigest(),
                "train_rows": train_text.count("\n"),
                "cal_sha256": hashlib.sha256(cal_text.encode()).hexdigest(),
                "seed": cand.get("seed", 0)}
        jobs.append((cand, train_text, cal_text, meta))
    results = {}
    pending = []
    # Reserve every B200 attempt before any dispatch.
    attempts = {}
    for cand, tt, ct, m in jobs:
        attempts[cand["name"]] = B.reserve(
            ledger, cap, f"train-{cand['name']}-B200", "B200", 2400,
            mem_gib=mem_gib, cpu_cores=4, note=f"train {cand['name']} B200")
        pending.append((cand, tt, ct, m))
    outs = list(train_b200.starmap(
        [(c["name"], c.get("flags", []), tt, ct, m) for c, tt, ct, m in pending],
        return_exceptions=True))
    retry = []
    for (cand, tt, ct, m), o in zip(pending, outs):
        att = attempts[cand["name"]]
        if isinstance(o, Exception):
            B.outcome(ledger, att, False, "B200", None,
                      note=f"exception envelope retained: {repr(o)[:300]}")
            if is_compat_failure(repr(o)):
                retry.append((cand, tt, ct, m))
            else:
                print(f"{cand['name']} B200 failed (no fallback): {repr(o)[:200]}", flush=True)
            continue
        secs = float(o.get("total_s") or 0)
        B.outcome(ledger, att, bool(o.get("ok")), "B200", secs,
                  mem_gib=mem_gib, note="train envelope until billed")
        if o.get("ok"):
            o.pop("adapter_tgz", None); results[cand["name"]] = o
            print(cand["name"], "ok B200", o.get("gpu"), o.get("gguf_sha256", "")[:16], flush=True)
        elif is_compat_failure(o.get("error", "")):
            retry.append((cand, tt, ct, m))
        else:
            print(f"{cand['name']} B200 failed (no fallback): {str(o.get('error'))[:200]}", flush=True)
    for cand, tt, ct, m in retry:
        att = B.reserve(ledger, cap, f"train-{cand['name']}-H100", "H100", 2400,
                        mem_gib=mem_gib, cpu_cores=4,
                        note=f"train {cand['name']} H100 compat fallback")
        try:
            o = train_h100.remote(cand["name"], cand.get("flags", []), tt, ct, m)
        except Exception as e:
            B.outcome(ledger, att, False, "H100", None,
                      note=f"h100 exception retained: {repr(e)[:300]}")
            continue
        B.outcome(ledger, att, bool(o.get("ok")), "H100",
                  float(o.get("total_s") or 0), mem_gib=mem_gib,
                  note="train envelope until billed")
        if o.get("ok"):
            o.pop("adapter_tgz", None); results[cand["name"]] = o
            print(cand["name"], "ok H100 fallback", o.get("gpu"), flush=True)
    B.write_status(ledger, status_path, cap, {"train_results": {
        k: {"ok": v.get("ok"), "gpu": v.get("gpu"), "sha": v.get("gguf_sha256"),
            "steps": (v.get("train_result") or {}).get("steps_done")}
        for k, v in results.items()}})
    pathlib.Path(man["results"]).write_text(json.dumps(results, indent=1))
    print(f"done {len(results)}/{len(jobs)} committed=${B.totals(ledger)['committed_usd']:.4f}", flush=True)

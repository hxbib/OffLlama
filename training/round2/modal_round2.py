"""Round-2 LoRA sweep on Modal (H100, A100-80GB fallback). One GPU container per variant, run in parallel.
Each container: train (training/round2/lora_r2.py) -> merge fp16 (as training/export_gguf.sh) -> convert_hf_to_gguf.py --outtype f16
-> llama-quantize Q4_K_M (llama.cpp pinned to the box build 13ec8f6, converter in its own venv with llama.cpp's pinned requirements).
Outputs on Volume pg-round2: /gguf/<V>.gguf, /lora/<V>/, /logs/<V>.json. Base weights: HF unsloth/Llama-3.2-1B-Instruct (ungated
mirror of meta-llama/Llama-3.2-1B-Instruct, what the PC kit used; LEDGER 11), fetched once into the Volume.
  modal run training/round2/modal_round2.py::warm                       # build image, fetch base, tiny end-to-end smoke run
  modal run training/round2/modal_round2.py --train training/round2/out/r2a_train.jsonl --variants V0,V1,...
No secrets are passed into the containers (HF repo is public)."""
import io, json, os, pathlib, subprocess, tarfile, time, hashlib
import modal
_P = pathlib.Path(__file__).resolve()
ROOT = _P.parents[2] if len(_P.parents) > 2 else pathlib.Path("/repo")
LLAMA_SHA = "13ec8f614cfef964fe97bbf872bc436dbc484a1f"
img = (modal.Image.debian_slim(python_version="3.11")
       .apt_install("git", "cmake", "build-essential", "ca-certificates")
       .pip_install("torch==2.15.0", "transformers==5.22.1", "peft==0.21.2", "accelerate", "sentencepiece", "huggingface_hub", "safetensors", "numpy")
       .run_commands(
           f"git init /opt/llama.cpp && cd /opt/llama.cpp && git remote add origin https://github.com/ggml-org/llama.cpp && git fetch --depth 1 origin {LLAMA_SHA} && git checkout FETCH_HEAD",
           "cd /opt/llama.cpp && cmake -B build -DGGML_NATIVE=OFF -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF -DBUILD_SHARED_LIBS=OFF && cmake --build build --target llama-quantize -j 16",
           "python -m venv /opt/conv && /opt/conv/bin/pip install -q -r /opt/llama.cpp/requirements/requirements-convert_hf_to_gguf.txt")
       .add_local_dir(str(ROOT / "training"), "/repo/training", ignore=["**/out/**", "**/__pycache__/**", "**/out"]))
vol = modal.Volume.from_name("pg-round2", create_if_missing=True)
app = modal.App("pg-round2", image=img)
GPU = ["H100", "A100-80GB"]  # 2026-11-04: every Modal GPU type returns "Please add a payment method" on this account -> CPU containers


def sh(cmd, log):
    t = time.time(); r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    log.append({"cmd": cmd[:300], "rc": r.returncode, "s": round(time.time() - t, 1), "out": r.stdout[-4000:], "err": r.stderr[-3000:]})
    if r.returncode: raise RuntimeError(f"rc={r.returncode}: {cmd[:200]}\n{r.stderr[-2000:]}")
    return r.stdout


def ensure_base():
    if os.path.exists("/vol/base/DONE"): return
    from huggingface_hub import snapshot_download
    snapshot_download("unsloth/Llama-3.2-1B-Instruct", local_dir="/vol/base",
                      allow_patterns=["*.json", "*.safetensors", "tokenizer*", "*.model"])
    open("/vol/base/DONE", "w").write(time.ctime()); vol.commit()


def _train(name, flags, train_text, cal_text):
    t0 = time.time(); log = []; out = {"name": name, "flags": flags}
    try:
        vol.reload(); ensure_base()
        out["gpu"] = subprocess.run("nvidia-smi --query-gpu=name --format=csv,noheader", shell=True, capture_output=True, text=True).stdout.strip()
        open("/tmp/train.jsonl", "w").write(train_text); open("/tmp/cal.jsonl", "w").write(cal_text)
        o = sh("cd /repo/training/round2 && python lora_r2.py --base /vol/base --train /tmp/train.jsonl --out /tmp/lora --test /tmp/cal.jsonl --skip-before --max-hours 1.2 "
               + " ".join(flags), log)
        out["train_result"] = json.loads(o.strip().splitlines()[-1]); out["train_s"] = round(time.time() - t0, 1)
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as t: t.add("/tmp/lora", arcname=f"lora-{name}")
        out["adapter_tgz"] = buf.getvalue()  # returned even if the GGUF export below fails (local CPU export fallback)
        sh("""python - <<'PY'
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
m = AutoModelForCausalLM.from_pretrained('/vol/base', dtype=torch.float16)
m = PeftModel.from_pretrained(m, '/tmp/lora').merge_and_unload()
m.save_pretrained('/tmp/merged')
PY
cp /vol/base/tokenizer.json /vol/base/tokenizer_config.json /vol/base/special_tokens_map.json /vol/base/generation_config.json /tmp/merged/""", log)
        sh("/opt/conv/bin/python /opt/llama.cpp/convert_hf_to_gguf.py /tmp/merged --outtype f16 --outfile /tmp/f16.gguf", log)
        os.makedirs("/vol/gguf", exist_ok=True)
        sh(f"/opt/llama.cpp/build/bin/llama-quantize /tmp/f16.gguf /vol/gguf/{name}.gguf Q4_K_M", log)
        sh(f"rm -rf /vol/lora/{name} && mkdir -p /vol/lora && cp -r /tmp/lora /vol/lora/{name}", log)
        hsh = hashlib.sha256()
        with open(f"/vol/gguf/{name}.gguf", "rb") as f:
            for blk in iter(lambda: f.read(1 << 24), b""): hsh.update(blk)
        out["gguf_sha256"] = hsh.hexdigest(); out["gguf_bytes"] = os.path.getsize(f"/vol/gguf/{name}.gguf"); out["ok"] = True
    except Exception as e:
        out["ok"] = False; out["error"] = str(e)[-3000:]
    out["total_s"] = round(time.time() - t0, 1); out["log"] = log
    os.makedirs("/vol/logs", exist_ok=True)
    json.dump({k: v for k, v in out.items() if k != "adapter_tgz"}, open(f"/vol/logs/{name}.json", "w"), indent=1); vol.commit()
    return out


@app.function(gpu=GPU, timeout=1500, volumes={"/vol": vol})  # GPUs enabled on the account at 07:58 ET (payment method added)
def train(name: str, flags: list, train_text: str, cal_text: str):
    return _train(name, flags, train_text, cal_text)


NCPU = int(os.environ.get("PG_MODAL_CPU", "32"))


@app.function(cpu=float(NCPU), memory=49152, timeout=3000, volumes={"/vol": vol})
def train_cpu(name: str, flags: list, train_text: str, cal_text: str):
    return _train(name, flags + ["--threads", str(NCPU)], train_text, cal_text)


VARIANTS = {
    "V0": [],                                                        # floor recipe on R2-A (control)
    "V1": ["--ce-weight", "0"],                                      # pure KL
    "V2": ["--ce-weight", "0", "--rank", "32", "--lr", "1e-4"],     # pure KL, r32, lr 1e-4
    "V3": ["--ce-weight", "0", "--epochs", "2", "--label-smooth", "0.05"],
    "V3p": ["--ce-weight", "0", "--label-smooth", "0.05"],            # V3 at 1 epoch (2 epochs do not fit the CPU time box)
    "V4": ["--lr", "1e-4", "--conf-weight"],                         # KL + 0.5 CE, teacher-confidence weighted
    "V5": ["--ce-weight", "0", "--glimmer-weight", "2"],             # pure KL, Glimmer rows 2x
    "V6": ["--ce-weight", "0", "--entropy-bonus", "0.1"],            # pure KL + confidence penalty
    "V0B": [], "V1B": ["--ce-weight", "0"], "V6B": ["--ce-weight", "0", "--entropy-bonus", "0.1"],  # same recipes on R2-B (imputed k=5)
    # 07:58 GPU sweep (orchestrator: skip pure KL; V1 was under-confident)
    "V6g": ["--lr", "1e-4", "--conf-weight", "--entropy-bonus", "0.1"],   # V4 + entropy bonus 0.1
    "V2g": ["--rank", "32", "--lr", "1e-4"],                              # r32, lr 1e-4, KL + 0.5 CE
    "V3g": ["--epochs", "2", "--label-smooth", "0.05"],                   # KL + 0.5 CE, 2 epochs, smoothed soft target
    "V0C": [], "V1C": ["--ce-weight", "0"], "V6C": ["--ce-weight", "0", "--entropy-bonus", "0.1"],  # R2-C (imputed k=8, alpha 0.1)
}


def _save(res, outdir):
    outdir.mkdir(parents=True, exist_ok=True)
    for r in res:
        if isinstance(r, Exception): print("EXC", r); continue
        if r.get("adapter_tgz"):
            tarfile.open(fileobj=io.BytesIO(r["adapter_tgz"])).extractall(outdir / "adapters")
        (outdir / f"modal_{r['name']}.json").write_text(json.dumps({k: v for k, v in r.items() if k != "adapter_tgz"}, indent=1))
        print(r["name"], "ok" if r.get("ok") else "FAIL", r.get("gpu"), r.get("total_s"), "s", r.get("gguf_sha256", r.get("error", ""))[:300])


@app.local_entrypoint()
def main(train: str = "", variants: str = "V0,V1,V2,V3,V4,V5,V6", tag: str = "sweep", cpu: bool = True, extra: str = ""):
    cal = (ROOT / "eval/gold/gold_calibration.jsonl").read_text()
    tt = (ROOT / train).read_text() if not train.startswith("/") else open(train).read()
    names = variants.split(",")
    t = time.time()
    fn = train_cpu if cpu else globals()["train"]
    ex = extra.split() if extra else []
    res = list(fn.starmap([(n + (("-" + tag) if tag != "sweep" else ""), VARIANTS[n] + ex, tt, cal) for n in names], return_exceptions=True))
    print(f"sweep wall {time.time()-t:.0f}s")
    _save(res, ROOT / "training/round2/out" / tag)


@app.function(timeout=1200, volumes={"/vol": vol})
def fetch_base():
    vol.reload(); ensure_base(); return sorted(os.listdir("/vol/base"))


@app.local_entrypoint()
def bench():
    print(fetch_base.remote())
    rows = (ROOT / "training/local_teacher/out/distill_train.jsonl").read_text().splitlines()[:200]
    cal = "\n".join((ROOT / "eval/gold/gold_calibration.jsonl").read_text().splitlines()[:8]) + "\n"
    jobs = [(f"BENCH-bf16-c{NCPU}", ["--max-steps", "6"])]
    for r in train_cpu.starmap([(n, f, "\n".join(rows) + "\n", cal) for n, f in jobs], return_exceptions=True):
        if isinstance(r, Exception): print("EXC", r); continue
        print(r["name"], r.get("ok"), r.get("error", "")[-300:], [l["out"][-400:] for l in r["log"][:1]], r.get("total_s"))


@app.local_entrypoint()
def warm():
    print(fetch_base.remote())
    rows = [l for l in (ROOT / "training/local_teacher/out/distill_train.jsonl").read_text().splitlines()[:24]]
    cal = "\n".join((ROOT / "eval/gold/gold_calibration.jsonl").read_text().splitlines()[:16]) + "\n"
    r = train_cpu.remote("WARM", ["--ce-weight", "0"], "\n".join(rows) + "\n", cal)
    _save([r], ROOT / "training/round2/out/warm")

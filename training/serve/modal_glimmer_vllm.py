"""Muse Glimmer 30B (Meta open weights, Apache-2.0) as Pocket Glimmer's self-hosted System-2 brain on Modal.

vLLM (native `MuseGlimmerForConditionalGeneration` support since v0.28.0, no trust_remote_code) serving the bf16
checkpoint `meta-models/Muse-Glimmer-30B` on one H100 80GB, OpenAI-compatible at  https://<app>.modal.run/v1/ ,
served model name `muse-glimmer`, flags per dev.meta.ai/docs/muse-glimmer/deploy + recipes.vllm.ai.

  modal run    training/serve/modal_glimmer_vllm.py::download     # once: ~60 GB bf16 -> Volume pg-glimmer-weights
  modal deploy training/serve/modal_glimmer_vllm.py               # persistent URL; scales to zero (idle = $0)

Auth: every path except /health needs `Authorization: Bearer $PG_GLIMMER_TOKEN` (Modal Secret `pg-glimmer-token`,
enforced by pg_auth.py). Cost: H100 billed per second only while a container runs; scaledown after 5 idle minutes.
"""
import subprocess

import modal

APP_NAME = "pg-glimmer-vllm"
MODEL_ID = "meta-models/Muse-Glimmer-30B"
MODEL_REVISION = "main"
MODEL_DIR = "/weights/Muse-Glimmer-30B"
SERVED_NAME = "muse-glimmer"
VLLM_VERSION = "0.33.0"          # >= 0.28.0 required (vllm-project/vllm#51655)
PORT = 8000
MINUTES = 60

app = modal.App(APP_NAME)

weights = modal.Volume.from_name("pg-glimmer-weights", create_if_missing=True)
vllm_cache = modal.Volume.from_name("pg-glimmer-vllm-cache", create_if_missing=True)

image = (
    modal.Image.debian_slim(python_version="3.12")
    .uv_pip_install(f"vllm=={VLLM_VERSION}", "huggingface_hub[hf_xet]")
    .env({"HF_XET_HIGH_PERFORMANCE": "1", "VLLM_USE_V1": "1"})
    .add_local_file(__file__.rsplit("/", 1)[0] + "/pg_auth.py", "/root/pg_auth.py")
)

dl_image = modal.Image.debian_slim(python_version="3.12").uv_pip_install("huggingface_hub[hf_xet]").env({"HF_XET_HIGH_PERFORMANCE": "1"})


@app.function(image=dl_image, volumes={"/weights": weights}, timeout=60 * MINUTES, cpu=8, memory=16384)
def download():
    """Fetch the bf16 safetensors + tokenizer/chat template once into the Volume (skips if already complete)."""
    import os
    from huggingface_hub import snapshot_download

    if os.path.exists(f"{MODEL_DIR}/.complete"):
        print("weights already cached"); return
    snapshot_download(MODEL_ID, revision=MODEL_REVISION, local_dir=MODEL_DIR,
                      allow_patterns=["*.json", "*.safetensors", "*.jinja", "LICENSE", "USAGE_POLICY.md", "README.md"])
    open(f"{MODEL_DIR}/.complete", "w").write(MODEL_REVISION)
    weights.commit()
    print("downloaded", sum(os.path.getsize(os.path.join(MODEL_DIR, f)) for f in os.listdir(MODEL_DIR)) / 1e9, "GB")


@app.function(
    image=image,
    gpu="H100",
    volumes={"/weights": weights, "/root/.cache/vllm": vllm_cache},
    secrets=[modal.Secret.from_name("pg-glimmer-token")],
    min_containers=0,
    max_containers=1,
    scaledown_window=300,
    timeout=30 * MINUTES,
    startup_timeout=25 * MINUTES,
)
@modal.concurrent(max_inputs=16)
@modal.web_server(port=PORT, startup_timeout=25 * MINUTES)
def serve():
    cmd = [
        "vllm", "serve", MODEL_DIR,
        "--served-model-name", SERVED_NAME,
        "--host", "0.0.0.0", "--port", str(PORT),
        "--tensor-parallel-size", "1",
        "--generation-config", "auto",                     # published sampling (T=1.0, top_p .95, top_k 64) + stop ids
        "--enable-auto-tool-choice", "--tool-call-parser", "muse_glimmer",
        "--reasoning-parser", "muse_glimmer",              # thinking -> message.reasoning, content stays clean
        "--default-chat-template-kwargs", '{"reasoning_strength": "low"}',   # phone escalations: short answers
        "--language-model-only",                           # text-only System-2; frees VRAM from the vision tower
        "--max-model-len", "16384",
        "--gpu-memory-utilization", "0.92",
        "--middleware", "pg_auth.bearer_auth",
    ]
    import os
    subprocess.Popen(cmd, cwd="/root", env={**os.environ, "PYTHONPATH": "/root"})

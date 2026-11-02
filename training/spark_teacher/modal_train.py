"""Run local_teacher/lora_gpu.py (floor recipe, unchanged) on a Modal L4. Uploads base model + training code + train rows;
returns the adapter dir. Usage: modal run modal_train.py"""
import modal, pathlib, subprocess, io, tarfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
img = (modal.Image.debian_slim(python_version="3.11")
       .pip_install("torch==2.15.0", "transformers==5.22.1", "peft==0.21.2", "accelerate", "sentencepiece")
       .add_local_dir("/workspace/pg-lora-venv/llama32-1b-instruct", "/base")
       .add_local_dir(str(ROOT / "training"), "/repo/training", ignore=["**/out/**", "**/__pycache__/**"])
       .add_local_file(str(ROOT / "training/spark_teacher/out/distill_train_spark.jsonl"), "/repo/train.jsonl")
       .add_local_dir(str(ROOT / "eval/gold"), "/repo/eval/gold"))
app = modal.App("pg-spark-floor", image=img)

@app.function(gpu="L4", timeout=3600)
def train():
    r = subprocess.run(["python", "/repo/training/local_teacher/lora_gpu.py", "--base", "/base", "--train", "/repo/train.jsonl",
                        "--out", "/tmp/lora", "--test", "/repo/eval/gold/gold_test.jsonl", "--dtype", "bfloat16", "--max-hours", "1"],
                       capture_output=True, text=True)
    print(r.stdout[-6000:]); print(r.stderr[-3000:])
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t: t.add("/tmp/lora", arcname="lora")
    return r.returncode, r.stdout, buf.getvalue()

@app.local_entrypoint()
def main():
    rc, out, tgz = train.remote()
    d = ROOT / "training/local_teacher/out"; (d / "spark_modal.log").write_text(out)
    tarfile.open(fileobj=io.BytesIO(tgz)).extractall(d / "spark_tmp")
    print("rc", rc)

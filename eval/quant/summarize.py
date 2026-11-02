"""Table for QUANT_IDENTITY.md from eval/quant/* (and the original headline files in eval/results/after_floor.*)."""
import json, os, sys, re
sys.path.insert(0, "training"); from reliability import ece
def rows(p): return json.load(open(p))["rows"]
def stats(R):
    n=len(R); acc=sum(r["ok"] for r in R)/n; h=[r for r in R if r["conf"]>=0.8]
    nn=[r for r in R if r["type"]=="nudgeNow"]
    return dict(acc=acc, handled=len(h)/n, aoh=(sum(r["ok"] for r in h)/len(h) if h else float("nan")),
        ece=ece([(r["conf"],r["ok"]) for r in R]), nudge=f'{sum(r["ok"] for r in nn)}/{len(nn)}')
def bound(p):
    t=open(p).read().splitlines()[0]; m=re.search(r"error <= ([\d.]+)%.*tau=([\d.]+), (\d+)/(\d+)", t)
    return f"{m.group(1)}% @tau {m.group(2)} ({int(m.group(3))/int(m.group(4)):.0%} handled)" if m else t
S={"Q4_K_M headline (Nov 1)":("eval/results/after_floor","eval/results/after_floor.conformal.txt",807694080)}
sz={"f16":"/workspace/quant-ggufs/ep1-f16.gguf","q8":"/workspace/quant-ggufs/ep1-Q8_0.gguf","q4ship":"training/local_teacher/out/lora-llama1b-glimmer-merged/Llama-3.2-1B-PocketGlimmer-Reflex-Q4_K_M.gguf","q3km":"/workspace/quant-ggufs/ep1-Q3_K_M.gguf","q2k":"/workspace/quant-ggufs/ep1-Q2_K.gguf"}
for k,f in sz.items():
    if os.path.exists(f"eval/quant/{k}.test.json"): S[k]=(f"eval/quant/{k}",f"eval/quant/{k}.conformal.txt",os.path.getsize(f))
print("| file | MB | cal acc | cal handled@0.8 | cal acc-on-handled | cal ECE | cal bound | cal nudgeNow | test acc | test ECE | test handled@0.8 | test acc-on-handled | test nudgeNow |")
print("|"+"---|"*13)
for k,(pre,conf,size) in S.items():
    c=stats(rows(pre+".calibration_split.json")); t=stats(rows(pre+".test.json"))
    print(f"| {k} | {size/1e6:.0f} | {c['acc']:.3f} | {c['handled']:.2f} | {c['aoh']:.3f} | {c['ece']:.3f} | {bound(conf)} | {c['nudge']} | {t['acc']:.3f} | {t['ece']:.3f} | {t['handled']:.2f} | {t['aoh']:.3f} | {t['nudge']} |")

"""Drift check part 2: run eval/drift/prompts.jsonl through GGUFs with llama.cpp llama-server (commit ddf48f8, CPU).
Prompt = exact token ids from the HF tokenizer's chat template (same as run_drift.py), sent as a token list
so no double BOS. Greedy (temperature 0, top_k 1), n_predict 96. KL vs bf16 is NOT computed (the server only
exposes top-n probs, not full logits).
Usage: pg-lora-venv/bin/python eval/drift/run_drift_gguf.py <label> <model.gguf> [port]"""
import json, os, sys, subprocess, time, urllib.request
from transformers import AutoTokenizer
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
HERE=os.path.dirname(os.path.abspath(__file__))
SERVER="/workspace/gate1/llama.cpp/build/bin/llama-server"
BASE="/workspace/pg-lora-venv/llama32-1b-instruct"
label, gguf = sys.argv[1], sys.argv[2]; port=int(sys.argv[3]) if len(sys.argv)>3 else 8099
import re
COLLAPSE=re.compile(r'^\s*[\{\[]|"\w+"\s*:|\b(request_type|route|label|intent|category)\b\s*[:=]|^\s*[A-Z_]{4,}\s*$', re.I|re.M)
def check(text, ans):
    if not ans: return None
    t=text.lower()
    return any((re.search(r'(?<!\d)'+re.escape(a)+r'(?!\d)',t) if a.isdigit() else a in t) for a in ans)
tok=AutoTokenizer.from_pretrained(BASE, trust_remote_code=False)
srv=subprocess.Popen([SERVER,"-m",gguf,"--port",str(port),"-c","2048","-t",str(os.cpu_count()),"-np","1"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
try:
    for _ in range(120):
        try: urllib.request.urlopen(f"http://127.0.0.1:{port}/health"); break
        except Exception: time.sleep(1)
    rows=[json.loads(l) for l in open(os.path.join(HERE,"prompts.jsonl"))]
    out=open(os.path.join(HERE,f"outputs_gguf_{label}.jsonl"),"w"); t0=time.time()
    for r in rows:
        ids=tok.apply_chat_template([{"role":"user","content":r["prompt"]}], add_generation_prompt=True, return_dict=True)["input_ids"]
        body=json.dumps({"prompt":ids,"n_predict":96,"temperature":0,"top_k":1,"cache_prompt":False,"seed":0}).encode()
        res=json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/completion",body,{"Content-Type":"application/json"})))
        txt=res["content"].strip()
        rec=dict(id=r["id"],category=r["category"],model=label,gguf=os.path.basename(gguf),out=txt,ok=check(txt,r["answers"]),collapse=bool(COLLAPSE.search(txt)))
        out.write(json.dumps(rec)+"\n"); out.flush()
    print(label,"done",round(time.time()-t0,1),"s")
finally: srv.terminate()

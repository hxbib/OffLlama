"""Drift check: Llama 3.2 1B Instruct base vs base + ep1 'floor' LoRA (SHIPPING adapter).
HF bf16 on box CPU, same chat template (tokenizer default, no system prompt), greedy decode.
KL(base||tuned) per token, teacher-forced on the base model's own greedy continuation (first 64 tokens).
No trust_remote_code. Usage: pg-lora-venv/bin/python eval/drift/run_drift.py"""
import json, re, time, os, torch, torch.nn.functional as F
from transformers import AutoTokenizer, AutoModelForCausalLM
from peft import PeftModel
HERE=os.path.dirname(os.path.abspath(__file__))
BASE="/workspace/pg-lora-venv/llama32-1b-instruct"
ADAPTER=os.path.join(HERE,"../../training/local_teacher/out/lora-llama1b-glimmer")  # ep1 SHIPPING adapter
MAXNEW=96; KLTOK=64
torch.set_num_threads(os.cpu_count()); torch.manual_seed(0)
tok=AutoTokenizer.from_pretrained(BASE, trust_remote_code=False)
m=AutoModelForCausalLM.from_pretrained(BASE, torch_dtype=torch.bfloat16, trust_remote_code=False)
m=PeftModel.from_pretrained(m, ADAPTER); m.eval()
COLLAPSE=re.compile(r'^\s*[\{\[]|"\w+"\s*:|\b(request_type|route|label|intent|category)\b\s*[:=]|^\s*[A-Z_]{4,}\s*$', re.I|re.M)
def gen(ids, base):
    ctx = m.disable_adapter() if base else torch.no_grad()
    with ctx, torch.no_grad():
        o=m.generate(ids, max_new_tokens=MAXNEW, do_sample=False, pad_token_id=tok.eos_token_id)
    return o[0, ids.shape[1]:]
def logits(full, base):
    ctx = m.disable_adapter() if base else torch.no_grad()
    with ctx, torch.no_grad(): return m(full).logits[0].float()
def check(text, ans):
    if not ans: return None
    t=text.lower()
    return any((re.search(r'(?<!\d)'+re.escape(a)+r'(?!\d)',t) if a.isdigit() else a in t) for a in ans)
rows=[ json.loads(l) for l in open(os.path.join(HERE,"prompts.jsonl")) ]
out=open(os.path.join(HERE,"outputs.jsonl"),"w"); t0=time.time()
for r in rows:
    ids=tok.apply_chat_template([{"role":"user","content":r["prompt"]}], add_generation_prompt=True, return_tensors="pt", return_dict=True)["input_ids"]
    gb=gen(ids,True); gt=gen(ids,False)
    cont=gb[:KLTOK]; full=torch.cat([ids[0],cont]).unsqueeze(0); n=ids.shape[1]
    lb=logits(full,True)[n-1:n-1+len(cont)]; lt=logits(full,False)[n-1:n-1+len(cont)]
    pb=F.log_softmax(lb,-1); pt=F.log_softmax(lt,-1)
    kl=(pb.exp()*(pb-pt)).sum(-1)
    tb=tok.decode(gb,skip_special_tokens=True); tt=tok.decode(gt,skip_special_tokens=True)
    rec=dict(id=r["id"],category=r["category"],prompt=r["prompt"],answers=r["answers"],
      kl_mean=kl.mean().item(), kl_max=kl.max().item(), kl_tokens=len(cont),
      base_out=tb, tuned_out=tt, identical=(tb==tt), base_ok=check(tb,r["answers"]), tuned_ok=check(tt,r["answers"]),
      base_collapse=bool(COLLAPSE.search(tb)), tuned_collapse=bool(COLLAPSE.search(tt)))
    out.write(json.dumps(rec)+"\n"); out.flush()
    print(r["id"], f'{rec["kl_mean"]:.4f}', rec["base_ok"], rec["tuned_ok"], rec["tuned_collapse"], f'{time.time()-t0:.0f}s', flush=True)
print("total_s", round(time.time()-t0,1))

"""Smoke test for the self-hosted Muse Glimmer 30B System-2 endpoint (training/serve/modal_glimmer_vllm.py). Stdlib only.

  source /tmp/gencode/sec/glimmer.env      # PG_GLIMMER_URL=https://<app>.modal.run  PG_GLIMMER_TOKEN=...
  python3 eval/serve/smoke_glimmer.py --out eval/serve/glimmer_modal_smoke.json

(a) GET /v1/models (also measures cold start when the app is scaled to zero)
(b) the exact escalation Assistant.swift sends (system prompt + scrubbed user text) -> [PERSON_1] must survive verbatim
(c) 3 System-2 Q&A items from eval/system2_items.py, graded with eval/run_system2.grade (key phrases)
(d) warm streaming TTFT + decode tokens/s
Output JSON never contains the token or the real host (host redacted to <modal-app>.modal.run)."""
import argparse, json, os, sys, time, urllib.error, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from system2_items import QA, NOW          # noqa: E402
from run_system2 import grade              # noqa: E402

SYS = ("You are the reasoning brain of a private phone assistant. Placeholders like [PERSON_1] stand for private data; "
       "keep them verbatim.")                                       # == core/Sources/PocketCore/Assistant.swift:164
SCRUBBED = ("Known about the user:\n- [PERSON_1] is the user's sister; her birthday is [DATE_1].\n"
            "User: Draft a two-sentence text I can send [PERSON_1] wishing her a happy birthday and suggesting dinner "
            "on Friday.")
QA_IDS = ("qa04", "qa07", "qa12")


def req(base, token, path, body=None, timeout=1800, stream=False):
    r = urllib.request.Request(base.rstrip("/") + path, json.dumps(body).encode() if body is not None else None,
                               {"Content-Type": "application/json", "Authorization": "Bearer " + token})
    resp = urllib.request.urlopen(r, timeout=timeout)
    return resp if stream else json.loads(resp.read())


def chat(base, token, messages, max_tokens=1024):
    t = time.time()
    r = req(base, token, "/v1/chat/completions", {"model": "muse-glimmer", "messages": messages, "max_tokens": max_tokens})
    m = r["choices"][0]["message"]
    return {"content": m.get("content") or "", "reasoning_chars": len(m.get("reasoning") or m.get("reasoning_content") or ""),
            "finish_reason": r["choices"][0].get("finish_reason"), "usage": r.get("usage"), "seconds": round(time.time() - t, 2)}


def stream_metrics(base, token, max_tokens=400):
    body = {"model": "muse-glimmer", "max_tokens": max_tokens, "stream": True, "stream_options": {"include_usage": True},
            "messages": [{"role": "system", "content": SYS},
                         {"role": "user", "content": "Explain in about 150 words why a phone assistant should ask before sending a message on the user's behalf."}]}
    t0 = time.time(); first = None; last = None; usage = None; chunks = 0
    for line in req(base, token, "/v1/chat/completions", body, stream=True):
        line = line.decode().strip()
        if not line.startswith("data:") or line == "data: [DONE]":
            continue
        d = json.loads(line[5:])
        if d.get("usage"): usage = d["usage"]
        for c in d.get("choices", []):
            delta = c.get("delta", {})
            if delta.get("content") or delta.get("reasoning") or delta.get("reasoning_content"):
                now = time.time(); first = first or now; last = now; chunks += 1
    out_toks = (usage or {}).get("completion_tokens") or chunks
    return {"ttft_s": round(first - t0, 3) if first else None, "total_s": round(time.time() - t0, 2),
            "completion_tokens": out_toks,
            "decode_tok_per_s": round((out_toks - 1) / (last - first), 1) if first and last and last > first else None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("PG_GLIMMER_URL")); ap.add_argument("--out")
    a = ap.parse_args()
    token = os.environ["PG_GLIMMER_TOKEN"]
    base = a.url.rstrip("/").removesuffix("/v1")
    res = {"endpoint": "https://<modal-app>.modal.run/v1", "model": "muse-glimmer (meta-models/Muse-Glimmer-30B, bf16)",
           "server": "vLLM on Modal, 1x H100 80GB", "date_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}

    try:                                                            # auth gate: no token -> 401
        urllib.request.urlopen(base + "/v1/models", timeout=1800); res["auth_without_token"] = "OPEN (unexpected)"
    except urllib.error.HTTPError as e:
        res["auth_without_token"] = f"HTTP {e.code}"

    t = time.time(); models = req(base, token, "/v1/models")
    res["a_models"] = {"ids": [m["id"] for m in models.get("data", [])], "seconds_incl_cold_start": round(time.time() - t, 1)}
    print("models", res["a_models"])

    b = chat(base, token, [{"role": "system", "content": SYS}, {"role": "user", "content": SCRUBBED}])
    b["placeholder_PERSON_1_verbatim"] = "[PERSON_1]" in b["content"]
    b["no_invented_name"] = "[" in b["content"]
    res["b_escalation"] = b
    print("escalation", b["placeholder_PERSON_1_verbatim"], repr(b["content"][:200]))

    qa = []
    for i, q, ref, keys in [x for x in QA if x[0] in QA_IDS]:
        r = chat(base, token, [{"role": "system", "content": f"You are a concise assistant. {NOW}"}, {"role": "user", "content": q}])
        qa.append({"id": i, "pass": grade(r["content"], keys), "reference": ref, "answer": r["content"][:300],
                   "finish_reason": r["finish_reason"], "seconds": r["seconds"], "usage": r["usage"]})
        print(i, "PASS" if qa[-1]["pass"] else "FAIL", repr(r["content"][:120]))
    res["c_system2_items"] = {"items": qa, "passed": sum(x["pass"] for x in qa), "n": len(qa),
                              "grader": "eval/run_system2.py grade() key phrases"}

    res["d_warm_stream"] = stream_metrics(base, token)
    print("stream", res["d_warm_stream"])
    if a.out:
        Path(a.out).write_text(json.dumps(res, indent=2) + "\n")
        print("wrote", a.out)


if __name__ == "__main__":
    main()

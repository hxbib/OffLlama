"""Local, free teacher: Muse Glimmer 30B IQ2_M GGUF behind llama-server on this box (no API, no spend).

One forward pass per item: render the Glimmer ATEM chat template (system = Reflex SYSTEM, reasoning strength low),
then force the assistant straight onto the user channel (` to=user<|message|>Answer:`) so the reasoning channel is
skipped, and read n_probs over the next token. Letter tokens (" A".."H" / "A".."H") are merged and renormalised
over the valid letters -> soft label. Serve with e.g.:
  /workspace/gate1/llama.cpp/build/bin/llama-server -m /workspace/gate1/Muse-Glimmer-30B-IQ2_M.gguf -c 2048 -t 8 -np 1 --port 8091
"""
import datetime, json, sys, time, urllib.request
from pathlib import Path
import jinja2

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pg_train import prompts  # noqa: E402
from pg_train.teachers import _normalize, _merge_letter_logprobs  # noqa: E402

TEMPLATE = "/workspace/gate1/chat_template.jinja"
_env = jinja2.Environment()
_env.globals["raise_exception"] = lambda m: (_ for _ in ()).throw(Exception(m))
_env.globals["strftime_now"] = lambda f: datetime.datetime(2026, 10, 31).strftime(f)
_tmpl = _env.from_string(Path(TEMPLATE).read_text())
SUFFIX = " to=user<|message|>Answer:"


def render(s: dict, ctx: str) -> str:
    p = _tmpl.render(messages=prompts.chat_messages(s, ctx), tools=None, add_generation_prompt=True, bos_token="",
                     reasoning_strength="low", current_date="2026-10-31")
    return p + SUFFIX


class GlimmerLocalTeacher:
    paid = False

    def __init__(self, url="http://127.0.0.1:8091", name="muse-glimmer-30b-iq2m-local"):
        self.url, self.name = url.rstrip("/"), name

    def label(self, s: dict, ctx: str) -> dict:
        L = prompts.letters(s)
        body = {"prompt": render(s, ctx), "n_predict": 1, "n_probs": 50, "temperature": 0, "cache_prompt": True,
                "post_sampling_probs": False}
        t0 = time.time()
        req = urllib.request.Request(self.url + "/completion", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as r:
            out = json.loads(r.read())
        ms = (time.time() - t0) * 1000
        top = out["completion_probabilities"][0]["top_logprobs"]
        raw = _merge_letter_logprobs([(t["token"], t["logprob"]) for t in top], L)
        p = _normalize(raw, L)
        import math
        mass = sum(math.exp(v) for v in raw.values())  # prob mass on letter tokens before renormalising
        letter = max(p, key=p.get) if p else None
        tm = out.get("timings", {})
        return {"teacher": self.name, "letter": letter, "probs": p or None, "confidence": p.get(letter) if p else None,
                "letter_mass": mass, "first_token": out.get("content"), "latency_ms": ms,
                "tokens_in": tm.get("prompt_n"), "prompt_ms": tm.get("prompt_ms"), "tokens_cached": out.get("tokens_cached")}

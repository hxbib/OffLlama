"""Teachers record (letter, probabilities over letters) per scenario.

Remote teachers (Muse Spark Open on Baseten, Muse Glimmer 30B on Modal, Meta Model API) are OpenAI-compatible
chat endpoints with logprobs. They REFUSE to run unless PG_ALLOW_SPEND=1 is set explicitly (spend approval).
LocalLlamaServerTeacher talks to a local llama-server and costs nothing (used for the labeled DRY RUN)."""
import json, math, os, random, time, urllib.request
from . import prompts


class SpendNotApproved(RuntimeError):
    pass


def _post(url, body, headers=None, timeout=120):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def _normalize(logp: dict, letters: list[str]) -> dict:
    """letter->logprob (subset) -> letter->prob over ALL letters; absent letters get floor = min(seen)-2."""
    if not logp: return {}
    floor = min(logp.values()) - 2.0
    v = [logp.get(l, floor) for l in letters]
    m = max(v); e = [math.exp(x - m) for x in v]; s = sum(e)
    return {l: x / s for l, x in zip(letters, e)}


def _merge_letter_logprobs(pairs, letters):
    out = {}
    for tok, lp in pairs:
        k = tok.strip()
        if k in letters:
            out[k] = lp if k not in out else max(out[k], lp) + math.log1p(math.exp(-abs(out[k] - lp)))
    return out


class LocalLlamaServerTeacher:
    """Stand-in teacher for dry runs. `shuffle=True` permutes option order (and maps back) to expose position bias."""
    def __init__(self, url="http://127.0.0.1:8088", name="llama-3.2-1b-q4-local", shuffle=False, seed=0, style="fewShot"):
        self.url, self.name, self.shuffle, self.rng = url.rstrip("/"), name + ("-shuf" if shuffle else ""), shuffle, random.Random(seed)
        self.style = style
        self.paid = False

    def label(self, s: dict, ctx: str) -> dict:
        order = list(range(len(s["options"])))
        if self.shuffle: self.rng.shuffle(order)
        view = dict(s, options=[s["options"][i] for i in order])
        L = prompts.letters(view)
        t0 = time.time()
        r = _post(self.url + "/completion", {"prompt": prompts.llama3(view, ctx, self.style), "n_predict": 1, "n_probs": 40, "temperature": 0, "cache_prompt": True})
        ms = (time.time() - t0) * 1000
        top = r["completion_probabilities"][0]["top_logprobs"]
        p_view = _normalize(_merge_letter_logprobs([(t["token"], t["logprob"]) for t in top], L), L)
        # map back to canonical letters
        p = {prompts.LETTERS[order[i]]: p_view[L[i]] for i in range(len(L))} if p_view else {}
        letter = max(p, key=p.get) if p else None
        return {"teacher": self.name, "letter": letter, "probs": p, "latency_ms": ms,
                "tokens_in": r.get("tokens_evaluated") or r.get("timings", {}).get("prompt_n"), "tokens_out": 1}


class OpenAICompatTeacher:
    """mode="logprobs": read the answer-letter token's top_logprobs (scans the output so reasoning tokens before the
    letter are fine). mode="sample": provider returns no logprobs (Meta Model API rejects logprobs with HTTP 400;
    Baseten ignores them for Spark Open), so draw k answers and use the empirical letter distribution."""
    def __init__(self, name, base_url, model, api_key_env, mode="logprobs", top_logprobs=20, k=5, max_tokens=1, extra=None):
        self.name, self.base_url, self.model, self.api_key_env = name, base_url.rstrip("/"), model, api_key_env
        self.mode, self.top, self.k, self.max_tokens, self.extra = mode, top_logprobs, k, max_tokens, extra or {}
        self.paid = True

    def _check(self):
        if os.environ.get("PG_ALLOW_SPEND") != "1":
            raise SpendNotApproved(f"{self.name}: paid API. Set PG_ALLOW_SPEND=1 only after spend approval (run cost.py first).")
        key = os.environ.get(self.api_key_env)
        if not key: raise SpendNotApproved(f"{self.name}: missing ${self.api_key_env}")
        return key

    @staticmethod
    def parse_letter(text, L):
        import re
        m = re.findall(r"\b([A-H])\b", text or "")
        m = [x for x in m if x in L]
        return m[-1] if m else None

    def _call(self, key, s, ctx, logprobs):
        body = {"model": self.model, "messages": prompts.chat_messages(s, ctx), "max_tokens": self.max_tokens, **self.extra}
        if logprobs: body.update({"logprobs": True, "top_logprobs": self.top, "temperature": 0})
        return _post(self.base_url + "/chat/completions", body, {"Authorization": f"Bearer {key}"})

    def label(self, s: dict, ctx: str) -> dict:
        key = self._check()
        L = prompts.letters(s)
        t0 = time.time(); tin = tout = 0
        if self.mode == "logprobs":
            r = self._call(key, s, ctx, True)
            ch = r["choices"][0]; u = r.get("usage", {}); tin, tout = u.get("prompt_tokens"), u.get("completion_tokens")
            toks = (ch.get("logprobs") or {}).get("content") or []
            pos = [t for t in toks if t.get("token", "").strip() in L]
            lp = pos[-1].get("top_logprobs", []) if pos else []
            p = _normalize(_merge_letter_logprobs([(x["token"], x["logprob"]) for x in lp], L), L)
            text = (ch.get("message") or {}).get("content") or ""
            letter = max(p, key=p.get) if p else self.parse_letter(text, L)
            probs = p or None
        else:
            votes = []
            for _ in range(self.k):
                r = self._call(key, s, ctx, False)
                u = r.get("usage", {}); tin += u.get("prompt_tokens") or 0; tout += u.get("completion_tokens") or 0
                votes.append(self.parse_letter((r["choices"][0].get("message") or {}).get("content"), L))
            got = [v for v in votes if v]
            probs = {l: got.count(l) / len(got) for l in L} if got else None
            letter = max(probs, key=probs.get) if probs else None
        return {"teacher": self.name, "letter": letter, "probs": probs, "latency_ms": (time.time() - t0) * 1000,
                "tokens_in": tin, "tokens_out": tout, "mode": self.mode}


# Provider presets, verified against official docs on 2026-10-31 (see docs/PROVIDERS_AND_LICENSES.md).
def spark_open_fireworks(model=os.environ.get("FIREWORKS_SPARK_MODEL", "accounts/fireworks/models/muse-spark-open")):
    # Serverless, $1.25/$4.25 per 1M. Fireworks chat API supports logprobs (top_logprobs <= 5). Reasoning model: allow
    # room for reasoning before the letter; the parser scans for the letter token.
    return OpenAICompatTeacher("muse-spark-open@fireworks", "https://api.fireworks.ai/inference/v1", model, "FIREWORKS_API_KEY",
                               mode="logprobs", top_logprobs=5, max_tokens=int(os.environ.get("PG_TEACHER_MAX_TOKENS", "512")))


def muse_spark_open_baseten(model=os.environ.get("BASETEN_MODEL", "meta-models/muse-spark-open")):
    # Baseten docs: Spark Open accepts logprobs but returns none -> sampled votes.
    return OpenAICompatTeacher("muse-spark-open@baseten", "https://inference.baseten.co/v1", model, "BASETEN_API_KEY",
                               mode="sample", k=int(os.environ.get("PG_TEACHER_K", "5")), max_tokens=int(os.environ.get("PG_TEACHER_MAX_TOKENS", "512")))


def glimmer_modal(model=os.environ.get("MODAL_MODEL", "muse-glimmer")):
    # Your own vLLM on a Modal Dedicated Endpoint / @app.server (1x H100 80GB; Meta docs: 72 GB VRAM to serve).
    # vLLM returns up to 20 top_logprobs. Use low reasoning strength via the system prompt per Glimmer prompting guide.
    return OpenAICompatTeacher("muse-glimmer-30b@modal", os.environ.get("MODAL_BASE_URL", "https://REPLACE.modal.direct/v1"), model, "MODAL_API_KEY",
                               mode="logprobs", top_logprobs=20, max_tokens=int(os.environ.get("PG_TEACHER_MAX_TOKENS", "384")))


def meta_model_api(model=os.environ.get("META_MODEL", "muse-spark-1.3")):
    # https://api.meta.ai/v1, Bearer $MODEL_API_KEY. logprobs -> HTTP 400 (reasoning model) -> sampled votes.
    return OpenAICompatTeacher("muse-spark-1.3@meta", "https://api.meta.ai/v1", model, "MODEL_API_KEY",
                               mode="sample", k=int(os.environ.get("PG_TEACHER_K", "5")), max_tokens=int(os.environ.get("PG_TEACHER_MAX_TOKENS", "512")),
                               extra={"reasoning_effort": "low"})

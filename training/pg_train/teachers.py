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
    def __init__(self, url="http://127.0.0.1:8088", name="llama-3.2-1b-q4-local", shuffle=False, seed=0):
        self.url, self.name, self.shuffle, self.rng = url.rstrip("/"), name + ("-shuf" if shuffle else ""), shuffle, random.Random(seed)
        self.paid = False

    def label(self, s: dict, ctx: str) -> dict:
        order = list(range(len(s["options"])))
        if self.shuffle: self.rng.shuffle(order)
        view = dict(s, options=[s["options"][i] for i in order])
        L = prompts.letters(view)
        t0 = time.time()
        r = _post(self.url + "/completion", {"prompt": prompts.llama3(view, ctx), "n_predict": 1, "n_probs": 40, "temperature": 0, "cache_prompt": True})
        ms = (time.time() - t0) * 1000
        top = r["completion_probabilities"][0]["top_logprobs"]
        p_view = _normalize(_merge_letter_logprobs([(t["token"], t["logprob"]) for t in top], L), L)
        # map back to canonical letters
        p = {prompts.LETTERS[order[i]]: p_view[L[i]] for i in range(len(L))} if p_view else {}
        letter = max(p, key=p.get) if p else None
        return {"teacher": self.name, "letter": letter, "probs": p, "latency_ms": ms,
                "tokens_in": r.get("tokens_evaluated") or r.get("timings", {}).get("prompt_n"), "tokens_out": 1}


class OpenAICompatTeacher:
    def __init__(self, name, base_url, model, api_key_env, extra=None):
        self.name, self.base_url, self.model, self.api_key_env, self.extra = name, base_url.rstrip("/"), model, api_key_env, extra or {}
        self.paid = True

    def _check(self):
        if os.environ.get("PG_ALLOW_SPEND") != "1":
            raise SpendNotApproved(f"{self.name}: paid API. Set PG_ALLOW_SPEND=1 only after spend approval (run cost.py first).")
        key = os.environ.get(self.api_key_env)
        if not key: raise SpendNotApproved(f"{self.name}: missing ${self.api_key_env}")
        return key

    def label(self, s: dict, ctx: str) -> dict:
        key = self._check()
        L = prompts.letters(s)
        t0 = time.time()
        r = _post(self.base_url + "/chat/completions",
                  {"model": self.model, "messages": prompts.chat_messages(s, ctx), "max_tokens": 1, "temperature": 0,
                   "logprobs": True, "top_logprobs": 20, **self.extra}, {"Authorization": f"Bearer {key}"})
        ms = (time.time() - t0) * 1000
        ch = r["choices"][0]
        lp = ((ch.get("logprobs") or {}).get("content") or [{}])[0].get("top_logprobs") or []
        p = _normalize(_merge_letter_logprobs([(x["token"], x["logprob"]) for x in lp], L), L)
        text = (ch.get("message") or {}).get("content") or ""
        letter = max(p, key=p.get) if p else (text.strip()[:1] if text.strip()[:1] in L else None)
        usage = r.get("usage", {})
        return {"teacher": self.name, "letter": letter, "probs": p or None, "latency_ms": ms,
                "tokens_in": usage.get("prompt_tokens"), "tokens_out": usage.get("completion_tokens")}


def muse_spark_open_baseten(model=os.environ.get("BASETEN_MODEL", "muse-spark-open")):
    # Baseten Model APIs, OpenAI-compatible. Confirm the model slug in your Baseten dashboard.
    return OpenAICompatTeacher("muse-spark-open@baseten", os.environ.get("BASETEN_BASE_URL", "https://inference.baseten.co/v1"), model, "BASETEN_API_KEY")


def glimmer_modal(model=os.environ.get("MODAL_MODEL", "muse-glimmer-30b")):
    # Your own vLLM deployment on Modal (see training/modal_glimmer_vllm.py); URL looks like https://<ws>--<app>.modal.run/v1
    return OpenAICompatTeacher("muse-glimmer-30b@modal", os.environ.get("MODAL_BASE_URL", "https://REPLACE.modal.run/v1"), model, "MODAL_API_KEY")


def meta_model_api(model=os.environ.get("META_MODEL", "muse-spark-1.3")):
    return OpenAICompatTeacher("muse-spark@meta", os.environ.get("META_BASE_URL", "https://api.llama.com/compat/v1"), model, "META_API_KEY")

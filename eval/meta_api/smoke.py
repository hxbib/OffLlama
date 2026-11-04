#!/usr/bin/env python3
"""Live smoke tests for the three Meta Model API capabilities Pocket Glimmer adds on top of Muse Spark text:

  (a) Muse Voice Transcribe  POST /v1/asr/transcribe      model muse-voice-transcribe-1.0  (multipart: request JSON + audio WAV)
  (b) Muse Spark 1.3 vision  POST /v1/chat/completions    model muse-spark-1.3 (Standard mode) image_url data URL
  (c) SAM 3.1 segmentation   POST /v1/responses           model sam-3.1  input_text noun phrase + input_image data URL

stdlib only. Reads META_API_KEY from the environment (`source /tmp/gencode/sec/meta.env`); the key is never printed or
saved. Every response is written to eval/meta_api/<name>.json with the Authorization header redacted, and every call's
usage + an estimated cost is appended to eval/meta_api/spend.jsonl. Hard cap: --cap-usd (default 3.00).

Fixtures (generated, not downloaded): fixtures/remind.wav (ffmpeg flite TTS, 16 kHz mono PCM),
fixtures/bars.jpg (matplotlib bar chart), fixtures/whiteboard.jpg (matplotlib whiteboard with 5 sticky notes).

    python3 eval/meta_api/smoke.py            # runs a, b, c (+ the endpoint probes)
    python3 eval/meta_api/smoke.py --only c
"""
from __future__ import annotations

import argparse, base64, json, os, sys, time, urllib.error, urllib.request, uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIX = HERE / "fixtures"
BASE = os.environ.get("META_BASE_URL", "https://api.meta.ai/v1")
SPEND = HERE / "spend.jsonl"

# Pay-as-you-go prices, dev.meta.ai/docs/pricing-rate-limits (read 2026-11-04).
PRICE = {
    "muse-spark-1.3": {"in": 1.25 / 1e6, "out": 4.25 / 1e6, "cached": 0.15 / 1e6},
    "muse-voice-transcribe-1.0": {"per_hour": 0.18},
    "sam-3.1": {"per_image": 2.50 / 1000},
}


def key() -> str:
    k = os.environ.get("META_API_KEY") or os.environ.get("MODEL_API_KEY")
    if not k:
        sys.exit("META_API_KEY not set (source /tmp/gencode/sec/meta.env). Smoke tests not run.")
    return k


def spent_so_far() -> float:
    if not SPEND.exists():
        return 0.0
    return sum(json.loads(l).get("usd", 0.0) for l in SPEND.read_text().splitlines() if l.strip())


def log_spend(name: str, model: str, endpoint: str, status: int, usage: dict, usd: float, extra: dict | None = None):
    row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "test": name, "model": model, "endpoint": endpoint, "status": status,
           "usage": usage, "usd": round(usd, 6)}
    if extra:
        row.update(extra)
    with SPEND.open("a") as f:
        f.write(json.dumps(row) + "\n")


def http(method: str, path: str, body: bytes | None, headers: dict, timeout=120):
    req = urllib.request.Request(BASE + path, data=body, method=method)
    req.add_header("Authorization", "Bearer " + key())
    for k, v in headers.items():
        req.add_header(k, v)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data, status, rh = r.read(), r.status, dict(r.headers)
    except urllib.error.HTTPError as e:
        data, status, rh = e.read(), e.code, dict(e.headers)
    ms = (time.time() - t0) * 1000
    return status, data, rh, ms


def save(name: str, request_summary: dict, status: int, data: bytes, ms: float, headers: dict | None = None):
    try:
        parsed = json.loads(data)
    except Exception:
        parsed = None
    out = {"name": name, "endpoint": BASE + request_summary.pop("path"), "request": request_summary,
           "request_headers": {"Authorization": "Bearer <REDACTED>", **(headers or {})},
           "status": status, "latency_ms": round(ms), "response_json": parsed,
           "response_head": None if parsed is not None else data[:4000].decode("utf-8", "replace")}
    (HERE / f"{name}.json").write_text(json.dumps(out, indent=2) + "\n")
    return parsed


def multipart(parts: list[tuple[str, str | None, str, bytes]]) -> tuple[bytes, str]:
    """parts: (field, filename|None, content_type, bytes)"""
    b = "----pg" + uuid.uuid4().hex
    out = bytearray()
    for field, fname, ctype, payload in parts:
        out += f"--{b}\r\n".encode()
        disp = f'form-data; name="{field}"' + (f'; filename="{fname}"' if fname else "")
        out += f"Content-Disposition: {disp}\r\nContent-Type: {ctype}\r\n\r\n".encode()
        out += payload + b"\r\n"
    out += f"--{b}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={b}"


def guard(cap: float, est: float):
    if spent_so_far() + est > cap:
        sys.exit(f"spend cap ${cap:.2f} would be exceeded (so far ${spent_so_far():.4f}); stopping")


# ---------------------------------------------------------------------------------------------------------------- (a)
def test_voice(cap: float):
    wav = (FIX / "remind.wav").read_bytes()
    req = {"model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV", "mode": "PUSH_TO_TALK", "languageBias": ["English"]}
    guard(cap, 0.01)
    body, ctype = multipart([("request", None, "application/json", json.dumps(req).encode()),
                             ("audio", "remind.wav", "audio/wav", wav)])
    st, data, _, ms = http("POST", "/asr/transcribe", body, {"Content-Type": ctype, "Accept": "application/json"})
    j = save("voice_transcribe", {"path": "/asr/transcribe", "multipart": {"request": req, "audio": f"<{len(wav)} bytes WAV 16kHz mono, flite TTS: 'Remind me to call Mom at seven tonight.'>"}},
             st, data, ms, {"Accept": "application/json", "Content-Type": "multipart/form-data"})
    dur = (j or {}).get("audioDurationMs", 0) if isinstance(j, dict) else 0
    usd = (dur // 1000) / 3600 * PRICE["muse-voice-transcribe-1.0"]["per_hour"] if st == 200 else 0.0
    log_spend("voice_transcribe", "muse-voice-transcribe-1.0", "/v1/asr/transcribe", st, {"audioDurationMs": dur, "audio_bytes": len(wav)}, usd)
    print(f"(a) voice  {st} {ms:.0f} ms  transcript={json.dumps((j or {}).get('transcript') if isinstance(j, dict) else data[:200].decode('utf-8','replace'))}")
    return st, j


def probe_openai_transcriptions(cap: float):
    """The OpenAI-style path, probed once so the docs can say it is NOT the Meta route."""
    wav = (FIX / "remind.wav").read_bytes()
    body, ctype = multipart([("model", None, "text/plain", b"muse-voice-transcribe-1.0"), ("file", "remind.wav", "audio/wav", wav)])
    st, data, _, ms = http("POST", "/audio/transcriptions", body, {"Content-Type": ctype})
    save("probe_audio_transcriptions", {"path": "/audio/transcriptions", "multipart": {"model": "muse-voice-transcribe-1.0", "file": f"<{len(wav)} bytes>"}}, st, data, ms)
    log_spend("probe_audio_transcriptions", "muse-voice-transcribe-1.0", "/v1/audio/transcriptions", st, {}, 0.0)
    print(f"    probe /audio/transcriptions -> {st} {data[:160].decode('utf-8','replace')!r}")


# ---------------------------------------------------------------------------------------------------------------- (b)
def test_vision(cap: float):
    jpg = (FIX / "bars.jpg").read_bytes()
    q = "What is the tallest bar in this chart, and what is its value? Answer in one short sentence."
    payload = {"model": "muse-spark-1.3", "max_tokens": 600, "reasoning_effort": "low", "messages": [{"role": "user", "content": [
        {"type": "text", "text": q},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(jpg).decode()}}]}]}
    guard(cap, 0.02)
    st, data, rh, ms = http("POST", "/chat/completions", json.dumps(payload).encode(), {"Content-Type": "application/json"})
    summary = {"path": "/chat/completions", "json": {**payload, "messages": [{"role": "user", "content": [
        {"type": "text", "text": q}, {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,<{len(jpg)} bytes JPEG 640x400>"}}]}]}}
    j = save("vision_describe", summary, st, data, ms, {"Content-Type": "application/json"})
    u = (j or {}).get("usage", {}) if isinstance(j, dict) else {}
    p = PRICE["muse-spark-1.3"]
    usd = u.get("prompt_tokens", 0) * p["in"] + u.get("completion_tokens", 0) * p["out"]
    log_spend("vision_describe", "muse-spark-1.3", "/v1/chat/completions", st, u, usd, {"image_bytes": len(jpg)})
    ans = ((j or {}).get("choices") or [{}])[0].get("message", {}).get("content") if isinstance(j, dict) else None
    print(f"(b) vision {st} {ms:.0f} ms usage={u} answer={ans!r}")
    return st, j


def test_vision_whiteboard(cap: float):
    jpg = (FIX / "whiteboard.jpg").read_bytes()
    q = "This is a photo of my whiteboard. List each sticky note's text, one per line."
    payload = {"model": "muse-spark-1.3", "max_tokens": 800, "reasoning_effort": "low", "messages": [{"role": "user", "content": [
        {"type": "text", "text": q},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(jpg).decode()}}]}]}
    guard(cap, 0.02)
    st, data, _, ms = http("POST", "/chat/completions", json.dumps(payload).encode(), {"Content-Type": "application/json"})
    summary = {"path": "/chat/completions", "json": {**payload, "messages": [{"role": "user", "content": [
        {"type": "text", "text": q}, {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,<{len(jpg)} bytes JPEG 800x500>"}}]}]}}
    j = save("vision_whiteboard", summary, st, data, ms, {"Content-Type": "application/json"})
    u = (j or {}).get("usage", {}) if isinstance(j, dict) else {}
    p = PRICE["muse-spark-1.3"]
    usd = u.get("prompt_tokens", 0) * p["in"] + u.get("completion_tokens", 0) * p["out"]
    log_spend("vision_whiteboard", "muse-spark-1.3", "/v1/chat/completions", st, u, usd, {"image_bytes": len(jpg)})
    ans = ((j or {}).get("choices") or [{}])[0].get("message", {}).get("content") if isinstance(j, dict) else None
    print(f"(b2) whiteboard {st} {ms:.0f} ms usage={u} answer={ans!r}")


# ---------------------------------------------------------------------------------------------------------------- (c)
def sam_request(prompt: str, jpg: bytes, include_conf=True, one_bit=True):
    meta = {}
    if include_conf:
        meta["include_confidence"] = "true"
    if one_bit:
        meta["mask_encoding"] = "one_bit"
    payload = {"model": "sam-3.1", "input": [{"type": "message", "role": "user", "content": [
        {"type": "input_text", "text": prompt},
        {"type": "input_image", "image_url": "data:image/jpeg;base64," + base64.b64encode(jpg).decode()}]}], "stream": False}
    if meta:
        payload["metadata"] = meta
    return payload


def output_text(j: dict) -> str:
    if not isinstance(j, dict):
        return ""
    if isinstance(j.get("output_text"), str):
        return j["output_text"]
    parts = []
    for item in j.get("output", []) or []:
        for c in item.get("content", []) or []:
            if c.get("type") in ("output_text", "text") and isinstance(c.get("text"), str):
                parts.append(c["text"])
    return "".join(parts)


def test_sam(cap: float, fixture="whiteboard.jpg", prompt="yellow sticky note", name="sam_segment"):
    jpg = (FIX / fixture).read_bytes()
    payload = sam_request(prompt, jpg)
    guard(cap, 0.01)
    st, data, _, ms = http("POST", "/responses", json.dumps(payload).encode(), {"Content-Type": "application/json"})
    summary = {"path": "/responses", "json": {**payload, "input": [{"type": "message", "role": "user", "content": [
        {"type": "input_text", "text": prompt}, {"type": "input_image", "image_url": f"data:image/jpeg;base64,<{len(jpg)} bytes {fixture}>"}]}]}}
    j = save(name, summary, st, data, ms, {"Content-Type": "application/json"})
    txt = output_text(j)
    n = txt.count("<|box;")
    usd = PRICE["sam-3.1"]["per_image"] if st == 200 else 0.0
    log_spend(name, "sam-3.1", "/v1/responses", st, (j or {}).get("usage", {}) if isinstance(j, dict) else {}, usd, {"image_bytes": len(jpg), "boxes": n})
    print(f"(c) sam    {st} {ms:.0f} ms boxes={n} text_head={txt[:220]!r}")
    if st != 200:
        print("    body:", data[:300].decode("utf-8", "replace"))
    return st, j


def probe_sam_chat(cap: float):
    jpg = (FIX / "whiteboard.jpg").read_bytes()
    payload = {"model": "sam-3.1", "messages": [{"role": "user", "content": [
        {"type": "text", "text": "sticky note"},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(jpg).decode()}}]}]}
    guard(cap, 0.01)
    st, data, _, ms = http("POST", "/chat/completions", json.dumps(payload).encode(), {"Content-Type": "application/json"})
    save("probe_sam_chat_completions", {"path": "/chat/completions", "json": {"model": "sam-3.1", "messages": "<text 'sticky note' + image_url data URL>"}}, st, data, ms)
    log_spend("probe_sam_chat_completions", "sam-3.1", "/v1/chat/completions", st, {}, PRICE["sam-3.1"]["per_image"] if st == 200 else 0.0)
    print(f"    probe sam-3.1 on /chat/completions -> {st} {data[:200].decode('utf-8','replace')!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="abc")
    ap.add_argument("--probes", action="store_true", help="also probe the OpenAI-style paths (documents what is NOT supported)")
    ap.add_argument("--cap-usd", type=float, default=3.0)
    a = ap.parse_args()
    key()
    print(f"spent before: ${spent_so_far():.4f} (cap ${a.cap_usd:.2f})")
    if "a" in a.only:
        test_voice(a.cap_usd)
        if a.probes:
            probe_openai_transcriptions(a.cap_usd)
    if "b" in a.only:
        test_vision(a.cap_usd)
        test_vision_whiteboard(a.cap_usd)
    if "c" in a.only:
        test_sam(a.cap_usd)
        test_sam(a.cap_usd, fixture="bars.jpg", prompt="bar", name="sam_segment_bars")
        if a.probes:
            probe_sam_chat(a.cap_usd)
    print(f"spent after: ${spent_so_far():.4f}")


if __name__ == "__main__":
    main()

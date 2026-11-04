"""Batched Spark Open decision labeling for phone contexts.

Each API request covers a batch of independent Reflex decision contexts and
returns one letter per context ID. Fixed passes (default 3) give every
context the same number of draws; vote frequencies are empirical sample
frequencies, never teacher probabilities, and no soft target is built from
fewer than 2 valid draws. Raw completions, hashes, option IDs/order, parse
failures, and per-call usage are preserved in the state directory.

Usage (paid; requires BASETEN_API_KEY in the environment):
  python3 spark_phone_label.py --inputs staged.jsonl --state-dir DIR \
      --status status.json --cap-usd 54.99 [--batch-size 12] [--passes 3]
Resume is automatic: settled batches are skipped, UNKNOWN reserves persist.
"""
import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import spark_phone_common as C
import spark_phone_store as S


def aggregate(records_by_id, rows, passes):
    """records_by_id: id -> list of (batch_id, letter|None, parse_error)."""
    out = []
    for row in rows:
        oset = C.set_for_row(row)
        letters = C.letters_for(oset)
        recs = records_by_id.get(row["id"], [])
        votes = [r[1] for r in recs if r[1] is not None]
        counts = {l: votes.count(l) for l in letters}
        entry = {
            "id": row["id"],
            "stable_prompt_id": C.sha256_text(
                (row.get("reflex_type") or row.get("type") or "") + "\n"
                + row["context"] + "\n" + json.dumps(row.get("candidates"))),
            "reflex_type": row.get("reflex_type") or row.get("type") or row.get("decision_type"),
            "contract_id": row.get("contract_id"),
            "group_id": row.get("group_id"),
            "candidates": row.get("candidates"),
            "option_ids": C.option_ids_for(oset),
            "option_ids_order_hash": C.sha256_text(json.dumps(C.option_ids_for(oset))),
            "context_sha256": C.sha256_text(row["context"]),
            "k_requested": passes,
            "n_draws_settled": len(recs),
            "n_valid": len(votes),
            "vote_counts": counts,
            "draws": [{"batch_id": b, "letter": l, "parse_error": e} for b, l, e in recs],
            "teacher": C.TEACHER, "model": C.MODEL,
        }
        if votes:
            top = max(letters, key=lambda l: counts[l])
            tied = [l for l in letters if counts[l] == counts[top] and l != top]
            entry["hard_letter"] = top
            entry["hard_option_id"] = C.option_ids_for(oset)[letters.index(top)]
            entry["tie"] = bool(tied)
            entry["sample_frequencies"] = {l: counts[l] / len(votes) for l in letters}
            entry["frequency_note"] = (
                "empirical vote frequencies from fixed-k batched sampling at "
                "temperature 1.0; not teacher log-probabilities")
            if len(votes) >= 2:
                n = len(letters)
                entry["soft_smoothed_alpha0.5"] = {
                    l: (counts[l] + 0.5) / (len(votes) + 0.5 * n) for l in letters}
        else:
            entry["hard_letter"] = None
            entry["hard_option_id"] = None
        out.append(entry)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--inputs", required=True)
    ap.add_argument("--inputs-sha256", default="")
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--status", required=True)
    ap.add_argument("--out", required=True, help="aggregated labels JSONL")
    ap.add_argument("--cap-usd", type=float, default=54.99)
    ap.add_argument("--batch-size", type=int, default=12)
    ap.add_argument("--passes", type=int, default=3)
    ap.add_argument("--workers", type=int, default=S.MAX_INFLIGHT)
    ap.add_argument("--max-tokens", type=int, default=1536)
    ap.add_argument("--max-attempts", type=int, default=3)
    ap.add_argument("--rpm", type=float, default=S.MAX_RPM)
    ap.add_argument("--limit-batches", type=int, default=0, help="smoke: cap new batches")
    a = ap.parse_args(argv)

    raw = Path(a.inputs).read_bytes()
    digest = C.sha256_text(raw.decode())
    if a.inputs_sha256 and digest != a.inputs_sha256:
        raise SystemExit(f"input hash mismatch: {digest} != {a.inputs_sha256}")
    if "test" in Path(a.inputs).name.lower() and "test" not in str(a.state_dir):
        raise SystemExit("refusing: never label a test split")
    rows = [json.loads(l) for l in raw.decode().splitlines() if l.strip()]
    ids = [r["id"] for r in rows]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate input ids")
    state_dir = Path(a.state_dir)
    batches = [rows[i:i + a.batch_size] for i in range(0, len(rows), a.batch_size)]
    units = [(p, bi, b) for p in range(a.passes) for bi, b in enumerate(batches)]

    with S.single_writer(state_dir):
        store = S.Store(state_dir, a.cap_usd)
        done = S.load_done_batches(state_dir, "label_batches.jsonl")
        todo = []
        ns = digest[:10]  # namespace batches by input set: shared ledger, no collisions
        for p, bi, b in units:
            bid = f"label-{ns}-p{p}-b{bi:05d}"
            rec = done.get(bid)
            if rec and rec.get("state") == "SETTLED_OK":
                continue
            if rec is not None:
                # settled-but-unparseable (or failed) batch: retry under a fresh
                # batch id so the spend ledger keeps every attempt distinct
                k = 1
                while f"{bid}-r{k}" in done:
                    k += 1
                bid = f"{bid}-r{k}"
            todo.append((bid, b))
        if a.limit_batches:
            todo = todo[: a.limit_batches]
        S.write_status(store, a.status, "labeling",
                       {"inputs": a.inputs, "input_sha256": digest,
                        "rows": len(rows), "batches_total": len(units),
                        "batches_pending": len(todo), "passes": a.passes,
                        "batch_size": a.batch_size})
        key = os.environ.get("BASETEN_API_KEY")
        if todo and not key:
            raise SystemExit("BASETEN_API_KEY missing (source the env file; never pass keys as flags)")
        denied = [0]
        if todo:
            throttle = S.Throttle(a.rpm)
            transport = S.real_transport(key, throttle)

            def work(unit):
                bid, batch = unit
                messages = C.label_batch_messages(batch)
                outcome, body = S.run_batch_call(
                    store, transport, "label", bid, messages, a.max_tokens,
                    max_attempts=a.max_attempts)
                if outcome == "budget_denied":
                    denied[0] += 1
                    return bid
                rec = {"batch_id": bid, "kind": "label",
                       "input_ids": [r["id"] for r in batch],
                       "input_ids_hash": C.sha256_text(json.dumps([r["id"] for r in batch])),
                       "outcome": outcome, "at": time.time()}
                if outcome == "settled" and body is not None:
                    content = None
                    try:
                        content = (body.get("choices") or [{}])[0].get("message", {}).get("content")
                    except Exception:
                        content = None
                    rec["raw_completion"] = content
                    rec["raw_completion_sha256"] = C.sha256_text(content or "")
                    rec["usage"] = body.get("usage")
                    rec["model_returned"] = body.get("model")
                    try:
                        parsed = C.parse_label_batch(content, batch)
                        rec["state"] = "SETTLED_OK"
                        rec["parsed"] = parsed
                    except ValueError as e:
                        rec["state"] = "SETTLED_PARSE_FAIL"
                        rec["parse_error"] = str(e)
                else:
                    rec["state"] = "FAILED_" + outcome.upper()
                with store.lock:
                    S.append_jsonl(state_dir, "label_batches.jsonl", rec)
                return bid

            with ThreadPoolExecutor(max_workers=max(1, a.workers)) as ex:
                futs = [ex.submit(work, u) for u in todo]
                for f in as_completed(futs):
                    f.result()
        # aggregate from all settled batch records (including prior runs)
        done = S.load_done_batches(state_dir, "label_batches.jsonl")
        by_id = {}
        # multiple records per batch_id possible after parse-fail retries; last wins
        for bid, rec in done.items():
            if rec.get("kind") != "label":
                continue
            if not bid.startswith(f"label-{ns}-"):
                continue  # other input sets sharing this ledger (incl. retained v1)
            batch_rows = [r for r in rows if r["id"] in set(rec.get("input_ids", []))]
            for row in batch_rows:
                letter, err = None, rec.get("parse_error") or rec.get("state")
                if rec.get("state") == "SETTLED_OK":
                    letter, err = rec["parsed"][row["id"]], None
                by_id.setdefault(row["id"], []).append((bid, letter, err))
        labels = aggregate(by_id, rows, a.passes)
        out_path = Path(a.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = out_path.with_suffix(".jsonl.tmp")
        with open(tmp, "w") as f:
            for r in labels:
                f.write(json.dumps(r) + "\n")
            f.flush()
            os.fsync(f.fileno())
        tmp.replace(out_path)
        n_valid = sum(1 for r in labels if r["n_valid"] >= 2)
        S.write_status(store, a.status, "labels_written",
                       {"inputs": a.inputs, "input_sha256": digest, "rows": len(rows),
                        "labels_out": str(out_path), "labels_sha256": C.sha256_file(out_path),
                        "rows_with_ge2_valid": n_valid, "budget_denied_batches": denied[0]})
        print(f"labels: {len(labels)} rows, {n_valid} with >=2 valid draws, "
              f"committed ${store.committed():.4f} / ${a.cap_usd}", flush=True)
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

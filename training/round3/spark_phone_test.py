"""Fake-transport tests for spark_phone_*. No network, no paid calls."""
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spark_phone_common as C
import spark_phone_store as S
import spark_phone_label as L
import spark_phone_generate as G

ROW = {"id": "phone-00001", "reflex_type": "skillPick", "contract_id": "call",
       "context": "Now: Fri 09:00\nUser: Call Maya Patel",
       "candidates": ["Call someone", "Send a text"], "group_id": "pg-x"}
ROW2 = {"id": "phone-00002", "reflex_type": "skillPick", "contract_id": "call",
        "context": "Now: Fri 09:00\nUser: Call Leo Chen",
        "candidates": ["Call someone", "Send a text"], "group_id": "pg-y"}


def ok_transport(content_by_call=None, pin=1000, pout=100):
    state = {"n": 0}

    def t(messages, max_tokens):
        state["n"] += 1
        content = content_by_call(state["n"]) if content_by_call else "A"
        return {"kind": "ok", "http_status": 200,
                "body": {"choices": [{"message": {"content": content}}],
                         "usage": {"prompt_tokens": pin, "completion_tokens": pout},
                         "model": C.MODEL}}
    return t


class BatchParseTest(unittest.TestCase):
    def test_exact_id_mapping_required(self):
        good = json.dumps([{"id": "phone-00001", "letter": "A"},
                           {"id": "phone-00002", "letter": "B"}])
        got = C.parse_label_batch(good, [ROW, ROW2])
        self.assertEqual(got, {"phone-00001": "A", "phone-00002": "B"})

    def test_missing_duplicate_unknown_ids_rejected(self):
        rows = [ROW, ROW2]
        with self.assertRaises(ValueError):
            C.parse_label_batch(json.dumps([{"id": "phone-00001", "letter": "A"}]), rows)
        with self.assertRaises(ValueError):
            C.parse_label_batch(json.dumps([{"id": "phone-00001", "letter": "A"},
                                            {"id": "phone-00001", "letter": "A"},
                                            {"id": "phone-00002", "letter": "B"}]), rows)
        with self.assertRaises(ValueError):
            C.parse_label_batch(json.dumps([{"id": "phone-99999", "letter": "A"},
                                            {"id": "phone-00002", "letter": "B"}]), rows)
        with self.assertRaises(ValueError):
            C.parse_label_batch(json.dumps([{"id": "phone-00001", "letter": "Z"},
                                            {"id": "phone-00002", "letter": "B"}]), rows)

    def test_generation_parse_rejects_garbage(self):
        with self.assertRaises(ValueError):
            C.parse_generation_batch("no json here", 2)
        items = C.parse_generation_batch(
            json.dumps([{"utterance": "Call Maya", "arguments": {"contact": "Maya"}}]), 1)
        self.assertEqual(items[0]["utterance"], "Call Maya")

    def test_contract_validation(self):
        contracts = C.load_contracts()
        self.assertEqual(len(contracts), 38)
        disp, _ = C.disposition_for(contracts["alarmkit_schedule"], {}, "Set an app alarm")
        self.assertEqual(disp, "unsupported")
        disp, _ = C.disposition_for(contracts["call"], {}, "Call Maya")
        self.assertEqual(disp, "clarify_missing")
        disp, _ = C.disposition_for(contracts["call"], {"contact": "Maya Patel"}, "Call Maya Patel")
        self.assertEqual(disp, "await_confirmation")
        disp, _ = C.disposition_for(contracts["timer_start"], {"duration": "25 hours"},
                                    "Timer 25 hours")
        self.assertEqual(disp, "clarify_invalid")


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_reserve_includes_prompt_and_max_tokens_no_cache_discount(self):
        w = C.prompt_token_worst([{"role": "user", "content": "x" * 100}])
        self.assertAlmostEqual(C.reserve_usd(w, 1536), w * C.PIN + 1536 * C.POUT)

    def test_concurrent_admissions_never_exceed_cap(self):
        store = S.Store(self.dir, 0.02)
        results = []

        def admit(i):
            results.append(store.try_reserve("label", f"b{i}", 1, 500, 1536))
        threads = [threading.Thread(target=admit, args=(i,)) for i in range(50)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        admitted = [r for r in results if r not in (None, "duplicate")]
        self.assertLessEqual(store.committed(), 0.02 + 1e-9)
        self.assertLess(len(admitted), 50)
        self.assertGreaterEqual(len(admitted), 1)
        store.close()

    def test_restart_turns_reserved_into_unknown_and_retains_reserve(self):
        store = S.Store(self.dir, 25.0)
        key = store.try_reserve("label", "b1", 1, 500, 1536)
        self.assertTrue(key)
        store.close()
        store2 = S.Store(self.dir, 25.0)
        totals = store2.totals()
        self.assertEqual(totals.get("UNKNOWN", {}).get("calls"), 1)
        self.assertGreater(store2.committed(), 0)
        key2 = store2.try_reserve("label", "b1", 2, 500, 1536)
        self.assertTrue(key2)
        store2.close()

    def test_unknown_timeout_retains_reserve(self):
        store = S.Store(self.dir, 25.0)

        def timeout_transport(messages, max_tokens):
            return {"kind": "unknown", "error": "TimeoutError"}
        outcome, _ = S.run_batch_call(store, timeout_transport, "label", "bT",
                                      [{"role": "user", "content": "hi"}], 1536,
                                      max_attempts=2, backoff_base=0)
        self.assertEqual(outcome, "unknown")
        self.assertEqual(store.totals()["UNKNOWN"]["calls"], 2)
        self.assertAlmostEqual(store.committed(),
                               store.totals()["UNKNOWN"]["reserved_usd"])
        store.close()

    def test_missing_usage_fails_closed(self):
        store = S.Store(self.dir, 25.0)

        def no_usage(messages, max_tokens):
            return {"kind": "ok", "http_status": 200,
                    "body": {"choices": [{"message": {"content": "A"}}]}}
        outcome, _ = S.run_batch_call(store, no_usage, "label", "bM",
                                      [{"role": "user", "content": "hi"}], 1536,
                                      max_attempts=1)
        self.assertEqual(outcome, "unknown")
        self.assertEqual(store.totals()["UNKNOWN"]["calls"], 1)
        store.close()

    def test_budget_denial_before_dispatch(self):
        store = S.Store(self.dir, 0.001)
        calls = []
        outcome, _ = S.run_batch_call(
            store, ok_transport(calls.append), "label", "bD",
            [{"role": "user", "content": "x" * 5000}], 1536, max_attempts=1)
        self.assertEqual(outcome, "budget_denied")
        self.assertEqual(calls, [])
        store.close()

    def test_http_error_settles_zero_and_counts_retries(self):
        store = S.Store(self.dir, 25.0)
        calls = []

        def always_429(messages, max_tokens):
            calls.append(1)
            return {"kind": "http_error", "http_status": 429, "retry_after": 0,
                    "error": "HTTP 429"}
        outcome, _ = S.run_batch_call(store, always_429, "label", "bH",
                                      [{"role": "user", "content": "hi"}], 1536,
                                      max_attempts=3, backoff_base=0)
        self.assertEqual(outcome, "http_error")
        self.assertEqual(len(calls), 3)
        self.assertEqual(store.totals()["HTTP_ERROR"]["calls"], 3)
        self.assertAlmostEqual(store.committed(), 0.0)
        store.close()

    def test_throttle_respects_rpm_ceiling(self):
        times = []
        clock = [0.0]
        th = S.Throttle(25.0, token_budget=10 ** 9,
                        clock=lambda: clock[0], sleep=times.append)
        th.wait(est_tokens=10)
        th.wait(est_tokens=10)
        # second start spaced by >= 60/25 = 2.4s of throttle time
        self.assertGreaterEqual(th.next_at, 2.4)


class AggregateTest(unittest.TestCase):
    def test_soft_only_with_two_valid_draws_and_frequencies_labelled(self):
        by_id = {"phone-00001": [("b0", "A", None), ("b1", "A", None), ("b2", "B", None)],
                 "phone-00002": [("b0", "A", None), ("b1", None, "missing_ids")]}
        out = L.aggregate(by_id, [ROW, ROW2], 3)
        self.assertEqual(out[0]["hard_letter"], "A")
        self.assertIn("soft_smoothed_alpha0.5", out[0])
        self.assertIn("not teacher log-probabilities", out[0]["frequency_note"])
        self.assertNotIn("soft_smoothed_alpha0.5", out[1])

    def test_generated_ingest_rejects_heldout_and_mismatch(self):
        contracts = C.load_contracts()
        rec = {"batch_id": "gen-x", "state": "SETTLED_OK", "contract_id": "call",
               "family": "valid_complete",
               "items": [{"utterance": "Call Maya Patel",
                          "arguments": {"contact": "Maya Patel"}}]}
        rows, stats = G.ingest([rec], contracts, set(), set(), 0)
        self.assertEqual(stats["accepted"], 1)
        rows2, stats2 = G.ingest([rec], contracts,
                                 {C.core_key(rows[0]["context"])}, set(), 0)
        self.assertEqual(stats2["accepted"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)

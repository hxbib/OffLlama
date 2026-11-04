"""Fake-transport tests for spark_label. No network, no paid calls."""
import json, sys, tempfile, threading, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import spark_label as S

ROW = {"id": "ctx-1", "type": "route", "context": "User: hello there", "candidates": None}
ROW2 = {"id": "ctx-2", "type": "route", "context": "User: another question here", "candidates": None}


def ok_transport(content="A", pin=100, pout=50, calls=None):
    def t(messages, max_tokens):
        if calls is not None:
            calls.append(1)
        return {"kind": "ok", "http_status": 200,
                "body": {"choices": [{"message": {"content": content}}],
                         "usage": {"prompt_tokens": pin, "completion_tokens": pout}}}
    return t


class T(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def store(self, cap=25.0):
        return S.Store(self.dir, cap)

    def test_reserve_includes_prompt_worst_and_max_tokens(self):
        w = S.prompt_token_worst([{"role": "user", "content": "x" * 100}])
        self.assertGreaterEqual(w, 100)
        r = S.reserve_usd(w, 768)
        self.assertAlmostEqual(r, w * S.PIN + 768 * S.POUT)

    def test_concurrent_near_cap_admissions_never_exceed(self):
        # Worst-case reserve per call (~$0.0044) against a $0.02 cap: only a
        # few admissions may hold at once, and committed must never exceed cap.
        store = self.store(cap=0.02)
        results = []
        def admit(i):
            results.append(store.try_reserve(f"c{i}", 0, 1, 500, 768))
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

    def test_restart_after_response_before_log_failure(self):
        store = self.store(cap=25.0)
        key = store.try_reserve(ROW["id"], 0, 1, 500, 768)
        self.assertTrue(key)
        # Simulate crash: provider responded but settlement never logged.
        store.close()
        store2 = S.Store(self.dir, 25.0)
        totals = store2.totals()
        self.assertEqual(totals.get("UNKNOWN", {}).get("calls"), 1)
        self.assertGreater(store2.committed(), 0)
        # The unknown draw is not silently free: a retry needs a new reserve.
        key2 = store2.try_reserve(ROW["id"], 0, 2, 500, 768)
        self.assertTrue(key2)
        self.assertGreater(store2.committed(), totals["UNKNOWN"]["reserved_usd"])
        store2.close()

    def test_unknown_timeout_retains_reserve_and_fails_closed(self):
        store = self.store(cap=25.0)
        def timeout_transport(messages, max_tokens):
            return {"kind": "unknown", "error": "TimeoutError"}
        res = S.run_draw(store, timeout_transport, ROW, 0, 768, max_attempts=2, backoff_base=0)
        self.assertEqual(res, "unknown")
        totals = store.totals()
        self.assertEqual(totals["UNKNOWN"]["calls"], 2)
        self.assertAlmostEqual(store.committed(), totals["UNKNOWN"]["reserved_usd"])
        store.close()

    def test_missing_usage_fails_closed(self):
        store = self.store(cap=25.0)
        def no_usage(messages, max_tokens):
            return {"kind": "ok", "http_status": 200, "body": {"choices": [{"message": {"content": "A"}}]}}
        res = S.run_draw(store, no_usage, ROW, 0, 768, max_attempts=1, backoff_base=0)
        self.assertEqual(res, "unknown")
        self.assertEqual(store.totals()["UNKNOWN"]["calls"], 1)
        store.close()

    def test_retry_cap_and_http_errors_settle_zero(self):
        store = self.store(cap=25.0)
        calls = []
        def always_429(messages, max_tokens):
            calls.append(1)
            return {"kind": "http_error", "http_status": 429, "retry_after": 0, "error": "HTTP 429"}
        res = S.run_draw(store, always_429, ROW, 0, 768, max_attempts=3, backoff_base=0)
        self.assertEqual(res, "http_error")
        self.assertEqual(len(calls), 3)
        self.assertEqual(store.totals()["HTTP_ERROR"]["calls"], 3)
        self.assertEqual(store.committed(), 0.0)
        store.close()

    def test_throttle_spacing_and_retry_after(self):
        now = [0.0]
        sleeps = []
        th = S.Throttle(rpm=60.0, clock=lambda: now[0], sleep=lambda d: (sleeps.append(d), now.__setitem__(0, now[0] + d)))
        th.wait()
        th.wait()
        self.assertEqual(len(sleeps), 1)
        self.assertAlmostEqual(sleeps[0], 1.0)
        th.penalize(5.0)
        th.wait()
        self.assertAlmostEqual(sleeps[-1], 5.0, places=5)

    def test_duplicate_input_resume_dispatches_nothing(self):
        store = self.store(cap=25.0)
        calls = []
        t = ok_transport(calls=calls)
        self.assertEqual(S.run_draw(store, t, ROW, 0, 768, 3, backoff_base=0), "settled")
        self.assertEqual(len(calls), 1)
        self.assertEqual(S.run_draw(store, t, ROW, 0, 768, 3, backoff_base=0), "settled")
        self.assertEqual(len(calls), 1)
        self.assertTrue(store.draw_terminal(ROW["id"], 0, 3))
        store.close()

    def test_partial_votes_and_malformed_labels_preserved(self):
        store = self.store(cap=25.0)
        # draws: A, malformed, timeout-exhausted, B, A
        seq = [ok_transport("A"), ok_transport("no letter here at all"),
               None, ok_transport("B"), ok_transport("Answer: A")]
        for d in range(5):
            if seq[d] is None:
                def timeout_transport(messages, max_tokens):
                    return {"kind": "unknown", "error": "TimeoutError"}
                S.run_draw(store, timeout_transport, ROW, d, 768, max_attempts=1, backoff_base=0)
            else:
                S.run_draw(store, seq[d], ROW, d, 768, max_attempts=1, backoff_base=0)
        out = S.export_contexts(store, [ROW], 1)
        ctx = out[0]
        self.assertEqual(ctx["n_settled_draws"], 4)
        self.assertEqual(ctx["derived"]["n_valid"], 3)
        self.assertEqual(ctx["derived"]["vote_counts"]["A"], 2)
        self.assertEqual(ctx["derived"]["vote_counts"]["B"], 1)
        # malformed raw string preserved separately from derived target
        self.assertEqual(ctx["draws"][1]["raw_content"], "no letter here at all")
        self.assertIsNone(ctx["draws"][1]["parsed_letter"])
        self.assertEqual(ctx["draws"][2]["state"], "UNKNOWN")
        # actual token accounting includes every settled call
        totals = store.totals()
        self.assertEqual(totals["SETTLED"]["calls"], 4)
        expected = 4 * (100 * S.PIN + 50 * S.POUT)
        self.assertAlmostEqual(totals["SETTLED"]["actual_usd"], expected)
        store.close()

    def test_settled_actual_replaces_worst_case_reserve(self):
        store = self.store(cap=25.0)
        S.run_draw(store, ok_transport(pin=10, pout=10), ROW, 0, 768, 1, backoff_base=0)
        committed = store.committed()
        self.assertAlmostEqual(committed, 10 * S.PIN + 10 * S.POUT)
        self.assertLess(committed, S.reserve_usd(500, 768))
        store.close()


if __name__ == "__main__":
    unittest.main()

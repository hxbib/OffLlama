"""Stub tests for the Glimmer label pipeline. No network, GPU, or spend."""
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glimmer_common as G


def top_for(letter_probs, extra_min=-12.0):
    """Build a fake top-k dict (token_id -> logprob) from letter -> prob."""
    top = {}
    for letter, prob in letter_probs.items():
        ids = G.LETTER_TOKEN_IDS[letter]
        top[ids[0]] = math.log(prob)
        top[ids[1]] = math.log(prob * 0.01)
        top[ids[2]] = math.log(prob * 0.001)
    top[999999] = extra_min
    return top


class TestAggregation(unittest.TestCase):
    def test_sums_all_token_forms(self):
        top = top_for({"A": 0.8, "B": 0.1})
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -12.0)
        self.assertEqual(r["status"], "valid_complete")
        self.assertTrue(r["usable"])
        total = 0.8 * 1.011 + 0.1 * 1.011
        self.assertAlmostEqual(r["letter_mass"], total, places=9)
        self.assertAlmostEqual(r["distribution"]["A"], 0.8 / 0.9, places=6)

    def test_missing_token_is_censored_not_zero(self):
        top = top_for({"A": 0.8, "B": 0.1})
        missing_id = G.LETTER_TOKEN_IDS["B"][2]
        del top[missing_id]
        top[999999] = -4.0
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -4.0)
        self.assertEqual(r["status"], "invalid_censored")
        self.assertFalse(r["usable"])
        self.assertIn(missing_id, r["missing_token_ids"])

    def test_missing_with_tiny_bound_is_valid_bounded(self):
        top = top_for({"A": 0.8, "B": 0.1})
        del top[G.LETTER_TOKEN_IDS["B"][2]]
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -20.0)
        self.assertEqual(r["status"], "valid_bounded")
        self.assertTrue(r["usable"])
        self.assertLessEqual(r["missing_mass_upper"], G.MISSING_BOUND_EPS)

    def test_probe_completes_censored(self):
        top = top_for({"A": 0.8, "B": 0.1})
        mid = G.LETTER_TOKEN_IDS["B"][2]
        del top[mid]
        r = G.aggregate_letter_probs(top, {mid: math.log(0.0001)}, ["A", "B"], -4.0)
        self.assertEqual(r["status"], "valid_complete")

    def test_nonfinite_rejected(self):
        top = top_for({"A": 0.8, "B": 0.1})
        top[G.LETTER_TOKEN_IDS["A"][0]] = float("nan")
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -12.0)
        self.assertEqual(r["status"], "invalid_nonfinite")
        top[G.LETTER_TOKEN_IDS["A"][0]] = float("inf")
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -12.0)
        self.assertEqual(r["status"], "invalid_nonfinite")
        top[G.LETTER_TOKEN_IDS["A"][0]] = 0.5
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -12.0)
        self.assertEqual(r["status"], "invalid_nonfinite")

    def test_low_mass_not_usable(self):
        top = top_for({"A": 0.2, "B": 0.1})
        r = G.aggregate_letter_probs(top, {}, ["A", "B"], -12.0)
        self.assertEqual(r["status"], "valid_complete")
        self.assertFalse(r["usable"])
        self.assertLess(r["letter_mass"], 0.5)


class TestRestartAndBudget(unittest.TestCase):
    def test_restart_skips_terminal_and_retries_errors(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "labels.jsonl"
            recs = [
                {"id": "a", "prompt_hash": "h1", "status": "valid_complete"},
                {"id": "b", "prompt_hash": "h2", "status": "error"},
                {"id": "c", "prompt_hash": "h3", "status": "invalid_censored"},
            ]
            G.append_jsonl(out, recs)
            index = G.load_done_index(out)
            self.assertIn("h1", index)
            self.assertNotIn("h2", index)
            self.assertIn("h3", index)
            rows = [{"id": "a", "prompt_hash": "h1"}, {"id": "b", "prompt_hash": "h2"}]
            todo = [r for r in rows if r["prompt_hash"] not in index]
            self.assertEqual([r["id"] for r in todo], ["b"])

    def test_spending_bound(self):
        ledger = G.BudgetLedger(cap_usd=20.0)
        self.assertTrue(ledger.can_launch("B200", 1200))
        ledger.settle("B200", 3600, "one hour")
        spent = ledger.settled_usd
        self.assertGreater(spent, 6.0)
        self.assertFalse(ledger.can_launch("B200", 9000))
        self.assertAlmostEqual(G.worst_case_usd("H100", 3600), 3.95 + 32 * 0.008 + 4 * 0.0473, places=6)

    def test_balanced_selection(self):
        rows = [{"id": f"{t}-{i}", "type": t} for t in ["route", "timing"] for i in range(5)]
        picked = G.select_balanced(rows, 2)
        self.assertEqual(len(picked), 4)


if __name__ == "__main__":
    unittest.main()

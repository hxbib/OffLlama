"""Focused tests for duration_eval aggregate logic. No server required."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import duration_eval as D


def make_metrics(bound=0.09, share=0.40, tau=0.88, handled=72, errors=0,
                 acc_on=0.97, ece=0.05, acc=0.80, handled08=0.50):
    return {
        "n": 180, "acc": acc, "handled_at_0.8": handled08,
        "acc_on_handled_at_0.8": acc_on, "ece_10bin": ece,
        "ltt_tightest": {"tau": tau, "handled": handled, "errors": errors,
                         "handled_share": share, "error_upper_bound": bound, "delta": 0.1},
    }


class GateTests(unittest.TestCase):
    def test_gate_pass(self):
        g = D.legacy_gate(make_metrics())
        self.assertTrue(g["overall"])
        self.assertTrue(g["clause_a_bound_lt_10pct_share_ge_35pct"])

    def test_gate_fails_on_bound(self):
        g = D.legacy_gate(make_metrics(bound=0.104, share=0.35))
        self.assertFalse(g["clause_a_bound_lt_10pct_share_ge_35pct"])
        self.assertFalse(g["overall"])

    def test_gate_fails_on_share(self):
        g = D.legacy_gate(make_metrics(bound=0.09, share=0.30))
        self.assertFalse(g["overall"])

    def test_gate_fails_on_ece_warm(self):
        g = D.legacy_gate(make_metrics(ece=0.066))
        self.assertFalse(g["clause_c_ece_le_0.06"])
        self.assertFalse(g["overall"])

    def test_gate_fails_on_handled_accuracy(self):
        g = D.legacy_gate(make_metrics(acc_on=0.94))
        self.assertFalse(g["clause_b_acc_on_handled_at_0.8_ge_0.95"])
        self.assertFalse(g["overall"])

    def test_gate_boundary_is_strict(self):
        self.assertFalse(D.legacy_gate(make_metrics(bound=0.10))["overall"])
        self.assertTrue(D.legacy_gate(make_metrics(bound=0.0999))["overall"])


class DeltaTests(unittest.TestCase):
    def test_paired_delta_signs(self):
        cand = dict(make_metrics(bound=0.08, ece=0.04, acc=0.82, handled08=0.55, acc_on=0.98),
                    model_name="R3E2", global_pass=1, server_state="fresh", legacy_gate=D.legacy_gate(make_metrics()))
        base = dict(make_metrics(bound=0.10, ece=0.05, acc=0.79, handled08=0.48, acc_on=0.966),
                    model_name="SHIP", global_pass=1, server_state="fresh", legacy_gate=D.legacy_gate(make_metrics(bound=0.10)))
        # attach ltt_tightest already inside make_metrics copies
        d = D.paired_delta(cand, base)
        self.assertAlmostEqual(d["delta_bound"], -0.02)
        self.assertAlmostEqual(d["delta_ece"], -0.01)
        self.assertAlmostEqual(d["delta_handled_at_0.8"], 0.07)
        self.assertEqual(d["candidate"], "R3E2")

    def test_verify_rows_counts_errors(self):
        gold = [{"type": "route", "gold": "tool"}, {"type": "route", "gold": "clarify"}]
        rows = [{"type": "route", "gold": "tool", "ok": True},
                {"type": "route", "gold": "clarify", "ok": False}]
        v = D.verify_rows(rows, gold)
        self.assertTrue(v["order_match"])
        self.assertEqual(v["errors"], 1)
        self.assertEqual(v["correct"], 1)

    def test_verify_rows_detects_order_swap(self):
        gold = [{"type": "route", "gold": "tool"}, {"type": "timing", "gold": "now"}]
        rows = [{"type": "timing", "gold": "now", "ok": True},
                {"type": "route", "gold": "tool", "ok": True}]
        self.assertFalse(D.verify_rows(rows, gold)["order_match"])


class PassIdentityTests(unittest.TestCase):
    def test_four_pass_identities(self):
        ids = [((s - 1) * 2 + k + 1, "fresh" if k == 0 else "warm") for s in (1, 2) for k in range(2)]
        self.assertEqual(ids, [(1, "fresh"), (2, "warm"), (3, "fresh"), (4, "warm")])

    def test_drift_check(self):
        self.assertTrue(D.drift_check("The answer is 21.", ["21"]))
        self.assertFalse(D.drift_check("The answer is 22.", ["21"]))
        self.assertIsNone(D.drift_check("anything", []))
        self.assertTrue(D.drift_check("Paris is the capital", ["paris"]))


if __name__ == "__main__":
    unittest.main()

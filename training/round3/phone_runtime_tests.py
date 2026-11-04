"""Tests for phone_runtime_eval calibration and leakage guards.

Run: python3 training/round3/phone_runtime_tests.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import phone_runtime_eval as R


def row(lp, gold, t="route", key="route"):
    return {"id": "x", "type": t, "prior_key": key, "logprobs": lp,
            "gold_index": gold, "gold": "g", "pred_index": 0}


def test_censored_never_filled():
    vals, missing = R.extract_letter_logprobs(
        [{"token": " A", "logprob": -0.1}], ["A", "B"])
    assert vals is None and missing == ["B"]


def test_temperature_reduces_ece_on_overconfident_rows():
    rows = [row([2.0, -2.0], 0), row([2.0, -2.0], 0),
            row([2.0, -2.0], 1), row([-2.0, 2.0], 1)]
    raw = R.metrics(rows, {"*": 1.0}, {})
    temp = R.fit_temperature([(r["logprobs"], r["gold_index"]) for r in rows])
    cal = R.metrics(rows, {"*": temp}, {})
    assert temp > 1.0
    assert cal["calibrated"]["ece"] < raw["raw"]["ece"]


def test_prior_subtraction_flips_position_bias():
    rows = [row([1.0, 0.9], 1)]
    m = R.metrics(rows, {"*": 1.0}, {"route": [1.0, 0.0]})
    assert m["raw"]["acc"] == 0.0 and m["calibrated"]["acc"] == 1.0


def test_tau_none_when_target_unreachable():
    rows = [row([0.1, 0.0], 1)]
    assert R.select_tau(rows, {"*": 1.0}, {})["tau"] is None
    assert R.handled_at(rows, {"*": 1.0}, {}, None)["handled_n"] == 0


if __name__ == "__main__":
    test_censored_never_filled()
    test_temperature_reduces_ece_on_overconfident_rows()
    test_prior_subtraction_flips_position_bias()
    test_tau_none_when_target_unreachable()
    print("phone_runtime_tests: 4 passed")

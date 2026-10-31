import json, math, subprocess, sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pg_train import prompts, scenarios, label, calibrate, cost


class T(unittest.TestCase):
    def test_parity_with_swift(self):
        cfg = json.loads((ROOT / "config/option_sets.json").read_text())
        self.assertEqual(prompts.llama3(prompts.SETS["route"], "User: hello"), cfg["sample_prompt"])
        self.assertEqual(prompts.llama3(prompts.SETS["route"], "User: hello", "zeroShot"), cfg["sample_prompt_zeroshot"])
        self.assertEqual(prompts.llama3(prompts.get_set("contactPick", ["Sam Lee", "Sam Ortiz"]), "User: hi Sam"), cfg["sample_prompt_contact"])
        sw = {s["type"]: s for s in cfg["sets"]}
        self.assertEqual(prompts.dynamic_set("contactPick", ["Sam Lee", "Sam Ortiz"]), sw["contactPick"] | {})
        self.assertEqual(len(sw), 12)

    def test_scenarios_seeded_diverse(self):
        a, b = scenarios.generate(240, 7), scenarios.generate(240, 7)
        self.assertEqual(a, b)
        self.assertNotEqual(a, scenarios.generate(240, 8))
        self.assertEqual({x["type"] for x in a}, set(scenarios.GENS))
        self.assertEqual(len({(x["type"], x["context"], tuple(x.get("candidates", []))) for x in a}), 240)

    def test_disagreement_escalates(self):
        r = {"type": "route", "context": "x"}
        agree = label.merge(r, [{"letter": "B", "probs": {"A": .05, "B": .9, "C": .03, "D": .02}}, {"letter": "B", "probs": {"B": .8, "A": .2}}])
        self.assertEqual((agree["target"], agree["escalate"]), ("B", False))
        dis = label.merge(r, [{"letter": "A", "probs": {"A": .9}}, {"letter": "B", "probs": {"B": .9}}])
        self.assertEqual((dis["target"], dis["escalate"]), ("C", True))  # route fallback = escalate_cloud = C
        weak = label.merge(r, [{"letter": "A", "probs": {"A": .4, "B": .3}}])
        self.assertTrue(weak["escalate"])

    def test_calibration_math(self):
        S = [([6.0, 0.0], 0 if i < 70 else 1) for i in range(100)]
        t = calibrate.fit_temperature(S)
        self.assertAlmostEqual(calibrate.softmax([6, 0], t)[0], 0.7, places=2)
        self.assertEqual(calibrate.select_tau([.95, .9, .85, .6, .55], [1, 1, 1, 0, 1], 1.0), .85)

    def test_cost_estimator_no_network(self):
        rows = scenarios.generate(100, 0)
        est = cost.estimate(rows, ["spark-fireworks", "spark-baseten", "glimmer-modal", "local"], json.loads((ROOT / "config/pricing.json").read_text()))
        self.assertGreater(est["spark-baseten"]["usd"], 0); self.assertEqual(est["local"]["usd"], 0)
        self.assertGreater(est["spark-baseten"]["input_tokens"], 100 * 50)

    def test_remote_teacher_refuses_without_spend_flag(self):
        from pg_train import teachers
        import os
        os.environ.pop("PG_ALLOW_SPEND", None)
        with self.assertRaises(teachers.SpendNotApproved):
            teachers.muse_spark_open_baseten().label(prompts.SETS["route"], "x")


if __name__ == "__main__":
    unittest.main()


class TConformal(unittest.TestCase):
  def test_conformal_tau(self):
    from pg_train import conformal as K
    assert K.calibrate([0.99] * 20, [True] * 20)["tau"] is None  # too few rows to certify alpha=0.05
    conf = [0.9 + i * 1e-4 for i in range(200)] + [0.3 + i * 1e-3 for i in range(200)]
    ok = [True] * 200 + [i % 2 == 0 for i in range(200)]
    r = K.calibrate(conf, ok, 0.05, 0.1)
    assert r["tau"] is not None and r["handled"] >= 200 and r["error_upper_bound"] <= 0.05 + 1e-6

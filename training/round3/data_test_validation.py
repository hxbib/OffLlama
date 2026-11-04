"""Maintained tests for the round-3 data/benchmark tranche.

  python3 -m unittest training.round3.data_test_validation
  python3 training/round3/data_test_validation.py
"""
import importlib.util, json, sys, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def load_mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


class R3Data(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v = load_mod("dv", HERE / "data_validate.py")
        cls.g = load_mod("graders", ROOT / "eval/round3/graders.py")
        sys.path.insert(0, str(HERE))
        cls.bench = load_mod("bench", ROOT / "eval/round3/validate_benchmark.py")

    def test_real_manifests_pass(self):
        self.assertEqual(self.v.validate(HERE), [])

    def test_overlap_fixture_fails(self):
        self.assertTrue(self.v.validate(self.bench.corrupted_copy("overlap")))

    def test_missing_label_fixture_fails(self):
        self.assertTrue(self.v.validate(self.bench.corrupted_copy("missing_label")))

    def test_corrupt_hash_fixture_fails(self):
        self.assertTrue(self.v.validate(self.bench.corrupted_copy("corrupt_hash")))

    def test_no_gold_without_basis(self):
        for split in ("train", "dev", "calfit", "report"):
            for line in (HERE / f"data_{split}.jsonl").read_text().splitlines():
                r = json.loads(line)
                if r["label_status"] == "needs_label":
                    self.assertIsNone(r["gold"], r["id"])

    def test_graders_layers(self):
        self.assertTrue(self.g.grade_choice("tool", "tool"))
        ok, _ = self.g.grade_slots({"timezone": "UTC"}, {"timezone": "Europe/Paris"})
        self.assertFalse(ok)
        n, e = self.g.group_errors([{"group_id": "a", "error": False},
                                    {"group_id": "a", "error": False},
                                    {"group_id": "b", "error": True}])
        self.assertEqual((n, e), (2, 1))
        self.assertGreater(self.g.wilson(0, 30)[1], 0.05)

    def test_protocol_gate_is_unambiguous(self):
        proto = json.loads((ROOT / "eval/round3/protocol.json").read_text())
        self.assertNotIn("OR optimized", proto["primary_metric"]["gate"])
        self.assertIn("135 handled groups", proto["primary_metric"]["gate"])


if __name__ == "__main__":
    unittest.main()

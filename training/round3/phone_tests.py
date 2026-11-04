"""Focused phone-tranche tests. No network, GPU, or spend.

  python3 -m unittest training.round3.phone_tests -v
"""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "training"))
import phone_budget as B
import phone_contracts as PC
import phone_convert as CV


def load(p):
    return [json.loads(l) for l in Path(p).read_text().splitlines() if l.strip()]


class TestContracts(unittest.TestCase):
    def test_all_contracts_covered(self):
        cov = json.loads((HERE / "phone_coverage.json").read_text())
        self.assertEqual(len(cov), 38)
        for cid, c in cov.items():
            self.assertGreater(c["train"]["rows"], 0, cid)

    def test_unavailable_stays_unsupported(self):
        contracts = PC.load_contracts()
        d, _ = PC.disposition_for(contracts["alarmkit_schedule"], {}, "Set an alarm", {})
        self.assertEqual(d, "unsupported")

    def test_validators(self):
        self.assertIsNone(PC.duration_seconds("ten minutes"))
        self.assertEqual(PC.duration_seconds("1 hour 30 minutes"), 5400.0)
        self.assertFalse(PC.is_web_url("htp:/bad url"))
        self.assertTrue(PC.is_web_url("https://hunter.cuny.edu"))
        self.assertEqual(PC.request_issue("flashlight_toggle", "Turn on the flashlight"),
                         ("state", "unsupported"))
        self.assertIsNone(PC.request_issue("flashlight_toggle", "Toggle flashlight"))
        self.assertEqual(PC.datetime_disposition("tomorrow at 7"), "clarify_invalid")
        self.assertIsNone(PC.datetime_disposition("tomorrow at 7:30 AM America/New_York"))

    def test_option_mapping_roundtrip(self):
        oset = PC.extended_get_set("skillPick", ["A one", "B two"])
        self.assertEqual(PC.option_ids_for(oset), ["s0", "s1", "ask"])
        self.assertEqual(PC.letter_for_id(oset, "ask"), "C")
        self.assertEqual(PC.id_for_letter(oset, "A"), "s0")


class TestSplits(unittest.TestCase):
    def test_no_group_leakage_across_phone_splits(self):
        owners = {}
        for split in ("train", "dev", "calfit"):
            for r in load(HERE / f"phone_inputs_{split}.jsonl"):
                if r["group_id"] in owners:
                    self.assertEqual(owners[r["group_id"]], split, r["group_id"])
                owners[r["group_id"]] = split
    def test_phone_groups_disjoint_from_frozen_heldout(self):
        import re
        sys.path.insert(0, str(ROOT / "training" / "local_teacher"))
        import dedupe as D
        def key(ctx):
            lines = [l for l in ctx.splitlines()
                     if not re.match(r"^(Now:|User location:|Network:)\s", l.strip())]
            return "g" + hashlib.sha256(D.norm("\n".join(lines).strip()).encode()).hexdigest()[:15]
        held = set()
        for split in ("dev", "calfit", "report"):
            for r in load(HERE / f"data_{split}.jsonl"):
                held.add(r["group_id"])
        for split in ("train", "dev", "calfit"):
            for r in load(HERE / f"phone_inputs_{split}.jsonl"):
                self.assertNotIn(key(r["context"]), held, r["id"])


class TestGroupingV2(unittest.TestCase):
    def _row(self, i, ctx, cands=None, v1="g-a"):
        return {"id": f"r{i}", "group_id": v1, "reflex_type": "route",
                "context": ctx, "candidates": cands, "contract_id": "reminder_create"}

    def test_wrapper_variants_cannot_cross_splits(self):
        import phone_groupfix as GF
        rows = [self._row(1, "Now: Fri 09:00\nNetwork: online\nUser: Text happy anniversary", v1="g-a"),
                self._row(2, "Now: Sat 14:30\nNetwork: offline\nUser: text happy anniversary", v1="g-b"),
                self._row(3, "Now: Mon 08:15\nUser location: home\nUser: Text happy anniversary", v1="g-c")]
        out, _ = GF.build_v2([dict(r) for r in rows])
        self.assertEqual(len({r["group_v2"] for r in out}), 1)
        self.assertEqual(len({r["split_v2"] for r in out}), 1)

    def test_candidate_permutation_same_group(self):
        import phone_groupfix as GF
        rows = [self._row(1, "User: Call Ben", ["Ben Wu", "Ben Cole"], v1="g-a"),
                self._row(2, "User: Call Ben", ["Ben Cole", "Ben Wu"], v1="g-b")]
        out, _ = GF.build_v2([dict(r) for r in rows])
        self.assertEqual(out[0]["group_v2"], out[1]["group_v2"])

    def test_permission_distinction_preserved(self):
        import phone_groupfix as GF
        rows = [self._row(1, "User: Text Maya hi", v1="g-a"),
                self._row(2, "Contacts access: denied\nUser: Text Maya hi", v1="g-a")]
        out, _ = GF.build_v2([dict(r) for r in rows])
        # Same v1 sibling group unions them, but canonical keys differ;
        # union via v1 is intentional sibling grouping, so assert the
        # canonical keys themselves stay distinct.
        self.assertNotEqual(GF.canonical_str(rows[0]), GF.canonical_str(rows[1]))


class TestConvert(unittest.TestCase):
    def _inp(self):
        return [{"id": "x1", "type": "route", "context": "User: hi", "candidates": None}]

    def _lab(self, **kw):
        base = {"id": "x1", "type": "route", "candidates": None,
                "option_ids": ["answer_local", "tool", "escalate_cloud", "clarify"],
                "status": "valid_complete", "usable": True,
                "distribution": {"A": 0.7, "B": 0.1, "C": 0.1, "D": 0.1},
                "top_letter": "A"}
        base.update(kw)
        return [base]

    def test_incomplete_targets_dropped(self):
        rows, stats = CV.convert_glimmer(self._inp(), self._lab(status="invalid_censored", usable=False, distribution=None, top_letter=None), "t")
        self.assertEqual(rows, [])
        self.assertIn("drop_invalid_censored", stats)

    def test_option_map_mismatch_dropped(self):
        rows, stats = CV.convert_glimmer(self._inp(), self._lab(option_ids=["a", "b"]), "t")
        self.assertEqual(rows, [])
        self.assertIn("option_map_mismatch", stats)

    def test_spark_partial_refused(self):
        inputs = [{"id": "a", "type": "route", "context": "x", "candidates": None},
                  {"id": "b", "type": "route", "context": "y", "candidates": None}]
        draws = [{"context_id": "a", "state": "SETTLED", "parsed_letter": "A"}] * 3
        with self.assertRaises(ValueError):
            CV.convert_spark_final(inputs, draws, {})


class TestBudget(unittest.TestCase):
    def test_unknown_retained_across_restart(self):
        with tempfile.TemporaryDirectory() as d:
            led = Path(d) / "ledger.jsonl"
            att = B.reserve(led, 100.0, "job-1", "B200", 1200)
            t1 = B.totals(led)
            self.assertGreater(t1["unknown_reserved_usd"], 2.0)
            B.outcome(led, att, False, "B200", 5, note="simulated crash")
            t2 = B.totals(led)  # fresh read simulates restart
            self.assertEqual(t2["unknown_reserved_usd"], t1["unknown_reserved_usd"])
            self.assertEqual(t2["committed_usd"], t2["unknown_reserved_usd"])

    def test_billed_releases_envelope_once(self):
        with tempfile.TemporaryDirectory() as d:
            led = Path(d) / "ledger.jsonl"
            att = B.reserve(led, 100.0, "job-2", "B200", 1200)
            B.outcome(led, att, True, "B200", 10)
            self.assertGreater(B.totals(led)["unknown_reserved_usd"], 0.0)
            B.billed(led, att, 0.25, "test bill")
            t = B.totals(led)
            self.assertEqual(t["unknown_reserved_usd"], 0.0)
            self.assertAlmostEqual(t["settled_billed_usd"], 0.25)
            with self.assertRaises(ValueError):
                B.billed(led, att, 0.25, "double bill")

    def test_billed_without_reservation_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            led = Path(d) / "ledger.jsonl"
            with self.assertRaises(ValueError):
                B.billed(led, "ghost#0000000000", 1.0, "test")

    def test_concurrent_reserves_never_oversubscribe(self):
        import threading
        with tempfile.TemporaryDirectory() as d:
            led = Path(d) / "ledger.jsonl"
            got, errs = [], []
            def worker(i):
                try:
                    got.append(B.reserve(led, 5.0, f"job-{i}", "B200", 1200))
                except RuntimeError as e:
                    errs.append(str(e))
            threads = [threading.Thread(target=worker, args=(i,)) for i in range(6)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
            self.assertEqual(len(got), len(set(got)))  # unique attempts
            self.assertLessEqual(B.totals(led)["committed_usd"], 5.0 + 1e-9)
            self.assertTrue(errs)  # cap refused the rest

    def test_unknown_retry_keeps_both_envelopes(self):
        with tempfile.TemporaryDirectory() as d:
            led = Path(d) / "ledger.jsonl"
            a1 = B.reserve(led, 100.0, "job-x", "B200", 1200)
            B.outcome(led, a1, False, "B200", 3)
            a2 = B.reserve(led, 100.0, "job-x", "H100", 1200)
            self.assertNotEqual(a1, a2)
            t = B.totals(led)
            self.assertEqual(len(t["open_attempts"]), 2)

    def test_chunk_plan_stable_after_partial_output(self):
        hashes = [f"h{i}" for i in range(6)]
        # Settled calls without durable output leave hashes undone:
        # they must be replanned at their absolute starts.
        plan = PC.plan_chunks(hashes, {"h0", "h1", "h4", "h5"}, 2)
        self.assertEqual(plan, [(2, ["h2", "h3"])])

    def test_missing_letter_is_censored_not_invented(self):
        import phone_eval as EV
        top = [{"token": " A", "logprob": -0.1}, {"token": " B", "logprob": -2.0}]
        vals, missing = EV.extract_letter_logprobs(top, ["A", "B", "C"])
        self.assertIsNone(vals)
        self.assertEqual(missing, ["C"])
        vals2, missing2 = EV.extract_letter_logprobs(top, ["A", "B"])
        self.assertEqual(missing2, [])
        self.assertAlmostEqual(vals2[0], -0.1)


if __name__ == "__main__":
    unittest.main()

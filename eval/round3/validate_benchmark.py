"""Fail on corrupted/overlapping/mislabeled benchmark fixtures; pass on
the real exported manifests plus the graders' smoke checks.

  python3 eval/round3/validate_benchmark.py
  python3 eval/round3/validate_benchmark.py --expect-fail /tmp/fixture_dir
"""
import argparse, importlib.util, json, shutil, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def load_mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def run_data_validate(directory):
    v = load_mod("dv", ROOT / "training/round3/data_validate.py")
    return v.validate(directory)


def corrupted_copy(kind):
    src = ROOT / "training/round3"
    tmp = Path(tempfile.mkdtemp(prefix=f"r3fix-{kind}-"))
    for f in ("data_manifest.json", "data_train.jsonl", "data_dev.jsonl",
              "data_calfit.jsonl", "data_report.jsonl"):
        shutil.copy(src / f, tmp / f)
    rows = [json.loads(l) for l in (tmp / "data_dev.jsonl").read_text().splitlines() if l.strip()]
    if kind == "overlap":
        train0 = json.loads((tmp / "data_train.jsonl").read_text().splitlines()[0])
        rows[0] = dict(rows[0], context=train0["context"], group_id=train0["group_id"])
    elif kind == "missing_label":
        rows[0] = dict(rows[0], label_status="needs_label", gold="tool")
    elif kind == "corrupt_hash":
        rows[0] = dict(rows[0], context=rows[0]["context"] + " tampered")
    (tmp / "data_dev.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
    import hashlib
    man = json.loads((tmp / "data_manifest.json").read_text())
    if kind != "corrupt_hash":
        # Keep hashes honest so only the semantic check can catch it.
        man["splits"]["dev"]["sha256"] = hashlib.sha256((tmp / "data_dev.jsonl").read_bytes()).hexdigest()
        man["splits"]["dev"]["rows"] = len(rows)
        (tmp / "data_manifest.json").write_text(json.dumps(man))
    return tmp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--expect-fail", default=None)
    a = ap.parse_args()
    if a.expect_fail:
        errs = run_data_validate(a.expect_fail)
        print(f"fixture {a.expect_fail}: {len(errs)} error(s) (expected >0)")
        sys.exit(0 if errs else 1)
    errs = run_data_validate(ROOT / "training/round3")
    if errs:
        print("FAIL real manifests:"); [print(" -", e) for e in errs[:20]]; sys.exit(1)
    for kind in ("overlap", "missing_label", "corrupt_hash"):
        e2 = run_data_validate(corrupted_copy(kind))
        if not e2:
            print(f"FAIL: {kind} fixture was not caught"); sys.exit(1)
        print(f"fixture {kind}: caught ({len(e2)} error(s))")
    g = load_mod("graders", HERE / "graders.py")
    assert g.grade_choice("a", "a") and g.wilson(0, 10)[1] > 0.2
    subprocess.run([sys.executable, "-m", "unittest", "eval.round3.test_graders"], cwd=ROOT, check=True)
    proto = json.loads((HERE / "protocol.json").read_text())
    assert proto["primary_metric"]["threshold_fitting"].startswith("cal-fit")
    print(f"OK: real manifests pass; overlap/corruption/missing-label fixtures fail; grader safety tests pass; {len(g.ALL_FAMILIES)} compiled action families inventoried; protocol frozen fields present")


if __name__ == "__main__":
    main()

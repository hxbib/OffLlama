#!/usr/bin/env python3
"""Teacher verdicts for the phone: {"id": <telemetry row id>, "agreed": bool}. The app imports this file with
TelemetryLog.importTeacherVerdicts, which fills the `agreed_teacher` column that the Reflex chart's
"later agreement with the teacher" series is built from. Also prints the agreement summary per type."""
import argparse, json, collections
ap = argparse.ArgumentParser(); ap.add_argument("--labels", required=True); ap.add_argument("--out", required=True); a = ap.parse_args()
per = collections.defaultdict(lambda: [0, 0]); n = 0
with open(a.out, "w") as f:
    for l in open(a.labels):
        if not l.strip(): continue
        r = json.loads(l)
        if r.get("agreed") is None: continue
        f.write(json.dumps({"id": r["id"], "agreed": bool(r["agreed"])}) + "\n"); n += 1
        p = per[r["type"]]; p[0] += int(bool(r["agreed"])); p[1] += 1
print(json.dumps({"verdicts": n, "per_type_agreement": {t: f"{p[0]}/{p[1]}" for t, p in sorted(per.items())}}))

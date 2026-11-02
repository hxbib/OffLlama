# NEXT_AGENT

Read **LEDGER.md** first (protocol, results, in-flight work, rejected ideas, release assets).

## Top three next actions
1. Check the nudge_v2 chain (box: training/local_teacher/out/nv2.log, or the PC GPU worker). If `floor_nv2` beats ep1 on **cal180 only**, evaluate once on test120, quantize, and swap in before **Tue Nov 3 noon ET**; otherwise keep the shipping 808 MB ep1 GGUF.
2. Run temperature scaling (training/temp_scale.py, fit on cal180) + LTT rerun; report T-scaled ECE on test120 once; then get Habib's sign-off and fill `[AFTER_*]` in docs.
3. iPhone build on the Mac (compile commit 35d619d badge), measure `[PHONE_*]`, record the 3-min video by **Tue Nov 3**. Submit by **Wed Nov 4, 9 PM ET**; make the repo public and check logged-out.

## Hard rules
- Only Meta models ship; non-Meta models never produce labels. Meta API is not a teacher (no logprobs, ToS §10.1(ix)).
- test120 frozen; select on cal180; augmented data never near test.
- No Fireworks, no Supabase, no trust_remote_code. Don't pitch Open Weights bonus. Never claim a guaranteed win.
- No secrets in git. Never force-push. Append to LEDGER.md at every milestone.

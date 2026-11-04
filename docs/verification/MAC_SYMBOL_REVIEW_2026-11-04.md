# Run 65 packaging review — Mac framework symbol check

Reviewer: OpenCode River04, DeepSeek V4.1 Flash 1017, max (user assignment).
Date: 2026-11-04.
Scope: parent commits `571d80d` and `15ab389` against `1e5c56e`, changed lines and docs only.
Mode: read-only. No repository edits, no agents, no paid calls, no PR.

Verdict: the two-line Linux/macOS shell fix is sound. The `nm` half does more than
stop SIGPIPE: it rejects an undefined `U` symbol that the old check accepted. The
four new fixtures are effective, but they are Linux/mock control-flow tests and do
not prove a linked, signed, installed app. Two text defects remain: the ledger still
says the Mac retest is pending even though parent item 2753 records it passing, and
the failure message still reports every `nm` failure as a missing symbol.

## Comment Sicko report

Touched (reviewed, not edited):

- `ios/mac_prep.sh` (2 code lines; no comments added or changed)
- `ios/test_mac_prep.sh` (mock `nm` branches and 4 fixtures; no comments added)
- `ORCHESTRATOR_LEDGER.md` (run 65 section)
- `docs/ORCHESTRATOR_DECISIONS.tsv` (7 new rows, lines 63–69)
- `docs/verification/run65_dispatches.json` (new, 3 jobs in `15ab389`)
- `docs/FINAL_HOURS.md`, `docs/PROJECT_STATUS.md`, `ios/DEVICE_ACCEPTANCE.md`

Deletion count: **0 code comments**. The diff adds no code comments and changes no
existing comment, so there is nothing in the code-comment keep/kill class to delete.

MUST KILL (text claims, not application code):

1. `ORCHESTRATOR_LEDGER.md:294` — “This is not yet a Mac retest.” Stale. Parent item
   2753 (20:13:46) says the patched wrapper confirmed the structural checks and the
   defined symbol, and item 2756 says “The Mac retest confirms the symbol-check fix.”
   Replace with a pointer to that result; keep compile/provenance/install open.
2. `ios/mac_prep.sh:277` — “exported llama_model_load_from_file symbol is missing”.
   False diagnosis when `nm` itself fails: stderr is discarded and the `RC=1` fixture
   asserts this same message for a failed `nm`. Replace it or split the branches.

Skips:

- The pre-existing test header comment (“fake … prove shell control flow only; they
  are not Xcode or framework proof”) is true and useful. Keep it.
- “A clean source checkout at the pin alone does not prove that an old binary was
  built from it” is a true provenance constraint. Keep it.
- `acceptance-docs` “allowed leeway around 6PM” is supported by the user at parent
  position 2584 (“6PM isn’t a FIRM time, you have SOME leeway”), just before the
  2600 window. Keep it.
- P09/P16/P20 text is accurate: durable effect recovery is integrated (`1507e36`,
  `core/Sources/PocketCore/EffectLedger.swift`), while durable deferred busy input
  is not (`docs/ACTION_VALIDATION.md`). Keep both distinctions.
- Other `grep -q` uses read files, not pipes (`mac_prep.sh:555,563–568`), and the
  `cmake | awk` / `xcodegen | head` pipelines have ignored status. No SIGPIPE fix
  needed there.
- The `vtool` half of the change is hygiene, not the observed bug (its producer is a
  shell variable, not `nm`). Harmless; no test required.
- The pre-existing `11c07cf` checkpoint line and the later commits after `15ab389`
  are outside this review. The two input-design agents and the contract/privacy
  review were not inspected, per instruction.

## 1. The two-line fix

```diff
-  if ! printf '%s\n' "$out" | grep -qiE 'platform[[:space:]]+IOS([[:space:]]|$)'; then
+  if ! printf '%s\n' "$out" | grep -iE 'platform[[:space:]]+IOS([[:space:]]|$)' >/dev/null; then
...
-  if ! nm -g "$bin" 2>/dev/null | grep -q '_llama_model_load_from_file$'; then
+  if ! nm -g "$bin" 2>/dev/null | grep -E '[[:xdigit:]]+[[:space:]]+T[[:space:]]+_llama_model_load_from_file$' >/dev/null; then
```

`mac_prep.sh` runs under `set -uo pipefail`. With `grep -q`, grep exits at the first
match; if the producer has more output than the pipe buffer, the producer gets
SIGPIPE and the pipeline status is 141 even though grep matched. `! pipeline` then
reports failure. Removing `-q` makes grep read to EOF, so the producer completes and
the pipeline status reflects the match.

The `nm` half also changes the predicate: the old `_llama_model_load_from_file$`
matched an undefined line such as

```
                 U _llama_model_load_from_file
```

The new address-plus-`T` requirement rejects `U` and requires a defined external
text symbol. That is a real false-pass repair, independent of SIGPIPE.

The `vtool` half is defensive only: its producer is the `printf` builtin writing a
captured variable, and vtool output is small. It cannot reproduce the 64 KiB pipe
race, but the change is harmless.

### Real Mac evidence

- Mac thread `mcp:launch:ac62…`, activity 15: `preflight` at `1e5c56e` fails with
  “exported llama_model_load_from_file symbol is missing”. Model/calibration pass;
  the framework/Info.plist checks pass before the symbol line.
- Mac thread activity 23: `build-unsigned --require-model` at the same `1e5c56e`
  passes “source llama.framework: native arm64 iOS Mach-O, install name and pinned
  symbol verified”, then reports provenance incomplete, no bundled `.gguf`, build
  not started, 453 MiB free. Same framework, same old code, opposite symbol result.
- Parent item 2753 (20:13:46): the patched wrapper “confirms framework structural
  checks and defined symbol”, independent `nm` sample
  `0000000000213588 T _llama_model_load_from_file`, then incomplete because the
  provenance marker is genuinely absent. Parent item 2756: “The Mac retest confirms
  the symbol-check fix.”

The p15 log records the script's failure, not `nm`'s 141; the SIGPIPE mechanism is a
reproduced diagnosis plus the same-binary flip, not a captured exit code from the
failed Mac run. The patched retest at p2753 is the direct confirmation.

### Error-code preservation

`pipefail` plus `if !` means a nonzero `nm` status fails the check even when grep
matches. The `FAKE_NM_RC=1` fixture proves it. The vtool path already captures
`vtool`'s status with `out=$(...)`. The check intentionally collapses every failure
to the command's exit 1; that is the script contract. What is lost is the *cause*:
`2>/dev/null` discards `nm`'s error, and the single message calls a tool failure a
missing symbol. See F2.

## 2. Fixture effectiveness (mutation-checked)

I copied the scoped `ios/` tree to `/tmp/pg-mut`, reverted only the two lines above,
and ran the same `ios/test_mac_prep.sh` (Linux; `mac_prep.sh` and the test file are
unchanged since `571d80d`).

Result: **86 passed, 2 failed**.

```
FAIL check-app accepts an exported symbol in a large symbol table
FAIL check-app rejects an undefined model-load symbol: command unexpectedly succeeded
```

- `LARGE` fails under the old code at the embedded-framework `nm` check. The mock
  writes the matching `T` line first and then 100,000 lines; `grep -q` exits early
  and the producer gets SIGPIPE. This is the regression the fix targets.
- `UNDEFINED` unexpectedly succeeds under the old code: the old `$`-anchored regex
  matches the `U` line. This proves the `T` requirement is substantive, not cosmetic.
- `MISSING` and `RC` pass under both old and new code. They are controls: the former
  keeps the check non-vacuous; the latter guards `pipefail` (without it, a failed
  `nm` whose output contains the symbol would pass).
- Reverting the `vtool` line caused no suite failure. That half is untested but
  harmless; vtool output is a short captured variable.

Independent one-liners:

```
$ printf '%s\n' '0000000000213588 T _llama_model_load_from_file' | \
    grep -E '[[:xdigit:]]+[[:space:]]+T[[:space:]]+_llama_model_load_from_file$' >/dev/null
rc=0
$ printf '%s\n' '                 U _llama_model_load_from_file' | \
    grep -E '[[:xdigit:]]+[[:space:]]+T[[:space:]]+_llama_model_load_from_file$' >/dev/null
rc=1
$ bash -c 'set -o pipefail; seq 1 200000 | grep -q 1; echo $?'
141
```

The parent's `/tmp/pg-macprep-symbol-check.log` is 88/0 and contains the four new
tests at lines 15–18.

## 3. Real Mach-O `nm` assumptions and risk

The check assumes a thin arm64 Mach-O dylib, Apple `nm`, an unstripped symbol table,
a hex address (16 digits in the real sample), whitespace between fields, and a strong
external text symbol. The real p2753 sample satisfies all of those. Residual risks:

| Assumption | Status today | If wrong |
|---|---|---|
| Thin arm64, Apple `nm` | real sample passes | Fat/universal `nm` errors (“is a fat file”); GNU `nm` cannot read Mach-O; both fail closed with the misleading message |
| Hex address + `T` + exact name | real sample matches | Stripped, weak (`W`), local (`t`), or re-formatted symbols are false negatives |
| `T` is a real export | symtab `T` is a good proxy | `-exported_symbols_list`/export-trie mismatch could theoretically pass or fail; provenance is the version gate, not this check |
| `nm` failure is caught | `pipefail` + `if !` + RC fixture | the failure is preserved; the exact exit code and stderr are not |
| `vtool` reports `platform IOS` | existing simulator fixture rejects `IOSSIMULATOR`; real retest passes | multi-platform fat output could contain both IOS and simulator; `nm` then fails closed |
| No SIGPIPE | grep drains; large fixture | a future `grep -q`/`-m1`/`head` reintroduces the race; LARGE catches it |

The strongest false-positive fixed is the undefined `U` line. The main residual
false-positive is a stale binary with the same symbol but the wrong version/ABI;
the missing provenance marker is the separate gate for that, correctly recorded. The
main residual false-negative is a tool/format failure reported as “symbol missing”.
None of these are present in the current pinned framework.

## 4. Do the tests protect observable packaging outcomes?

No. They protect the **check command's** observable exit code and message:

- `check-app` fixtures use a mock `nm`, mock `vtool`, mock `lipo`, mock `otool`, and
  a fixture app. `build-unsigned` uses a mock `xcodebuild`.
- The tests prove the script's control flow and the two regressions above. They do
  not prove Xcode compilation, linking against the framework, signing, installation,
  or runtime behavior.
- The real Mac retest confirms the patched script against the actual framework, but
  the unsigned build never started (no bundled model, missing provenance, disk), so
  there is still no packaging outcome proof. The docs correctly say this; the stale
  “retest pending” sentence is the only inconsistency.

## 5. Run 65 TSV audit (lines 63–69, `15ab389`)

| # | Row | Verdict |
|---|---|---|
| 63 | `start` | Verified: parent 2600/2609/2631; prior rows start at 14:37:46Z and end at 19:53:21Z; app unbuilt. |
| 64 | `mac-link` | Verified at its timestamp: user 2670 says the Mac link is reachable and asks for the assignment; no build had started. Parent device-list claim not independently re-read. |
| 65 | `acceptance-docs` | Verified: Mac linked; 6 PM leeway is user 2584 (just before 2600); recovery integrated at `1507e36`; all device rows still NOT RUN. |
| 66 | `mac-dispatch` | Verified snapshot: user 2670/2673 selected GPT 6.1 Terra at high effort; dispatch JSON records `codex_13/gpt-6.1-terra`. The JSON later shows completed; the 20:06 row is a snapshot, not a contradiction. |
| 67 | `mac-preflight` | Verified: old Mac thread activity 15 fails the symbol check, 23 passes it on the same framework; provenance/model/disk block the build; no install. |
| 68 | `packaging-fix` | Code claims verified; 88/0 log verified; **“Mac retest pending” is stale** after parent 2753/2756 (see F1). “88 fixtures” should say Linux/mock. |
| 69 | `input-design` | Metadata verified: dispatch JSON has river02/river03, variant max, running; implementation pending; `/tmp/pg-input-design-20261104` exists. “Read-only” is not verifiable from the repo; agents not inspected, per instruction. |

No other new-row discrepancy. `run65_dispatches.json` in `15ab389` is internally
consistent: `recordedAt` 20:10:42, Mac job completed with the 1e5c56e report, two
input designs running. The 6 PM leeway citation falls just outside the 2600 start;
it is still the correct source.

## 6. Findings

**F1 — Medium — stale/contradictory retest status.**
`ORCHESTRATOR_LEDGER.md:294` says “This is not yet a Mac retest” and TSV row 68 says
“Mac retest pending”. Parent item 2753 (20:13:46) and item 2756 record the patched
check passing on the actual framework, and the later ledger paragraph already says
“the patched symbol check passed on the actual framework.” At `15ab389` the sentence
was true; it is now contradicted by the same document. Risk: the next Mac worker
repeats a retest already done, or a reader treats the fix as unverified. Fix the
ledger sentence and append a retest row; do not rewrite the historical 20:11 row.

**F2 — Low — failed `nm` is reported as a missing symbol.**
`ios/mac_prep.sh:276–279` discards `nm` stderr, and the failure string is the same
for “no symbol”, “undefined symbol”, “wrong type”, and “nm failed”. The `RC=1`
fixture asserts that string, so the test locks in the wrong diagnosis. The check
still fails closed (correct); only the diagnosis is wrong. Optional minimal repair:
capture `nm` output and status the way the vtool check already does, then report
“nm -g failed” separately. Do not delay the Mac build for this.

**F3 — Low — test-platform qualifier.**
TSV row 68 says “88fixtures pass” without Linux/mock. The ledger says “Linux/mock”,
and the test header says the mocks are not Xcode/framework proof. The fixtures protect
the check, not packaging. Add the qualifier or keep the ledger wording; do not let
the number read as a Mac build result.

**F4 — Informational — residual Mach-O assumptions.**
Thin arm64/unstripped/Apple nm/strong `T` are true for the current artifact and the
real sample. Fat, stripped, weak, GNU-nm, or export-trie cases would produce false
negatives (or, in theory, a symtab-only false positive). No action now; provenance
and a real compile are the larger gates.

**F5 — Positive — fixture discrimination.**
The mutation run (86/2) proves `LARGE` catches the SIGPIPE race and `UNDEFINED`
catches the old false pass. Keep both. `MISSING`/`RC` are controls; that is fine.

**F6 — Informational — vtool half.**
The vtool drain is not exercised by a failing fixture. It is harmless and the real
retest passes it; no test is required because the producer is a captured variable.

## 7. Proposed patch (not applied)

### 7.1 Ledger (replace the stale sentence)

```diff
- tables, missing/undefined symbols, and failed `nm`. This is not yet a Mac retest.
+ tables, missing/undefined symbols, and failed `nm`. A patched retest followed at
+ 20:13:46 (parent item 2753; nm sample
+ 0000000000213588 T _llama_model_load_from_file); see the latest Mac return below.
+ Compile, provenance, and installation remain unverified.
```

### 7.2 TSV (append; do not rewrite row 68)

```
2026-11-04T20:13:46+00:00	packaging-retest	Record patched framework symbol check on the real Mac	Parent item2753 reports structural checks and a defined symbol; nm sample 0000000000213588 T _llama_model_load_from_file	parent run65 item2753; ios/mac_prep.sh; ios/test_mac_prep.sh	check passed on real framework; provenance, compile, install still open
```

Optionally add “Linux/mock” to row 68's `88fixtures pass`.

### 7.3 Optional `nm` diagnostic patch

This keeps the drain and preserves `nm`'s exact status and stderr:

```diff
-  local bin=$1 label=$2 out
+  local bin=$1 label=$2 out nm_out nm_rc
...
-  if ! nm -g "$bin" 2>/dev/null | grep -E '[[:xdigit:]]+[[:space:]]+T[[:space:]]+_llama_model_load_from_file$' >/dev/null; then
+  nm_out=$(nm -g "$bin" 2>&1); nm_rc=$?
+  if [ "$nm_rc" -ne 0 ]; then
+    fail "$label: nm -g failed (exit $nm_rc): $nm_out"
+    return 1
+  fi
+  if ! printf '%s\n' "$nm_out" | grep -E '[[:xdigit:]]+[[:space:]]+T[[:space:]]+_llama_model_load_from_file$' >/dev/null; then
     fail "$label: exported llama_model_load_from_file symbol is missing"
     return 1
   fi
```

Then change the RC fixture's expected substring to `nm -g failed (exit 1)`. The
symbol-missing message remains for missing/undefined/weak cases. This is optional;
the current code fails closed correctly. It also avoids the `if ! cmd` trap where
`$?` would be the negated status rather than `nm`'s status.

### 7.4 Optional test rename

`"check-app accepts an exported symbol in a large symbol table"` → e.g.
`"check-app drains a large nm table instead of failing on a closed pipe"`.
This names the regression without adding a comment. The current description is not
false, just less specific.

## 8. Verification limits

- I did not rerun the full **fixed** suite to completion. I read the parent's
  88/0 log (`/tmp/pg-macprep-symbol-check.log`, four new tests at lines 15–18) and
  confirmed `ios/mac_prep.sh` and `ios/test_mac_prep.sh` are unchanged since
  `571d80d`. My full-suite run was the **mutant old code** (86/2), on Linux.
- I did not run macOS, Xcode, signing, or installation. The compile is blocked by
  disk and missing provenance; no packaging outcome is proven.
- I read the raw old Mac thread activity 15/23. The patched retest evidence is the
  parent message at item 2753 plus item 2756; the v2 Mac thread was unreachable
  during the user's restart, so I could not read its raw activity/log. The quoted
  `nm` sample is the parent's evidence, not an independent capture by me.
- I did not inspect the two input-design agents or the contract/privacy review, per
  instruction. Their TSV row is checked against dispatch metadata only.
- The parent moved HEAD to `4fda967` while I reviewed. I pinned code and the cited
  TSV rows to `571d80d`/`15ab389`; later commits are out of scope. The current ledger
  line 294 is unchanged from `15ab389`, which is why F1 is still live.
- The 88-fixture log, the Mac logs, and the input-design outputs are external
  (`/tmp`, T3, Mac). A repo-only reader cannot reproduce them; the suite itself is
  reproducible with `bash ios/test_mac_prep.sh`.
- No paid calls, no agents, no PR, no repository edits. When checked, the working
  tree at HEAD `4fda967` was clean; the reviewed code is pinned to
  `571d80d`/`15ab389`.

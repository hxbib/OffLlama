# First iPhone installation checkpoint

The Mac worker reported the following on 2026-11-04 after the user approved
the macOS codesign Keychain prompt. These are remote build/install results;
the Linux parent has not copied the full Mac logs into this checkout.

- Source: `4fda967` plus a one-line explicit `Void` task closure in
  `AppModel.loadScrubberNames`. The parent recovered the exact diff from the
  completed worker's activity and applied it to this checkout.
- Unsigned Release: passed. Signed Release: passed after automatic provisioning.
- Bundle: shipping GGUF size/hash, calibration at tau 0.90, skills, and rebuilt
  pinned llama framework with provenance all passed validation.
- Install: `devicectl` installed `com.habib.pocketglimmer` on the paired iPhone 17 Pro.
- Runtime: not verified. Device panel discovery failed twice, reporting Xcode
  selection and missing required agent-device version. No UI-tool fallback was used.
- Preserved: previous framework and pre-existing untracked files on the Mac.

Evidence remains under `/Users/habib/src/pocket-glimmer/` on the Mac:

- `docs/verification/MAC_BUILD_2026-11-04.md`
- `ios/.build/mac-build-fixed-2026-11-04.log`
- `ios/.build/mac-signed-team-2026-11-04.log`
- `ios/.build/mac-signed-check-2026-11-04.log`
- `ios/.build/mac-install-2026-11-04.log`

The installed build predates the pending time/constraint and saved-input repairs.
It establishes the packaging, signing, and installation path; a final integrated
build and phone acceptance are still required.

`mac_install_transcript_extract.json` retains the signed build, bundle-check,
and install output from the completed remote thread. Device installation IDs
are omitted from the extract; full logs remain at the paths above.

## First manual runtime check

The user confirmed that the app UI opens, then reported that the offline
“What is 2 + 2?” check produced no answer or an error. Settings showed
`PocketGlimmer.Calibration` code 2: “The bundled calibration file does not match
the shipping settings.” This fails before `LlamaCppEngine` initializes; successful
UI launch is not evidence of model loading or inference.

The Linux Swift probe passed every predicate on the checked-in calibration.
The Mac worker then reported that both debug and optimized Apple Swift probes
passed against source and signed-bundle files. Both had the expected calibration
SHA-256 and `defaultTau` bits `3feccccccccccccd`. The phone-only cause remains
unconfirmed.

Diagnostic commit `43d1811` on `fix/apple-calibration-validation` names every
failed predicate and the loaded file hash. The parent reviewed and cherry-picked
it as `647c261`. The worker reported a successful signed diagnostic build and
installation with exact model/calibration hashes. The user has been asked to
close and reopen the app and report the new result. No agent UI launch occurred.

Linux reproduction source and output are `calibration_guard_probe.swift` and
`calibration-guard-linux.txt`. The probe was compiled using Swift 6.1 with the
repository's `Decision.swift` and `Calibration.swift`; place the probe at
`main.swift` when compiling those three files together.

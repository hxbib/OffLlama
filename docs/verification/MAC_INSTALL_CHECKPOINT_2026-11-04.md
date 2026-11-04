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
build and phone acceptance are still required. The user's manual first-launch
observation has been requested while device automation is unavailable.

`mac_install_transcript_extract.json` retains the signed build, bundle-check,
and install output from the completed remote thread. Device installation IDs
are omitted from the extract; full logs remain at the paths above.

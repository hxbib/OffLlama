
## 2026-11-02 16:05 ET watchdog
- Mac (rebooted ~3:32 PM) now has Xcode 27.2 (build 27B52) at /Applications/Xcode.app; iOS 27.2 + Simulator SDKs present; ~11 GB free. xcode-select still points at CLT, so use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
- Installed XcodeGen 2.46.0 via brew on the Mac; ~/src/pocket-glimmer at 6123297; `xcodegen` generated app/PocketGlimmer.xcodeproj.
- Started unsigned simulator build (CODE_SIGNING_ALLOWED=NO, log /tmp/pg_simbuild.log on Mac, derived data /tmp/pgdd). Mac went offline mid-build; result unknown. Next: read the log, fix compile errors, then device build with Habib's free signing team + iPhone.
- PC and iPhone offline. No new box commits to back up besides this note.

## 2026-11-02 17:08 ET watchdog
- Mac, PC, iPhone all offline; simulator build result (/tmp/pg_simbuild.log on Mac) still unknown. Backup push not possible (no machine with gh online); box ahead of GitHub by cb1bed5 + this note.
- Committed training/data_scale/build_pool.py + dedupe_report.json (pool jsonl left untracked; regenerable). Data-scale retrain still awaits Habib's yes and a GPU machine.
- Next when Mac returns: read sim build log, fix compile errors, device build with free signing + iPhone; then demo video.

## 2026-11-02 18:05 ET watchdog
- Mac, PC, iPhone still offline (~2 h). Sim build result unknown; backup push impossible; box ahead of GitHub by cb1bed5, dd54c1a + this note.
- Posted blocker to room: need Mac + iPhone online tonight for sim build fix and device build; demo video due Nov 3.

## 2026-11-02 19:04 ET watchdog
- Mac, PC, iPhone still offline (~3 h). Sim build result unknown; backup push impossible; box ahead of GitHub by cb1bed5, dd54c1a, 86ccbce + this note.
- Blocker already posted to room at 18:05; not reposting. Next when Mac returns: read /tmp/pg_simbuild.log, fix compile errors, device build, demo video (due Nov 3).

## 2026-11-02 20:08 ET watchdog
- Mac back online (PC, iPhone still offline). Sim build log read: only failure was missing app/Frameworks/llama.xcframework (no Swift compile errors reached yet).
- Started on Mac: brew install cmake, clone llama.cpp at ddf48f8, ./build-xcframework.sh ios-device ios-sim (log /tmp/pg_xcfw.log). Next: copy into app/Frameworks, rerun xcodegen + sim build, then device build with iPhone + free signing.
- Backup pushed via Mac's gh login.

## 2026-11-02 20:21 ET (recorded 21:05 watchdog)
- Unsigned iOS Simulator build PASSES on Mac with no code changes, after copying llama.xcframework (llama.cpp ddf48f8) into gitignored app/Frameworks. Log /tmp/pg_simbuild2.log; app at /tmp/pg_dd/Build/Products/Debug-iphonesimulator/PocketGlimmer.app on Mac.
- Not launched: Mac has no iOS Simulator runtime installed (~8-10 GB download vs ~10 GB free).

## 2026-11-02 21:05 ET watchdog
- No change: Mac online, PC and iPhone offline; still no simulator runtime; 10 GB free. Mac checkout has untracked app/PocketGlimmer/Support/Info.plist (xcodegen output).
- Next: iPhone online + Habib picks his free Apple signing team in Xcode for a device build, or free ~15 GB on the Mac to download the simulator runtime. Then record the demo video (due Nov 3).

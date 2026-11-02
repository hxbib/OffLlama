
## 2026-11-02 16:05 ET watchdog
- Mac (rebooted ~3:32 PM) now has Xcode 27.2 (build 27B52) at /Applications/Xcode.app; iOS 27.2 + Simulator SDKs present; ~11 GB free. xcode-select still points at CLT, so use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
- Installed XcodeGen 2.46.0 via brew on the Mac; ~/src/pocket-glimmer at 6123297; `xcodegen` generated app/PocketGlimmer.xcodeproj.
- Started unsigned simulator build (CODE_SIGNING_ALLOWED=NO, log /tmp/pg_simbuild.log on Mac, derived data /tmp/pgdd). Mac went offline mid-build; result unknown. Next: read the log, fix compile errors, then device build with Habib's free signing team + iPhone.
- PC and iPhone offline. No new box commits to back up besides this note.

## 2026-11-02 17:08 ET watchdog
- Mac, PC, iPhone all offline; simulator build result (/tmp/pg_simbuild.log on Mac) still unknown. Backup push not possible (no machine with gh online); box ahead of GitHub by cb1bed5 + this note.
- Committed training/data_scale/build_pool.py + dedupe_report.json (pool jsonl left untracked; regenerable). Data-scale retrain still awaits Habib's yes and a GPU machine.
- Next when Mac returns: read sim build log, fix compile errors, device build with free signing + iPhone; then demo video.

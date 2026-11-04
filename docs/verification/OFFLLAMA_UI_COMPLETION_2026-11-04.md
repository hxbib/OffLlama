# OffLlama UI completion

Source commit `7857cd68d0106eae580ecfb49d28a17b54704e9b` on `feature/offllama-ui-completion`, built on
`origin/master` `c12182c` (includes the cloud-read outcome follow-up). Xcode 27.2 / iPhoneOS SDK 27.2.
Local logs live under `ios/.build/` (gitignored). The installed build is exactly this source commit.

## Results at a glance

| Item | Result | Evidence |
| --- | --- | --- |
| Core suite on merged tree | PASS, 235 tests, 1 pre-existing skip, 0 failures | `swift test` in `core/` |
| Rich-reply parser | PASS, 13 cases | `RichReplyTests` |
| Key entry and cloud settings logic | PASS, 12 cases | `KeyEntryTests`, `CloudSettingsCheckTests` |
| Real WebKit isolation (macOS WebKit, same controller source) | PASS, 0 escapes | `docs/verification/html-isolation-check-2026-11-04.txt` |
| Real Keychain, synthetic account, macOS | PASS | see Secrets below |
| Project generator | PASS, plus failure and lock cases | see Reproducible build |
| Resource gate `prepare --bundle-model --require-model` | PASS | `ios/.build/ui-completion-prepare.log` |
| Unsigned Release build and bundle check | PASS | `ios/.build/ui-completion-build-unsigned.log` |
| Signed Release build (team `2VGYC6S9F3`) | PASS | `ios/.build/ui-completion-signed.log` |
| Signed bundle check | PASS | `ios/.build/ui-completion-signed-check.log` |
| Install on paired iPhone 17 Pro (`devicectl`) | PASS | `ios/.build/ui-completion-install.log` |
| Launch, UI, runtime, app-switcher, VoiceOver, device OS | COULD NOT RUN | Device panel unavailable; no bypass used |

## 1. Inline HTML and SVG

`RichReply` (core) decides document boundaries. A document is a fenced block tagged `html` or `svg` (backtick or
tilde fence, up to three leading spaces), or a reply that is entirely one `<!doctype html>`, `<html>` or `<svg>`
document. Plain text, stray angle brackets, unterminated fences, other languages, oversize blocks (over 120,000
bytes) and documents beyond the fourth stay selectable prose. `IOSSkillRunner` `html_viz` now returns
`Chart ready: N bars` plus the chart in a fence long enough to survive backticks in the title, so the reply keeps the
content. The old imperative sheet was removed. Chat renders prose as selectable text and markup in an inline card
with Expand (full sheet) and Share source.

Isolation layers in `IsolatedHTMLController`: block-all content rules compiled and installed before the first load
(all subresource types plus child frames), a CSP in the page wrapper, JavaScript off, non-persistent data store, no
script message handler, no base URL, and a navigation delegate that allows only its own initial load and cancels
everything else (including `window.open`). The page loads once per distinct document, so unrelated SwiftUI updates do
not reload it.

Real WebKit evidence (`scripts/check-html-isolation.sh`, 21 hostile constructs in two modes, raw and wrapped): img,
srcset, link, `@import`, `@font-face`, CSS background, iframe, object, embed, video, audio, prefetch/preload, script,
SVG image/use/style import, relative image under `<base>`, meta refresh, form post, anchor, `target=_blank`, `tel:`.
The local server logged zero requests from isolated pages. A plain web view (control) reached the server 5 times, and
the same controller with a rule list that matches nothing (ablation) let 4 of 4 subresources through, so the content
rules, not the delegate, stop subresource loads. Own content still rendered in every case, page script did not run
or mutate the document, no message handler, non-persistent store, document URL is `about:blank`, and a repeated
`load` caused one load. This ran on macOS WebKit using the app's controller source; the iOS device WebKit build was
not exercised. With the page CSP, `form-action 'none'` stops a form submit before the delegate sees it, so the
delegate cancel for forms is covered by the raw mode only.

Not verified: how it looks and scrolls on the phone, Dynamic Type inside the web content, VoiceOver reading of web
content, and scroll-away/back reload behavior in the lazy chat list (a recreated card reloads, with its last measured
height remembered).

## 2. Protected settings

- `Keychain.swift` adds a presence check that never reads the secret, retries an update after a duplicate-item race,
  and keeps update-in-place so a failed replacement preserves the old key.
- `KeyEntry` (core) trims pasted keys, rejects keys with inner whitespace, and reports `saved`, `replaced`,
  `failed(status)` and removal outcomes. A failure with no earlier key says no key is saved, never "retained".
  Messages contain only numeric Keychain status, never the entered value or provider text. Tests use synthetic values.
- `CloudSettingsCheck` (core) asks `MetaAPI.requireStandardMode` and `OpenAICompatibleBrain.validConfiguration`, so
  there is no second allowlist. It reports not configured, needs a key, enabled, or refused (contributor model, empty
  model, bad base URL) and warns when the custom link is plain `http`.
- Settings keeps model and URL as drafts, writes them only on Save, shows "Changes are not saved yet", and ends Save
  with a per-route enabled or refused status. No reveal toggle. Entered key text clears on disappear and whenever the
  scene is not active; saved state is shown separately.
- `PrivacyShield` puts an opaque window above every presentation, sheets included, while a scene is inactive.
- Real macOS Keychain run with a synthetic account (created, replaced, empty write rejected with -50 and old value
  kept, removed, second remove -25300 which the store maps to success). The account was deleted. The iOS
  accessibility attribute behaves differently on a phone, so phone Keychain behavior is not verified.
- Open for the parent: `CloudSettings.chain()` in `AppModel.swift` still builds a Meta brain for a contributor model.
  That brain refuses at request time before any network call, so nothing is sent, but the chain should call
  `CloudSettingsCheck.meta` so the runtime and Settings agree. I did not touch `AppModel`.

## 3. Native input and polish

Keyboard Done on Chat, Settings and Glimpse now resigns any responder through one helper; the draft-card fields
share the Chat toolbar. Removed sparkle motifs (tab, onboarding, Glimpse button). Visible Files path says OffLlama.
Composer icons scale with Dynamic Type and have 44 pt targets, send has a label, scroll and symbol motion respect
Reduce Motion. The hold-to-record button is now a waveform labelled "Hold to record and upload", with a hint that it
uploads to Muse Voice Transcribe, needs internet and a Meta key, and is not Apple Dictation. Settings explains Dictate
Text, then Ask OffLlama with Request set to the Dictated Text, then the Vocal Shortcut "Hey OffLlama", without
promising locked or offline-in-every-language operation. The privacy sheet now says "Cloud request text" and "Masked
on device. A failed request may already have reached the provider."

## 4. Reproducible build

`scripts/generate-offllama-project.sh` now writes the generated plist to `ios/.build/generated/Info.plist` (stable,
gitignored, no `/tmp` dependency), uses a unique temp spec, takes a lock so concurrent runs cannot overwrite each
other, excludes the preserved `app/PocketGlimmer/Support/Info.plist` from the sources, and exits non-zero if either
transformation does not match exactly once. Checked: a clean run produced a project whose `INFOPLIST_FILE` points at
the stable path; a spec with a changed plist path failed with a clear message and left no spec behind; an existing
lock failed with a clear message. The preserved plist and `MAC_BUILD_2026-11-04.md` hashes were identical before and
after. `ios/mac_prep.sh` now generates through this script, since its plain `xcodegen generate` would overwrite the
preserved plist.

Bundle facts from the built apps (unsigned and signed, read from the bundle, not the source tree): display name
OffLlama, identifier `com.habib.pocketglimmer`, icon `AppIcon` (1024 px asset catalog entry from the approved
llama image, compiled sizes present), model SHA-256
`a5c60a8836aa73adeb847185aa30184cd9c33c522185f59fa9ac55a9d00782c2` (807,694,080 bytes), calibration SHA-256
`b9ce25b5223103944803c2668784c484ac7eee75b33aa984e62185728970a8f1`, tau 0.90, fewShot, 31 prior sets, pinned llama
framework provenance verified. The microphone prompt text now matches the waveform button.

## 5. Signed build and install

The earlier "no account for team" failure was a wrong team id, not a missing sign-in. The successful earlier signed
build used `DEVELOPMENT_TEAM=2VGYC6S9F3`; the later failing run used a different id. Reusing `2VGYC6S9F3` with
`-allowProvisioningUpdates` signed without a prompt. `codesign --verify --deep --strict` passed, TeamIdentifier
`2VGYC6S9F3`. `devicectl device install app` to Habib's iPhone (iPhone 17 Pro) succeeded and `devicectl` lists
OffLlama 1.0 (1) as installed. Install is not launch evidence. The phone's OS version was not recorded.

```sh
sh scripts/generate-offllama-project.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project app/PocketGlimmer.xcodeproj \
  -scheme PocketGlimmer -configuration Release -destination 'platform=iOS,id=00008150-000A59811180401C' \
  -derivedDataPath ios/.build/SignedDerivedData -allowProvisioningUpdates DEVELOPMENT_TEAM=2VGYC6S9F3 build
xcrun devicectl device install app --device 00008150-000A59811180401C \
  ios/.build/SignedDerivedData/Build/Products/Release-iphoneos/PocketGlimmer.app
```

## 6. Remaining phone checks (nothing below was run)

1. Launch OffLlama, confirm the OffLlama name and llama icon on the Home Screen.
2. Offline (Airplane Mode) ask "what is 2+2". The earlier 2+2=4 observation was on an old diagnostic build.
3. "Make a chart: rent 1200, food 400, transit 130" renders an inline chart; Expand and Share source work; scrolling
   the chat away and back is acceptable; Dynamic Type and VoiceOver on the card.
4. A cloud reply containing a fenced html block renders inline and plain replies are unchanged (needs a Meta key).
5. Settings: enter a synthetic key, Save, confirm the field empties and status shows saved. Replace with a second
   key. Remove it. Try model `muse-spark-1.3-contributor` and a bad base URL and confirm the refused messages.
6. Background the app from Settings with text typed in a key field, reopen, field is empty.
7. App switcher: confirm the OffLlama lock cover shows instead of chat, a photo or Settings, including with a sheet
   open.
8. Keyboard Done dismisses from the composer, a draft card field, Settings fields and Glimpse fields.
9. Waveform button wording; keyboard Dictation into the composer; Shortcut Dictate Text, Ask OffLlama, "Hey OffLlama".
10. The messaging and multi-step action fixes in other workstreams are not covered by this UI build.

## Ownership notes

`AppModel.swift`, `ActionPlanner`, `Assistant`, `EffectLedger`, `CloudPrivacy`, `CloudBrain` and `PocketEffects` were
not modified. The Info.plist and `MAC_BUILD_2026-11-04.md` preserved files remain untracked and byte-identical.

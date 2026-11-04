# First OffLlama UI checkpoint

Remote commit `4d912de` on `feature/offllama-native-polish` was source-reviewed and
integrated as `7b4f6b9`. It adds the visible name and icon asset, Shortcut titles,
concealed replacement-key fields with separate saved status, Apple Dictation/Vocal
Shortcut setup text, chat/settings/Glimpse keyboard dismissal and selectable replies.

The remote worker reports an unsigned Release build pass. Retrieved command output
shows the built bundle's display name is OffLlama and its identifier remains
`com.habib.pocketglimmer`. Source model and calibration SHA-256 values matched the
shipping files. Those commands hashed source resources, not the built bundle.
The worker did not complete a signed build, install, bundle hash comparison or phone
interaction. This is a partial source checkpoint, not a ready phone release.

The original icon source is an opaque 1254-square PNG. The committed app asset was
compiled by Xcode according to the worker; final bundle icon validation is still due.

Open assigned scope includes inline HTML and fixtures, draft-edit keyboard dismissal,
remaining brand motifs, useful settings validation, explicit key removal and key-save
failure feedback, secret-safe background presentation, final polish, exact bundle
resources, signing and installation. Chat input remains disabled while busy until
durable admission is wired. The new pre-send readiness check alone is not durable
input preservation.

The Mac has preserved untracked `app/PocketGlimmer/Support/Info.plist` and
`docs/verification/MAC_BUILD_2026-11-04.md`. The previous worker generated a temporary
project that points to `/tmp/offllama-build-info.plist`; the next build must regenerate
from the tracked specification while preserving the user's plist. The temporary
spec needed that plist excluded from the source copy list to avoid duplicate output.

A later incoming Mac report states 5.1 GiB free, unsigned build and bundle validation
passed at `4d912de`, but signing failed because Xcode found no account for the selected
team and no matching profile. Its source thread was not identified in the message.
Before concluding the user must sign in again, reconcile the chosen team and profile
with the earlier successful signed-build logs. There is no new installed SHA.

The remote project thread list showed the known Mac tasks completed at handoff.
The replacement owns the existing checkout exclusively and must inspect any remaining
build process before regenerating it. Device-panel automation remains unavailable;
no command-line UI bypass is authorized.

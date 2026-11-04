# OffLlama visual pass

The user explicitly chose OffLlama as the next build's visible name. Preserve the
existing bundle identifier, on-device data, provisioning and internal Swift package
names so this is an update to the installed app. Update visible app, onboarding,
Settings and Shortcut labels together. Runtime reasoning remains Meta-only.

Preserve the indigo accent, native SwiftUI controls and system typography. Make the
composer, review cards and result states easy to use. Provide keyboard dismissal,
Dynamic Type, VoiceOver labels, usable touch targets and Apple keyboard dictation.
Keep repeated interactions immediate and honor Reduce Motion.

Use [Apple's Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines),
including [keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards),
[accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
and [app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons).
The user also requested [Emil Kowalski's design engineering skill](https://github.com/emilkowalski/skills/blob/main/skills/emil-design-eng/SKILL.md).
Apply its interaction principles to native controls rather than importing web snippets.

The installed Impeccable context launcher failed with permission denied. Its documented
fallback uses the app's existing UI and source. No design-engine inspection or phone
screenshot is claimed. Device-panel automation is currently unavailable.

`assets/offllama-icon-source.png` is the original generated icon, an opaque1254×1254
RGB PNG. Native asset packaging must provide Xcode's required sizes. The earlier
pocket-shaped icon was superseded by the user's explicit rebrand. Neither uses
Meta's logo. The originals remain in the generation tool's output directory.

All API-key fields must conceal input, use Keychain storage and avoid plaintext
read-back into visible views. Show saved status separately. No reveal toggle is
needed for the demo. Errors, diagnostics and exported logs must not contain keys.

Generated using the built-in image-generation tool on2026-11-04. Prompt:

> Use case: logo-brand. Asset type: final opaque square iOS app icon for OffLlama (offline + Llama), full bleed, no pre-rounded outer corners. Make an original, extremely simple ivory-white stylized llama head silhouette with two unmistakable upright long llama ears and a calm rounded profile, one small amber circular glimmer beside it. Refined warm personality for an offline-first personal assistant. Solid deep indigo-blue background matching app accent RGB 92 107 255, subtly luminous tactile depth, crisp shapes, no busy detail. Centered mark fills about 60 percent, instantly recognizable when small, strong negative space. No text, no letters, no star, no sparkle, no infinity loop, no Meta/Gemini logo, no device mockup, no border, no watermark. Output actual icon artwork only, 1024 by 1024 pixels.

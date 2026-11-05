# Skills: open-world phone actions without retraining

> **Current OffLlama build (`4376810`).** Apple TV opens tv.apple.com search for
> the show after a review card; it needs no Shortcut and does not start playback.
> The eight "PG" helper skills (alarm, timer, note, flashlight, Focus, Low Power,
> weather, open app) are unavailable and never launch a Shortcut. Running a
> Shortcut by name still works if you already created it. Older text below that
> says otherwise describes the earlier Pocket Glimmer design.

Pocket Glimmer's 1B model was trained on 12 typed decisions (core/Sources/PocketCore/Decision.swift). Six of them are
concrete tools (reminder, event, calendar lookup, text, contact lookup, memory recall). Everything else a person asks a
phone to do ("DM Sam on Instagram", "wake me at 6", "summarize my last few emails", "chart these numbers") goes through
the **Skill Registry**: a data file of capabilities, and **one extra dynamic decision** the same 1B answers in one forward
pass. Adding an ability means adding about 10 lines of JSON. No retraining.

Code: `core/Sources/PocketCore/Skills.swift` (model, registry, retrieval, offline chart),
`core/Sources/PocketCore/ActionPlanner.swift` (two-stage routing, args, confirm, execution),
`app/PocketGlimmer/Actions/SkillRunner.swift` (iOS execution), `app/PocketGlimmer/Intents/SkillIntents.swift`
(share sheet / Shortcuts / Siri), `app/PocketGlimmer/Resources/Skills/builtin.json` (the registry as data),
tests in `core/Tests/PocketCoreTests/SkillsTests.swift`.

## Two-stage routing

Explicit app/feature requests can also try `skillPick` when the trained route falls below threshold. This includes anchored message commands such as “Text Mom…”. They still need skill confidence ≥0.90 before planning an action; an uncertain explicit message asks for clarification. The real-engine rehearsal in [ENGINE_REHEARSAL_NOV4.md](ENGINE_REHEARSAL_NOV4.md) records where the exact demo commands remain uncertain.

1. **Stage 1, trained `route`** (unchanged): answer_local / tool / escalate_cloud / clarify.
2. **Stage 2, trained `toolChoice`** (unchanged). If it picks one of its six tools above τ, today's path runs exactly as
   before. The skill path runs only when
   - toolChoice says `none` (chosen, or the fallback because confidence was below τ), or
   - the trained tool can't serve an app or feature the user named outright (`send_message` + "on Instagram",
     `create_reminder` + "wake me" / "alarm"). That table is small and explicit: `ActionPlanner.overridable`.
3. **Skill retrieval**: BM25 over each skill's title, aliases and examples (field-weighted), plus a bonus for matching a
   multi-word alias, plus the cosine from `HashingEmbedder`, the same offline character-trigram embedder memory uses
   (it catches "insta", "msg" and typos). Pure Swift and deterministic. It returns the top k ≤ 7 skills.
4. **`skillPick`, a dynamic decision built exactly like `contactPick`**: options `s0…s6` hold the retrieved skills'
   titles plus one example each, and the last option is `ask` ("None of these: ask the user"). The question is "Which
   phone action does the user want?". One forward pass reads the letter logits, applies contextual calibration (prior key
   `skillPick#N`, the same mechanism as `contactPick#N`), softmax, then the τ gate.
   - **Below τ → clarify** with the top 3 skills: "Did you mean: Instagram DM, X (Twitter) DM or WhatsApp message?"
     The trained decisions already "know when they don't know"; this carries that to open-world actions.
5. **Argument filling**: regexes per `ArgSpec` (contact names, `@handles`, quoted text, text after a separator such as
   "that", "saying" or ":", or the remainder after the contact for direct messages, times, durations, URLs, numbers,
   places). This is a bounded heuristic, not general natural-language parsing. Contacts with several matches go through
   the **trained `contactPick`**. Social handles never touch Contacts. If a required argument is missing, it asks for it
   ("What time?").
6. **Confirmation**: the trained `confirmBeforeAct` runs, then the **hard rule**: `skill.confirm` forces confirmation.
   Every message, social or email skill has `confirm = true`. The registry enforces this on load, so a JSON file can't
   turn it off. Anything that spends money (Uber) or calls someone also confirms.
7. The result is `PlannedAction(tool: "skill:<id>", args:)`, so the existing decision card, JSON tool-call view and
   Confirm button work unchanged. On Confirm, `Assistant.execute` sends handlers that are existing tools
   (`send_message`, `send_email`, EventKit) to `SystemActions`, and everything else to the iOS `SkillRunner`.

**The trained model is untouched.** No option id, label, letter, question or few-shot exemplar changed. `skillPick` is
appended last in `DecisionType` (existing raw values unchanged). It is not in `staticSets` and has no shots. It is a
zero-shot use of the multiple-choice skill the 1B was distilled for, like `contactPick` with runtime candidates.
The saved [27-item diagnostic probe](../eval/skills/SKILL_PROBE.md) retrieved the intended skill on 27/27 items,
selected it at argmax on 25/27, and accepted 15/27 at τ=0.90 with 15/15 correct. These author-written examples are
not a gold benchmark or covered by the cal180 risk calculation. `Reflex.measureSkillPickPriors()` produces the
content-free priors; the app uses the bundled threshold of 0.90.

## Honest iOS limits

- **No app can read or send inside Instagram, X or WhatsApp.** There is no public API for a third-party app to read DMs
  or press Send in another app, and Pocket Glimmer does not tap the screen. For Instagram we open
  `https://ig.me/m/<handle>` (Instagram's own link to a DM thread), copy the message to the clipboard, and say so:
  "Opened Instagram DM with @sam; message copied to clipboard · paste and tap Send". X only prefills a DM when you give it
  a numeric `recipient_id` the app can't know, so we open `x.com/<handle>` and copy the text. WhatsApp's documented
  `whatsapp://send?text=` prefills the text, and you choose the chat.
- **iMessage / SMS and email** use the system compose sheets (MessageUI), pre-filled. You tap Send, and the status line
  reports what you actually did (sent / cancelled / saved as draft).
- **"Reply to every reel with haha nice"** is saved as a rule in memory (provenance `user_stated`) and explained
  honestly: iOS lets no app answer Instagram DMs. The closest real automation is Shortcuts → Automation → Message, which
  covers iMessage only.
- **Alarms, timers, toggles, notes, weather**: there is no public URL scheme for them, so they run through tiny
  user-installed Shortcuts that call Apple's built-in actions. We open `shortcuts://run-shortcut?name=…&input=text&text=…`.
  If a Shortcut isn't installed, the Shortcuts app says so. Nothing claims success that didn't happen.
- **Apple TV playback** is only a Shortcut hand-off. There is no established public playback API or callback, so the app
  cannot tell whether the user's Shortcut exists or ran. It reports only the hand-off. The Shortcut is user-configured
  and device-dependent.
- **Mail can't be read by apps.** "Analyze my last few emails" works through the share sheet: select messages in Mail →
  Share → **PG Share Emails** → Pocket Glimmer summarizes them on device. Long threads escalate to Muse Spark 1.3 only
  when online and configured, and only if the `sensitivity` decision says the text is OK to send. It is scrubbed first.
- **Documents**: PDF (PDFKit), .txt and .md. Word/.docx is not supported on device.
- **HTML visualization** works offline with no model: numbers in the text ("rent 1200, food 400") become an inline SVG
  bar chart in a sheet (WKWebView, JavaScript off). The 1B only writes the chart title (≤ 12 tokens).
- "Offline" in the table means the decision and the hand-off work in airplane mode. Delivery, like an iMessage going
  out, still needs a network later.

## Catalog (36 built-in skills)

| id | what it does | invocation | offline | confirm |
|---|---|---|---|---|
| `imessage_send` | Send an iMessage / text | native `send_message` | yes | yes |
| `instagram_dm` | Instagram DM (+clipboard) | URL `https://ig.me/m/{contact}` | no | yes |
| `x_dm` | X (Twitter) DM (+clipboard) | URL `https://x.com/{contact}` | no | yes |
| `whatsapp_send` | WhatsApp message | URL `whatsapp://send?text={body}` | no | yes |
| `instagram_autoreply` | Auto-reply rule (Instagram / any app) | native `autoreply_rule` | yes | yes |
| `email_compose` | Write an email | native `send_email` | yes | yes |
| `email_digest` | Summarize my recent emails | native `email_digest` | yes | yes |
| `reminder_create` | Create a reminder | native `create_reminder` | yes | no |
| `calendar_create` | Add a calendar event | native `create_event` | yes | no |
| `calendar_find` | Check my calendar | native `find_event` | yes | no |
| `alarm_create` | Set an alarm | Shortcut “PG Create Alarm” (input `{time}\|{label}`) | yes | no |
| `timer_start` | Start a timer | Shortcut “PG Start Timer” (input `{duration}`) | yes | no |
| `appletv_play` | Apple TV: find a show ("open Ted Lasso on Apple TV") | Opens tv.apple.com search for `{show}` after review; no Shortcut; does not choose an episode or start playback | no | no |
| `call` | Phone call | URL `tel:{phone}` | yes | yes |
| `facetime` | FaceTime | URL `facetime:{phone}` | no | yes |
| `maps_directions` | Directions in Maps | URL `maps://?daddr={place}` | no | no |
| `uber_ride` | Request an Uber | URL `uber://?action=setPickup&pickup=my_location&dropoff[formatted_address]={place}` | no | yes |
| `web_search` | Search the web | URL `https://duckduckgo.com/?q={query}` | no | no |
| `open_url` | Open a link | URL `{url}` | no | no |
| `open_app` | Open an app | Shortcut “PG Open App” (input `{app}`) | yes | no |
| `run_shortcut` | Run a Shortcut by name | URL `shortcuts://run-shortcut?name={name}&input=text&text={text}` | yes | no |
| `create_shortcut` | Create a new Shortcut | URL `shortcuts://create-shortcut` | yes | no |
| `music_play` | Play music | URL `music://` | yes | no |
| `spotify_play` | Spotify | URL `spotify:search:{query}` | no | no |
| `notes_create` | Create a note | Shortcut “PG Create Note” (input `{text}`) | yes | no |
| `photos_open` | Open Photos | URL `photos-redirect://` | yes | no |
| `analyze_document` | Analyze a document | native `analyze_document` | yes | no |
| `html_viz` | Make a chart / HTML visualization | native `html_viz` | yes | no |
| `translate` | Translate a phrase | model (generation) | yes | no |
| `summarize_text` | Summarize shared text | model (longContext) | yes | no |
| `device_status` | Battery & storage | native `device_status` | yes | no |
| `flashlight_toggle` | Toggle flashlight | Shortcut “PG Toggle Flashlight” | yes | no |
| `focus_toggle` | Toggle Do Not Disturb | Shortcut “PG Toggle Focus” | yes | no |
| `low_power_toggle` | Toggle Low Power Mode | Shortcut “PG Toggle Low Power” | yes | no |
| `weather` | Weather | Shortcut “PG Weather” (input `{place}`) | no | no |
| `memory_recall` | Recall something I told you | native `search_memory` | yes | no |

Messaging and email skills always confirm. `email_digest` is read-only, but it's in the email category, so it confirms
too: one extra tap.

## Shortcuts to install (each is 1 to 3 built-in actions)

Not used by the current build: these helper skills are unavailable. Kept as the earlier design.

| Shortcut name | Actions |
|---|---|
| PG Create Alarm | Receive **Text** input → Split Text by `\|` → Clock › **Create Alarm** (time = item 1, label = item 2) |
| PG Start Timer | Receive Text → Clock › **Start Timer** (duration = input) |
| PG Open App | Receive Text → **Open App** (app = input) |
| PG Create Note | Receive Text → Notes › **Create Note** (body = input) |
| PG Toggle Flashlight / PG Toggle Focus / PG Toggle Low Power | **Set Flashlight** / **Set Focus** / **Set Low Power Mode** → Toggle |
| PG Weather | **Get Current Weather** (location = input or Current Location) → Show Result |
| PG Share Emails | Show in Share Sheet, receive **Text / Mail** → **Pocket Glimmer: handle text** (Text = Shortcut Input, Source = `mail`) |
| PG Send Message (existing fallback) | Receive Text → Split by `\|` → **Send Message** (recipient = item 1, message = item 2) |

## Add a skill (no retraining)

Drop a JSON file into **Files › On My iPhone › Pocket Glimmer › Skills/** (user skills), or add it to
`app/PocketGlimmer/Resources/Skills/builtin.json` (shipped skills). A skill with an existing id replaces that skill.

```json
[{
  "id": "threads_dm",
  "title": "Threads DM",
  "category": "social",
  "invocation": { "type": "url", "template": "https://www.threads.net/@{contact}" },
  "argSchema": [ { "name": "contact", "kind": "handle", "required": true }, { "name": "body", "kind": "text" } ],
  "clipboard": "{body}",
  "offlineCapable": false,
  "examples": ["dm sam on threads saying congrats"],
  "aliases": ["threads", "threads dm"]
}]
```

Invocation types: `{"type":"url","template":…}` (placeholders are percent-encoded), `{"type":"shortcut","name":…,"input":…}`,
`{"type":"native","handler":…}` (handlers: `send_message`, `send_email`, `create_reminder`, `create_event`, `find_event`,
`lookup_contact`, `search_memory`, `device_status`, `analyze_document`, `html_viz`, `autoreply_rule`, `email_digest`),
`{"type":"cloud","kind":"needsOnline|longContext|generation"}`. Argument kinds: `contact`, `handle`, `text`, `datetime`,
`url`, `document`, `app`, `duration`, `number`, `place`, `query`. A `social`, `message` or `email` skill is always
confirmed, even if the JSON says `"confirm": false` (tested in `SkillsTests.testJSONRoundTripAndHardRuleSurvivesJSON`).

## Demo: "DM Sam on Instagram saying congrats"

1. `route → tool`, then `toolChoice → send_message`. "On Instagram" is a feature the trained tool can't serve, so the
   planner switches to the skill path.
2. Retrieval puts **Instagram DM** first. The decision card shows `skillPick → s0 "Instagram DM (e.g. dm sam on instagram
   saying congrats)"` with its confidence bar. Below τ, the reply is instead "Did you mean: Instagram DM, …?"
3. Arguments: `contact = sam` (a handle, so no Contacts lookup), `body = congrats`. Tool-call JSON:
   `{"tool": "skill:instagram_dm", "arguments": {"body": "congrats", "contact": "sam"}}`.
4. `confirmBeforeAct` runs, and the hard rule forces Confirm: "Instagram DM: @sam · “congrats”? (message goes on your
   clipboard, you paste and send)".
5. On Confirm: `UIPasteboard` gets "congrats", and `https://ig.me/m/sam` opens the Instagram DM thread. Status: "Opened
   Instagram DM with @sam; message copied to clipboard · paste and tap Send". Paste and send in Instagram.

Without a registry (`Assistant.skills == nil`) the assistant behaves exactly as before. The existing tests run that way.

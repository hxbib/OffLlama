# Demo script, 3:00 (draft)

Note: the percentages and ms below are placeholders for the script; say whatever the phone actually shows.

Setup: iPhone 17 Pro mirrored (QuickTime). Model loaded. Memories seeded *live during rehearsal, by talking to it*
(never by inserting rows). Telemetry chart shows days of real use. Shortcuts automations installed.

**0:00–0:20 · The hook: airplane mode, instant action**
- Swipe down, tap **Airplane Mode** on camera. Pill turns green: "Offline · fully on device".
- Say/type: *"Remind me to call Mom at 7."*
- The Reflex strip flashes `route → tool 97% · 38 ms`, `toolChoice → create_reminder 99%`, and the reminder exists.
- VO: "No internet. A Meta model on this phone just made four decisions, and it tells you how sure it was."

**0:20–0:50 · Confidence is the product**
- *"Text Sam I'm running late."* Two Sams in Contacts → `contactPick` picks **Sam Ortiz (brother)** at 91%, then shows a **Confirm** button (messages always confirm).
- *"Move it."* → `route → clarify`, low confidence shown in orange: it asks instead of guessing.
- VO: "Every choice is one forward pass over a multiple-choice question. Below the threshold, it escalates or asks."

**0:50–1:30 · Memory → proactive nudge**
- Earlier: *"I'm out of oat milk."* → "Remembered: User needs to buy oat milk" (expires in 7 days). Open **Memory** tab: shown, swipe-to-forget.
- Trigger the "Arrive at Trader Joe's" automation (run it from Shortcuts on camera).
- Notification: **"You're at Trader Joe's — You said you're out of oat milk."** Subtitle: "Reflex 88% sure".
- Show the same trigger at "the office" → nothing. VO: "Memory decides when to speak up. Still offline."

**1:30–2:10 · Hard question escalates to Muse**
- Turn Airplane Mode off. Pill: "Online · cloud brain available".
- *"Compare paying down my 6% loan vs investing, given what you know about me."*
- Strip: `route → escalate_cloud`, `sensitivity → ok`. Answer badge: **Meta Model API · muse-spark-1.3**.
- Tap the info: names and numbers were masked as `[PERSON_1]` before leaving the phone.

**2:10–2:40 · The Reflex chart (real telemetry)**
- **Reflex** tab: line of "share handled on device" per day, with decision counts above each point. Export CSV on camera.
- VO: "Every point is a logged decision from this phone. As the small model learns, more decisions stay here, in milliseconds."
- Rule: if the curve isn't rising yet, say so. Never fake or backfill data.

**2:40–3:00 · Distillation close**
- One slide: Muse Spark Open + Muse Glimmer label the same questions with probabilities → disagreement becomes "escalate" → LoRA on the answer letter → calibrated → back on the phone.
- Show the before/after table from `eval/score_decisions.py --compare` (base 1B: 53% accuracy, 11% handled; distilled: real numbers once trained).
- Close: "Big Meta models teach. A small Meta model acts. Your data stays in your pocket."

Fallbacks: if a live decision is slow, the Reflex tab still shows the logged rows. If cloud keys aren't approved, skip 1:30–2:10 and say "with a key, this goes to Muse Spark".

# Gold labeling rules (hand-written, 2026-10-31)

All items were written and labeled by hand against these rules. No model was used to label any item.
Each item is meant to have exactly one defensible answer under its rule; items where two answers were defensible were left out.

- **route**: tool = asks for a phone action (reminder, calendar, message, contact, memory); answer_local = greeting/thanks/small arithmetic/translation/short rewrite; escalate_cloud = long writing, analysis, advice, multi-step planning, comparisons; clarify = refers to "it/that/the thing" with no object.
- **toolChoice**: verb decides (remind → reminder; schedule/put on calendar → event; what's on / when is → find_event; text/tell/message → send_message; number/email/address → lookup_contact; "what did I say/tell you" → search_memory; anything outside the 6 tools → none).
- **rememberOrNot**: lasting personal facts → remember_fact; facts that stop being true within days → remember_temporary; questions, commands, chit-chat → no.
- **memoryConflict**: the fact changed → update; both can be true → keep_both; joke, hypothetical, restatement → ignore_new.
- **notificationTriage**: safety, security, family emergency, imminent travel → interrupt; personal or work info that can wait → digest; marketing, engagement bait, newsletters → ignore.
- **confirmBeforeAct**: reminders, events, and lookups the user asked for → act; messaging other people, deleting, paying or buying → confirm.
- **nudgeNow**: the trigger's place or person matches the memory → nudge; unrelated → skip; related but the memory names a later moment → later.
- **timing**: no time given, or "now" → now; a single stated time or offset → at_time; arrive/leave a place → on_arrival; every/each → recurring.
- **sensitivity**: health, finances, credentials, IDs, intimate details → sensitive; everything else → ok.
- **answerability**: a 1B model can answer offline (greeting, single-word translation, small arithmetic, spelling, a one-line rewrite or antonym) → yes; needs fresh facts, long output or deep reasoning → no.
- **contactPick / eventPick**: the relation, name, or time named in the request picks exactly one candidate → that one; if it fits two or more → ask.

# INDEPENDENT NOTES — recorded BEFORE reading Grok IOS27_END_TO_END_JOURNEYS.md
# Investigator: Muse Wonder 1.0 (Muse Code ACP in T3 Code), max effort, 2026-11-04
# Baseline: 009430f (HEAD). Source read at working tree == HEAD (clean).

## Code evidence gathered first (file:symbol)
- AppModel.swift:52 chat:[ChatItem] in-memory only, ChatItem not Codable; :63 onboarded UserDefaults only persistence besides SQLite.
- AppModel.send:199 busy gate returns canned string; :218 pending PlannedAction stored only in chat[i].pending; confirm:233/cancel:256 operate only on in-memory chat.
- AppModel.bootOnce:114 SQLite pocket.sqlite in ApplicationSupport/PocketGlimmer; findModel:88 gguf in Documents/bundle.
- PocketGlimmerApp.swift: no scenePhase, no state restoration; RootView TabView only.
- SystemActions.requestAccess:15-19 try? swallows Reminders+Events+Contacts; called ONLY from OnboardingView:29. No openSettings anywhere (grep 0).
- SystemActions.searchContacts:21 unifiedContacts matchingName prefix(7); addresses(for:):114 .first contact, phones.prefix(1) in send_message:79; displayName strips "(hint)".
- SystemActions.date(from:):128 NSDataDetector firstMatch, no tz phrase; create_event:64 default now+1h, fixed 1h duration; create_reminder:56 Calendar.current components.
- Assistant.toolPath:202-211 contactPick>ask -> .clarify(text list); no pending clarify state stored; handle() stateless per utterance except MemoryStore.retrieve.
- Assistant.handle:107 memory upsert BEFORE route/tool; exception later loses 'remembered' surface but fact persisted.
- Assistant:230 send_message always needsConfirmation + confirmBeforeAct decision also runs; ChatView Bubble:79 Confirm/Cancel only, no Edit; accessibilityHint "Runs {tool}".
- ActionPlanner.planSkillCore:119 same contact pattern; :137 skill.confirm hard rule.
- SkillRunner.openURLSkill:51 clipboard written BEFORE url open:57; runShortcut:83 opened==handed-off only.
- Skills.swift SharedInbox:286 in-memory, 900s, take()=consume-once; AppModel.send busy early-return BEFORE SharedInbox.put (send:199 vs 202).
- Intents: ProactiveTriggerIntent openAppWhenRun=false -> handleTrigger boots GGUF if needed; Ask/HandleText/RunSkill openAppWhenRun=true -> send() (busy string can be returned as Siri answer).
- AppModel.handleTrigger:248 notification UUID, no category/actions/delegate/deeplink; Onboarding:31 notification auth try?; morningBrief meta last_morning_brief set after nudge decision (Proactive:111) regardless of notification authorization.
- VoiceCapture: hold DragGesture only; begin:104 offline->note, :105 meta_key required, :106 mic permission note text-only; finish:114 busy->recording dropped; AVAudioRecorder 60s cap.
- CameraGlimpse/GlimpseView: online+meta_key gated; SegmentOverlay accessibilityLabel count only, no per-object text list.
- Views accessibility: only 8 accessibilityLabel hits total (grep). No DynamicType/reduceMotion handling found. Confidence color-only + %.
- OptionSets.timing + notificationTriage defined Decision.swift:105,85 but never used in Assistant/SystemActions (grep: only pg-cli).
- No delete/edit/reschedule tool: toolChoice 6 tools Decision:60; EK identifiers never returned/persisted in perform() return strings.
- MemoryView:59 swipe Forget only; no delete-all, no inline undo for 'Remembered:' system line (AppModel:223).
- Proactive.isWithin birthday: en_US_POSIX "MMMM d" only; MemoryProfile.tasksBoard due = expiresAt (TTL expiry, not user due date).
- project.yml deploymentTarget iOS 18.0; entitlements empty {}; Info usage strings for reminders/calendars/mic/camera/photos/contacts.
- builtin.json 36 skills (python count at 009430f).

## Independent candidate gaps (pre-Grok)
J1 Process-death loss of pending confirmation + whole chat (kill while Confirm sheet pending / after clarify).
J2 Stateless clarify: "Which Sam?" answer as next utterance restarts pipeline; no tappable candidates, no pending-pick state.
J3 Permission denial/limited/revocation: no status check before actions, no recovery UI/deep link; limited Contacts silently shrinks search -> false "couldn't find"; EK denied -> generic Error:; onboarding one-shot bundle.
J4 Wrong-recipient risk: disambiguated label stripped to name, re-lookup .first, first phone only; "Mom" alias not resolved via memory aliases to contact.
J5 Time/tz/DST: confirmation prompt shows raw phrase, not resolved absolute date/tz; NSDataDetector local tz; event default+1h silent; no recurrence despite timing set unused; travel wall-clock shift.
J6 No undo/edit/delete/reschedule of created reminder/event; no ID retention; editing journey absent.
J7 Accessibility: hold-only voice (VoiceOver/Switch/motor), offline voice dead (cloud-only) though on-device SpeechAnalyzer iOS26+ exists; Glimpse results not enumerated for VoiceOver; color+caption heavy UI; repeat double-confirm burden.
J8 Partial outcomes: memory written before action fails; SharedInbox consume-once lost on failure; busy drops voice recording + intent shares; cloud throw = generic Error no retry/offline fallback for that turn.
J9 Notification handoff dead-end: nudge cannot be acted/snoozed, tap does nothing defined, denied auth silently eats morning brief.
J10 Handoff honesty vs completion: Shortcut missing still "handed to", user must notice in Shortcuts app; compose-sheet is real observed result (sent/cancelled) — good — but URL skills stop at opened.
J11 Re-entry/retention: next-day return shows empty chat; Glimpse photo/result not retained; kept recordings accumulate unmanaged; no delete-all/export of chat (chat volatile by design? unstated).
J12 Caregiver/student/traveler specifics: repeated trusted message still double-confirm; autonomy memory attributes exist (MemoryProfile:8) but confirm logic never reads them.

## Official-doc checks done pre-Grok (2026-11-04)
- CNAuthorizationStatus.limited (iOS 18+) https://developer.apple.com/documentation/contacts/cnauthorizationstatus/limited ; ContactAccessButton https://developer.apple.com/documentation/contactsui/contactaccessbutton
- EKEventStore authorizationStatus / requestFullAccessToEvents (iOS 17+ full vs writeOnly) https://developer.apple.com/documentation/eventkit/ekeventstore/authorizationstatus(for:)
- SpeechAnalyzer/SpeechTranscriber iOS 26+ on-device https://developer.apple.com/documentation/speech/speechanalyzer (JS-rendered; availability via search snippets + WWDC25 session 277 references — treat iOS27 specifics as UNVERIFIED)
- App Intents openAppWhenRun background mode WWDC22 10032 https://developer.apple.com/videos/play/wwdc2022/10032/
- Apple docs pages JS-rendered in this environment; iOS 27.0.1 API deltas could NOT be substantiated from primary sources here.

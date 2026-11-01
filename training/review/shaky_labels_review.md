# Shaky-type teacher labels: 10-minute review

Source: `training/local_teacher/out/train_labels.jsonl` (read-only; snapshot of 711 rows at time of writing; the labeler is still running). Teacher: local Muse Glimmer 30B IQ2_M.
Picked 4 per type from contactPick, eventPick, notificationTriage, nudgeNow and rememberOrNot, preferring teacher confidence 0.5–0.8; if a type had fewer than 4 in that band, the lowest-confidence remaining rows fill the gap. Confidence = the teacher's softmax over option letters.
Mark each with `y`, or `n` plus the right option id.
Pool: contactPick: 65 rows, 16 in 0.5–0.8; eventPick: 65 rows, 21 in 0.5–0.8; notificationTriage: 54 rows, 1 in 0.5–0.8; nudgeNow: 61 rows, 38 in 0.5–0.8; rememberOrNot: 61 rows, 8 in 0.5–0.8


## contactPick

### 1. `s0-00656` (conf 0.51)
- **Context:** User: Message Maya: see you soon
- **Candidates:** c0 = Maya Novak (roommate); c1 = Maya Khan (dad); c2 = Maya Park (sister)
- **Options (teacher prob):** c0 (0.51), c1 (0.05), c2 (0.05), ask (0.39)
- **Teacher pick:** **c0** at 0.51 · synthetic generator's intended answer: `ask`
- Correct? (y / n + right answer): ______

### 2. `s0-00473` (conf 0.52)
- **Context:** Now: Mon 16:00 · User location: home · User: Message Zoe: see you soon
- **Candidates:** c0 = Zoe Lee (manager); c1 = Zoe Khan (coworker); c2 = Zoe Ortiz (landlord)
- **Options (teacher prob):** c0 (0.19), c1 (0.23), c2 (0.06), ask (0.52)
- **Teacher pick:** **ask** at 0.52 · synthetic generator's intended answer: `ask`
- Correct? (y / n + right answer): ______

### 3. `s0-00610` (conf 0.53)
- **Context:** Now: Mon 16:42 · User location: a cafe · User: Message Diego: see you soon
- **Candidates:** c0 = Diego Ortiz (mom); c1 = Diego Park (landlord); c2 = Diego Khan (coworker)
- **Options (teacher prob):** c0 (0.13), c1 (0.22), c2 (0.12), ask (0.53)
- **Teacher pick:** **ask** at 0.53 · synthetic generator's intended answer: `ask`
- Correct? (y / n + right answer): ______

### 4. `s0-00260` (conf 0.56)
- **Context:** Now: Thu 18:55 · User location: work · User: Message Zoe: see you soon
- **Candidates:** c0 = Zoe Khan (sister); c1 = Zoe Lee (brother); c2 = Zoe Ortiz (coworker)
- **Options (teacher prob):** c0 (0.09), c1 (0.01), c2 (0.56), ask (0.34)
- **Teacher pick:** **c2** at 0.56 · synthetic generator's intended answer: `ask`
- Correct? (y / n + right answer): ______

## eventPick

### 5. `s0-00669` (conf 0.55)
- **Context:** Now: Thu 20:55 · User location: home · User: Move my standup to next week
- **Candidates:** c0 = Standup (daily 9:30am); c1 = Yoga (Thu 6pm); c2 = 1:1 with Priya (Wed 10am)
- **Options (teacher prob):** e0 (0.55), e1 (0.02), e2 (0.01), ask (0.42)
- **Teacher pick:** **e0** at 0.55 · synthetic generator's intended answer: `e0`
- Correct? (y / n + right answer): ______

### 6. `s0-00168` (conf 0.60)
- **Context:** Now: Sat 21:00 · User location: unknown · User: Move my yoga to next week
- **Candidates:** c0 = Yoga (Thu 6pm); c1 = 1:1 with Priya (Wed 10am); c2 = Standup (daily 9:30am)
- **Options (teacher prob):** e0 (0.60), e1 (0.01), e2 (0.00), ask (0.39)
- **Teacher pick:** **e0** at 0.60 · synthetic generator's intended answer: `e0`
- Correct? (y / n + right answer): ______

### 7. `s0-00714` (conf 0.62)
- **Context:** Now: Mon 23:42 · User location: unknown · User: Move my yoga to next week
- **Candidates:** c0 = Yoga (Thu 6pm); c1 = Standup (daily 9:30am); c2 = Flight to SFO (Fri 7am)
- **Options (teacher prob):** e0 (0.62), e1 (0.01), e2 (0.00), ask (0.37)
- **Teacher pick:** **e0** at 0.62 · synthetic generator's intended answer: `e0`
- Correct? (y / n + right answer): ______

### 8. `s0-00587` (conf 0.65)
- **Context:** Now: Fri 15:00 · User location: commuting · User: Move my flight to sfo to next week
- **Candidates:** c0 = Flight to SFO (Fri 7am); c1 = Standup (daily 9:30am); c2 = 1:1 with Priya (Wed 10am)
- **Options (teacher prob):** e0 (0.65), e1 (0.01), e2 (0.01), ask (0.33)
- **Teacher pick:** **e0** at 0.65 · synthetic generator's intended answer: `e0`
- Correct? (y / n + right answer): ______

## notificationTriage

### 9. `s0-00544` (conf 0.50)
- **Context:** Now: Tue 22:30 · User location: the gym · Notification from Airline: 'Your flight UA 512 gate changed to B22'
- **Options (teacher prob):** interrupt (0.50), digest (0.49), ignore (0.01)
- **Teacher pick:** **interrupt** at 0.50 · synthetic generator's intended answer: `interrupt`
- Correct? (y / n + right answer): ______

### 10. `s0-00171` (conf 0.95)
- **Context:** Now: Tue 20:00 · User location: the gym · Notification from Mom: 'Call me when you can, it's about Grandpa'
- **Options (teacher prob):** interrupt (0.95), digest (0.05), ignore (0.00)
- **Teacher pick:** **interrupt** at 0.95 · synthetic generator's intended answer: `interrupt`
- Correct? (y / n + right answer): ______

### 11. `s0-00671` (conf 0.96)
- **Context:** Now: Thu 19:15 · User location: the gym · Notification from Bank: 'Unusual sign-in attempt on your account'
- **Options (teacher prob):** interrupt (0.96), digest (0.04), ignore (0.00)
- **Teacher pick:** **interrupt** at 0.96 · synthetic generator's intended answer: `interrupt`
- Correct? (y / n + right answer): ______

### 12. `s0-00477` (conf 0.97)
- **Context:** Now: Sun 12:15 · User location: home · Notification from Calendar: 'Team lunch moved to 1pm tomorrow'
- **Options (teacher prob):** interrupt (0.02), digest (0.97), ignore (0.00)
- **Teacher pick:** **digest** at 0.97 · synthetic generator's intended answer: `digest`
- Correct? (y / n + right answer): ______

## nudgeNow

### 13. `s0-00467` (conf 0.50)
- **Context:** Now: Fri 6:42 · User location: commuting · Trigger: arrive, place: Mom's house · Memory: User needs to buy coffee beans
- **Options (teacher prob):** nudge (0.26), later (0.24), skip (0.50)
- **Teacher pick:** **skip** at 0.50 · synthetic generator's intended answer: `skip`
- Correct? (y / n + right answer): ______

### 14. `s0-00557` (conf 0.52)
- **Context:** Now: Fri 10:00 · User location: the gym · Trigger: arrive, place: Mom's house · Memory: User needs to buy printer paper
- **Options (teacher prob):** nudge (0.23), later (0.25), skip (0.52)
- **Teacher pick:** **skip** at 0.52 · synthetic generator's intended answer: `skip`
- Correct? (y / n + right answer): ______

### 15. `s0-00254` (conf 0.52)
- **Context:** Now: Fri 9:42 · User location: home · Trigger: arrive, place: CVS pharmacy · Memory: User needs to buy eggs
- **Options (teacher prob):** nudge (0.52), later (0.07), skip (0.41)
- **Teacher pick:** **nudge** at 0.52 · synthetic generator's intended answer: `nudge`
- Correct? (y / n + right answer): ______

### 16. `s0-00019` (conf 0.53)
- **Context:** Now: Mon 6:05 · User location: work · Trigger: arrive, place: CVS pharmacy · Memory: User needs to buy printer paper
- **Options (teacher prob):** nudge (0.42), later (0.06), skip (0.53)
- **Teacher pick:** **skip** at 0.53 · synthetic generator's intended answer: `nudge`
- Correct? (y / n + right answer): ______

## rememberOrNot

### 17. `s0-00308` (conf 0.58)
- **Context:** Now: Thu 15:55 · User location: commuting · User: My partner's name is Jordan.
- **Options (teacher prob):** remember_fact (0.58), remember_temporary (0.03), no (0.40)
- **Teacher pick:** **remember_fact** at 0.58 · synthetic generator's intended answer: `remember_fact`
- Correct? (y / n + right answer): ______

### 18. `s0-00262` (conf 0.60)
- **Context:** Now: Fri 19:05 · User location: unknown · User: My partner's name is Jordan.
- **Options (teacher prob):** remember_fact (0.39), remember_temporary (0.01), no (0.60)
- **Teacher pick:** **no** at 0.60 · synthetic generator's intended answer: `remember_fact`
- Correct? (y / n + right answer): ______

### 19. `s0-00726` (conf 0.60)
- **Context:** Now: Sat 16:05 · User location: home · User: My partner's name is Jordan.
- **Options (teacher prob):** remember_fact (0.60), remember_temporary (0.02), no (0.38)
- **Teacher pick:** **remember_fact** at 0.60 · synthetic generator's intended answer: `remember_fact`
- Correct? (y / n + right answer): ______

### 20. `s0-00354` (conf 0.62)
- **Context:** Now: Wed 19:15 · User location: unknown · User: I'm at home until 5, then heading home
- **Options (teacher prob):** remember_fact (0.10), remember_temporary (0.28), no (0.62)
- **Teacher pick:** **no** at 0.62 · synthetic generator's intended answer: `remember_temporary`
- Correct? (y / n + right answer): ______

# ZeroLog build checklist

Living list. Ordered by what unblocks the next real decision, not by how
interesting it is. Tick things off in place.

**The rule that decides ordering:** until rep counting is proven on a wrist with
a loaded barbell, anything built on top of it is at risk of being rebuilt. So
Tier 1 is "make the phone app worth using daily", Tier 2 is "answer the wrist
question", and everything that depends on the answer waits.

---

## Tier 1 — so the phone app is worth opening every day

Needed because the plan depends on four weeks of real dogfooding. An app that
is not worth opening produces no data, and then nothing else matters.

- [x] Rest timer between sets, correct while backgrounded
- [x] What is coming next in the rotation
- [x] This week: workouts, sets, volume, change vs last week
- [x] Crash recovery (a killed app no longer loses the session)
- [x] Undo on every automatic change
- [ ] **Training experience at signup** (novice / returning / experienced)
      — the single biggest gap. Decides progression RATE: a novice adds weight
      every session, an intermediate cannot and will stall and quit if told to.
- [ ] **Which days you train** — makes "Tomorrow: Pull day" honest instead of
      invented, and lets the engine plan a real week
- [ ] **Goal: strength or size** — changes rep ranges and rest length
- [ ] **Bodyweight** — ONLY to suggest opening weights and to load bodyweight
      exercises. Not used after the first session; your last session is.
- [ ] Last time's numbers shown on each exercise row
- [ ] App icon (currently blank — see docs/screens)
- [ ] Edit or delete a logged set (no way to fix a mistake today)
- [ ] Empty states that say what will appear

**Not collecting height.** It affects form cues, not programming. It would add
a signup field and change no number.

---

## Tier 2 — answering the wrist question (needs Nov 10)

- [x] Watch capture loop, set detection, auto-log rules
- [x] Settings sync phone → watch
- [x] Motion consent + visible recording indicator
- [x] On-watch diagnostics and engine self-test (6/6 on Apple's runtime)
- [x] Every workout saves its raw windows for offline re-tuning
- [ ] **Apple Developer account** ($99/yr, needs 18) — hard gate
- [ ] **An actual Apple Watch** — UNCONFIRMED whether one is owned
- [ ] Code signing + TestFlight
- [ ] First real gym session with raw capture
- [ ] **Battery cost measured** — completely unknown, biggest open risk
- [ ] Barbell accuracy measured (bench, squat, deadlift — absent from MM-Fit)
- [ ] Re-tune per-exercise profiles on real barbell data

---

## Tier 3 — before a closed beta (target Mar 2027)

- [ ] Rest timer on the watch, auto-started from a detected set
- [ ] Exercise animations (free legal source identified, nothing wired)
- [ ] HealthKit recovery actually populated (engine accepts it; nothing feeds it)
- [ ] Gym arrival detection
- [ ] Onboarding that explains the one-tap idea
- [ ] Trademark search, domain, company formation
- [ ] Lawyer on health data (UK GDPR special category, US state health laws)

---

## Later — deliberately deferred, with reasons

- [ ] **Food logging.** Needs a paid vision API (no card until 18), a server,
      and a privacy review for health-adjacent images. Turns a local app into a
      company. The brief itself calls it a commodity; MyFitnessPal works today.
      Nothing else counts barbell reps.
- [ ] AI coach — depends on food plus training plus recovery all existing
- [ ] Paywall and subscriptions
- [ ] Recipes that fit macro targets

---

## UI: what is actually wrong, in priority order

Judged from the committed screenshots, not from imagination.

### 1. No hierarchy — everything has the same visual weight
Today's screen is a uniform list where the session title, the plan, the warnings
and the exercise rows all read at the same level. The most important thing on
the screen should dominate it.

- Today: one hero block — day name, duration, exercise count, Start — then the
  detail below, rather than a row among rows.
- Mid-workout: the current set should own the screen; everything else recedes.

### 2. The colour system is defined but unused
Red for workouts, green for done, yellow for wins, blue for food — all defined
in Theme, almost none of it visible. Completed exercises should go green as you
go; a weight increase should read as a win, not as body text.

### 3. Not enough data per row
Lifters want numbers. Each exercise row should carry last time's result
("Last: 60 kg x 8") so the next weight has visible context.

### 4. Empty states are blank rather than explanatory
A new install shows almost nothing and says nothing about what will appear.

### 5. History is a flat list
A session row could show its volume and a small trend, making the screen worth
visiting rather than a receipt.

### 6. No icon
The app installs with a blank white icon.

**Deliberately NOT on this list:** a redesign. The structure is sound and the
typography choices are good; it is under-used, not wrong. Rebuilding the look
before the wrist question is answered would be the same mistake as building
food logging on an untested capture layer.

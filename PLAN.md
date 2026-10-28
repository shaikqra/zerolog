# PLAN.md — ZeroLog

> **Decision 2026-10-28: build-first.** Shaik chose to build before marketing. Changes to this plan:
> - Waitlist page still launches **Nov 10** (no video) so signups collect while building. Concierge test, video and creators are **parked**; §1 stays as the playbook for when marketing restarts.
> - The 500/30 gate is no longer a build blocker. Waitlist signups are tracked as a signal only.
> - **No Mac.** Build the Mac-free core first: (1) rep detection prototype (§5 Stage A), (2) workout engine in `core/` (Python reference, ported to Swift later). Buy or rent a Mac only when those work and the app screens are next. Watch app without a Mac was ruled out: cloud builds can't do live watch testing.
> - Known risk accepted: without validation, we may build for months before learning whether lifters pay.

Written 2026-10-28. Context lives in `CLAUDE.md`. Anything marked **⚠ verify** comes from memory, not a live source. Check it before relying on it.

---

## 0. Constraints this plan is built around

| Constraint | Answer | What it changes |
|---|---|---|
| Mac | **None** | Phase 0 needs no Mac, so that's fine. Building the app does. Buying a used Mac becomes the first spend **after** the Phase 0 gate passes, not before. |
| Hours | **5–10 / week** (plan assumes ~7) | Concierge test cut from 20 testers to **8–10** (see §1.5). Build milestones sized at ~7h/week. |
| Phase 0 budget | **$0–100** | Free tiers everywhere. About $10 for a domain. Tester rewards are free App Store time, not cash. |
| Accounts | Shaik turns **18 on 2026-11-10** | No company needed. Most services (Cloudflare, Kit, domain registrars, Lemon Squeezy) require 18+ in their terms, so **everything launches on Nov 10** in Shaik's own name. Until then, build it all offline. |
| Name | **ZeroLog kept** (2026-10-28) | Known search clash with the "zerolog" programming library. `zerolog.com` / `.app` taken; **`getzerolog.com`** appears free. USPTO + UKIPO search still to do. |
| Design skills | Not asked. **Assumed none.** | Figma free plan + templates, CapCut for video. No custom brand work in Phase 0. |
| Coding | Shaik can't write code yet | Claude writes the Swift. Shaik builds, runs and tests on the Mac. Milestones are small so a broken step is cheap to find. A contractor stays as the fallback (§7). |

**Calendar fact, not a lecture:** at 7h/week the lifting-loop MVP lands around June 2027 (§7). Pre-order buyers must be told an honest delivery window. That date is part of what Phase 0 tests.

---

## 1. Phase 0 — Validation (no app code)

### 1.1 Goal and gate
- **Pass:** 500+ waitlist signups AND 30+ paid pre-orders by **2026-12-22**. That's six weeks from the Nov 10 launch, when waitlist and pre-orders open together.
- **Miss either one:** stop and rethink. Don't build anyway.
- **Also track (these inform the rethink, they aren't gates):** waitlist→pre-order conversion, which video hook converted, concierge D7/D14 engagement, and how many concierge testers say they'd pay at the end.

### 1.2 Landing page stack (recommendation: ~$10 total)

| Piece | Recommended | Cost | Why / alternatives |
|---|---|---|---|
| Hosting | **Cloudflare Pages** | $0 | Commercial use allowed on the free plan. **Not Vercel Hobby**: its free plan is non-commercial and a pre-order page is commercial (⚠ verify current ToS). Netlify free is the other option. |
| Page | Single static HTML page, written by Claude, edited by Shaik | $0 | Carrd ($19/yr for a custom domain) or Framer (paid for a custom domain) if you'd rather drag-and-drop. |
| Domain | Cloudflare Registrar | ~$10–12/yr | Check trademark conflicts for the name first (§8). |
| Waitlist + email | **Kit (ConvertKit) free plan** form embed | $0 | Free up to 10k subscribers with broadcast email (⚠ verify limits), so you can email the waitlist on Nov 10. Tally free is the alternative, but it can't send email. |
| Paid pre-order | **Lemon Squeezy** or **Gumroad** (merchant of record) | No monthly fee, % per sale (⚠ verify: LS ~5%+50¢, Gumroad ~10%+50¢) | A merchant of record handles US sales tax and UK VAT for you. Stripe India is invite-only for new accounts (⚠ verify). Opens **Nov 10** in Shaik's name. Check payouts to an Indian bank work before launch. |
| Analytics | Cloudflare Web Analytics | $0 | Cookieless, so no cookie banner needed for basic stats. |

**Page structure:** hook line → 30-sec video → three-step "how it works" (walk in / lift / tap) → honest line ("Concept demo. App in development. Built for Apple Watch lifters.") → email form → after signup, a pre-order offer on the thank-you page → FAQ (privacy, refunds, delivery window).

### 1.3 Pre-order offer
- **"Founding Member: first year for $49.99"**, the bottom of the planned price range, so it's a real willingness-to-pay test.
- Charged now. **Full refund on request any time before launch.** Stated in plain words, which also covers UK consumer-law cancellation rights (lawyer item, §8).
- Delivered as an **App Store subscription offer code** worth 12 months free at launch (⚠ verify current offer-code limits). Buyers also get TestFlight beta access first.
- Stated delivery window: "Beta: summer 2027." If that kills conversions, that's real data.

### 1.4 The 30-second demo video (concept video, labelled as one)
No app exists, so the video is a **mock-up**. It must say "concept demo" on screen. Taking money with a video that pretends to show a working app would be misleading, and the FTC/ASA see it that way too.

How to make it with $0 and no Mac:
1. **Figma (free):** design 6 screens. Phone lock-screen notification ("Push day · 45 min · ready"), exercise card, watch "Bench · 8 reps · 80 kg? ✓", food photo result "520–640 kcal · medium confidence", end card.
2. **Film at the gym on your phone:** walking in, a set of bench, a glance at the watch, a tap, photographing a meal.
3. **CapCut (free):** lay the Figma screens over the footage (watch screen composited onto the wrist). Captions on, because most viewers watch muted.
4. **Exercise animation in the video:** use only free licensed content (a Mixamo clip, ⚠ verify Mixamo licence) or none. No unlicensed GIFs.

Script beats: 0–2s hook ("Logging sets is the worst part of lifting.") → 2–8s walk in, phone buzzes with today's workout → 8–18s lift, watch counts, one tap → 18–25s food photo, calorie range → 25–30s "ZeroLog. You lift. It logs." + waitlist CTA.
Make **three hook variants**. Post all three and see which converts.

### 1.5 Concierge test: recruiting and running it

**Deviation from your brief (on purpose):** 20 testers coached live won't fit in 5–10h/week. At ~10 min per tester per day, 20 testers is ~23h/week, plus a time-zone problem (6pm US Eastern = 4:30am in Hyderabad). Recommended instead: **8–10 testers, mostly UK** (6pm UK = 11:30pm IST), **coached async** (workout sent the night before, reviewed the next morning), for **2 weeks**. If you can find more hours, grow it. Don't drop the quality of the test to hit 20.

Recruiting steps:
1. **Screener form (Tally, free):** country, Apple Watch model, lifts per week (need 3+), current apps (Hevy/Strong + MFP), messaging app, time zone. Include a consent line covering what you'll collect.
2. **Where to find testers** (read every community's self-promo rules first):
   - Threads where Bevel and Hevy users ask for auto rep detection. Reply with a helpful comment, not a spam DM.
   - Reddit communities for Apple Watch fitness and natural lifting (find the active ones; follow their rules).
   - Your own short videos (comment "tester" to apply).
   - Friends or family abroad with gym friends in the UK or US.
3. **Reward:** a free founding year (offer code) for finishing 2 weeks. $0 cash.
4. **Each day:**
   - Night before: they say when they'll train and for how long. You send the workout from a **spreadsheet version of the rules engine** (exercise DB + progression rules), which tests the "no free-writing" design for real.
   - After training: they send their Apple Watch workout screenshot. You confirm weights in one message ("80 kg × 8, 8, 7?" → they reply "yes").
   - Food: they send photos. You reply with a calorie **range**, using Claude.ai or your own judgment.
5. **Measure:** reply rate per day, days active out of 14, exit interview (3 questions: what they'd miss, what was annoying, "Would you pay $49.99/yr? If not, what price?").

### 1.6 Phase 0 week by week

| When | Work (~7h/week) | Done means |
|---|---|---|
| **Oct 28 – Nov 2** | ~~Name~~ (ZeroLog kept), ~~page copy~~ (`phase0/landing-copy.md` v1), trademark search, Figma screens | 6 screens designed; USPTO + UKIPO checked |
| **Nov 3 – Nov 9** | Build the page locally, film + edit video v1, screener form drafted, start Sensor Logger data (§5), install Train Fitness + Bevel for the teardown | Everything ready to go live; nothing public yet |
| **Nov 10 (turn 18)** | Buy domain, deploy to Cloudflare Pages, Kit form + Lemon Squeezy pre-order live, post first video | Test signup + test purchase + refund done end-to-end |
| **Nov 10 – Nov 23** | 3 hook videos, recruit testers, finish teardown | 8–10 testers screened; teardown notes written |
| **Nov 24 – Dec 7** | Concierge test runs; 2 more videos; reach out to 5–10 micro-creators (free collab first, maybe one paid post, ~$40, dad approves) | 14 days of tester data |
| **Dec 8 – Dec 22** | Keep posting, exit interviews, numbers, decision | **Gate decision written in this file (Dec 22)** |

---

## 2. MVP feature specs

**Scope warning:** the full vision (gym detection + workouts + animations + watch auto-detect + food + recipes + coach) is far too much for a first release at 7h/week. Recommended staging:
- **v1 = the lifting loop** (F1–F5, F10–F12). This is the moat.
- **v1.1 = food** (F6–F7).
- **v1.2 = coach + recipes** (F8–F9).

Food-photo logging is a commodity, as you said yourself. Shipping it first would put you in Cal AI's market without your edge.

| # | Feature | Tier | Acceptance criteria |
|---|---|---|---|
| F1 | **Gym arrival detection** | v1 | Arriving at a saved gym triggers a "workout ready" notification within 5 min in ≥80% of visits over 2 weeks (Shaik's real visits). Fewer than 1 false trigger per week. A manual "I'm at the gym" button on watch and phone always works. |
| F2 | **Workout generation** | v1 | Output contains **only** exercises from the exercise DB that the gym's equipment supports. Fits the time given (±5 min). Applies progression rules (e.g. hit top of rep range → +2.5 kg next time) traceably: each exercise shows "why this weight". Adjusts down when HealthKit recovery is low (rule-based thresholds). Same inputs → same workout (deterministic). |
| F3 | **Exercise animations** | v1 | Every exercise in the v1 catalog has a licensed animation, with the licence recorded per asset. Plays offline. Missing animation → text cues, never a broken view. |
| F4 | **Watch auto-detect + rep count** | v1 | For the launch set of lifts: rep count within ±1 on ≥90% of sets. Exercise top guess correct ≥85%, right exercise in top 3 ≥95%. Measured on held-out sets from people who didn't contribute training data. Watch battery drain ≤15% for a 60-min session (⚠ target to verify on device). |
| F5 | **One-tap confirm** | v1 | After each set the watch shows "Exercise · reps · weight?". One tap confirms. Correcting is ≤2 interactions (digital crown for weight/reps, swap exercise from top 3). Weight pre-filled from last session + progression rule. Every confirm/correct is stored as a label (§5). |
| F6 | **Food photo logging** | v1.1 | One photo → result in ≤8s. Always shows a **kcal range + confidence level** (low/med/high) and macros as ranges. On 50 weighed test meals, the true value falls inside the range ≥80% of the time and the median range width is ≤±25%. Easy correction ("that was 2 rotis, not 3"). |
| F7 | **Personal food memory** | v1.1 | A meal logged 2+ times is offered as a one-tap "your usual dal-rice?" suggestion. Repeat meals use the remembered values without an LLM call. User can edit or delete memories. |
| F8 | **Recipes / meal suggestions** | v1.2 | Suggestions come from a structured recipe set, not free-written. Each shows a macro range against the day's remaining target. No "good/bad food" language. |
| F9 | **AI coach** | v1.2 | Answers only from the user's own data plus the exercise/recipe DBs. Cites the data it used. Never gives medical claims or diagnoses. Refuses injury/medical questions with a "see a professional" message. Has a cost cap per user per month. |
| F10 | **Onboarding quiz + paywall** | v1 | Quiz ≤90 seconds (goal, experience, days/week, gym, equipment). Trial starts with StoreKit 2. Paywall states price, trial length and cancellation clearly (Apple guideline compliant). Offer codes redeem correctly for pre-order buyers. |
| F11 | **HealthKit integration** | v1 | Reads only the types needed (HRV, resting HR, sleep, workouts). Writes strength workouts to HealthKit. Works if the user denies some permissions. Raw HealthKit data stays on device by default. |
| F12 | **Privacy + consent** | v1 | Separate explicit consents for: health data processing, motion-data upload for model training (off by default), and sending food photos to a third-party AI provider. Delete-my-data works end to end. No health data in analytics or logs. |

**Explicitly out of v1:** Android, social features, streaks/badges (responsible-design rule), barcode scanning, wearables other than Apple Watch, web app.

**Ideas taken from reviewing FitG (a similar app, 2026-10-29).** Ideas only, rebuilt in our own words and code. None of its files, data or text are used.
- **Now (built):** "What I changed" cards on Today. Each automatic weight change shows its reason and an Undo. Also no-template copy rules (see CLAUDE.md).
- **v1.1 food, parked:**
  - Protein target around 1.6 g per kg of body weight. Research suggests muscle gain levels off near there. ⚠ verify the source before using it in the app.
  - A planned meal the user doesn't tap still counts as eaten for that day's maths. The app asks once, gently, and never nags.
  - Logging a meal means confirming the planned one with one tap, and only correcting it when it was different.
- **v1.2 coach, parked:**
  - A hard cap on notifications per day, e.g. 4. Every notification has a button that does something.
  - The coach speaks in the first person through its changes, with no mascot.
- **Not taken:**
  - FitG's Indian home-food focus: ZeroLog is US/UK.
  - Its visual identity: it's FitG's brand.
  - Its missed-workout reshuffle: ZeroLog has no fixed calendar, so the rotation simply continues from the last session.

---

## 3. Architecture and tech stack

### 3.1 App: **SwiftUI, native iOS + watchOS** (recommended, effectively forced)
- watchOS sensor access, workout sessions and complications need native Swift. React Native and Flutter can't run a real watchOS app. One Xcode project, two targets (phone + watch), shared Swift package for models and rules.
- Local storage: **SwiftData** on device (works offline in the gym), synced to the backend.
- Minimum OS: iOS 17 / watchOS 10 for `CLMonitor` and high-rate batched sensors (⚠ verify the floor when we start; going higher shrinks the market slightly).

### 3.2 watchOS + rep detection
- **`HKWorkoutSession`** keeps the watch app alive during the workout and unlocks sensor access in the background.
- **Sensors:** `CMMotionManager` (~50–100 Hz device motion) is enough to count reps. `CMBatchedSensorManager` (watchOS 10+, high-rate accelerometer during workouts, ⚠ verify rates) is the upgrade if accuracy needs it.
- **Two separate problems:**
  1. **Rep counting** (signal processing): filter → find the main movement axis → peak detection with per-exercise thresholds. Cheap, explainable, runs on-device. Build this first.
  2. **Exercise classification** (ML): a **Core ML activity classifier** on 2–3 s motion windows. Train in Create ML (Mac) or PyTorch → `coremltools`.
- **Launch set: start with 8–10 lifts, not 20–30.** Upper-body dumbbell and barbell moves (bench, OHP, curls, rows, lat pulldown, lateral raise, tricep pushdown, RDL) move the wrist clearly. Leg press, leg extension and squats with a fixed grip move the wrist very little, so expect poor accuracy there. Expand to 20–30 once real data shows which lifts work. The one-tap correction (F5) is what makes imperfect detection acceptable.
- **Known competitor:** Train Fitness already sells auto-detection on Apple Watch. The teardown (§1.6) has to answer: how good is theirs, and why would a lifter switch? If theirs is good, the moat is **the full loop**, not detection alone.

### 3.3 Gym detection: CoreLocation
- `CLMonitor` (iOS 17+) / region monitoring. **Limit: 20 regions per app** (fine, since people have 1–3 gyms). Accuracy is roughly 100 m, so a gym inside a mall or next to a café will false-trigger.
- Fix: geofence entry **plus** a second signal (watch motion pattern, or dwell over 5 min) before notifying. Manual button as a fallback.
- Needs "Always" location permission, which many users refuse. The app must work fully without it.
- **Free test now (no Mac):** set up an iPhone Shortcuts automation for "When I arrive at [gym]" → notification. Log hits and misses for 2 weeks.

### 3.4 Food vision LLM
- Called from a **backend function** (never from the app directly, so the API key is never on the phone), with a structured JSON output: items, portion estimate, kcal low/high, macros low/high, confidence.
- **Bake-off before choosing:** 50 weighed home meals (yours) → run through Claude Haiku 5.5 and Claude Sonnet 5.5 (and one non-Anthropic vision model for comparison). Pick the cheapest that hits the F6 accuracy bar. Opus is overkill here.
- Cost controls: resize photos to ~1,000 px, cache the system prompt, check food memory first, cap at ~15 analyses per user per day.

### 3.5 Backend and database

| Option | Pros | Cons |
|---|---|---|
| **Supabase** (recommended) | Postgres + auth + storage + edge functions in one. You already know it from Qra. Row Level Security. **London region** keeps UK data in the UK. Free tier for the beta. | Pro plan $25/mo once beyond the free tier. You own the security setup. |
| Firebase | Mature iOS SDK, generous free tier | NoSQL makes workout/set queries awkward. A second ecosystem to learn. |
| CloudKit | Free, Apple-native, private by default | No server-side logic for AI calls (still need a proxy). Hard to analyse data or train models. Locks you to Apple. |

**Data placement principle:** raw HealthKit data and raw motion stay **on device** unless the user opts in. The server stores workouts, sets, meals and consent records. Food photos are deleted after analysis unless the user saves them.

### 3.6 Other pieces
- **Subscriptions:** StoreKit 2 + **RevenueCat** (free until ~$2.5k monthly revenue, then ~1%; ⚠ verify).
- **Analytics:** TelemetryDeck or PostHog free tier. Never send health values.
- **Crash reporting:** Xcode Organizer (free) to start.

### 3.7 Exercise animation licensing (email for quotes during Phase 0; it's free to ask)

| Option | Fit | Notes |
|---|---|---|
| **ExerciseDB / AscendAPI** licensed animation library | Big catalog (1,000+), fastest path | Check the licence allows in-app use in a paid subscription app, offline caching, and whether the style is "3D" enough. ⚠ verify price and terms. |
| **Gym Visual** (3D exercise animation packs) | Clean 3D look | Per-pack or per-exercise licence. ⚠ verify. |
| **Mixamo** (Adobe, free) | $0, royalty-free | Few gym-specific moves; would need Blender work. Good for the demo video, weak for the catalog. |
| **Commission a 3D animator** (per exercise) | You own the IP, consistent style | Roughly $30–150 per exercise × 10 = affordable for the v1 launch set only. ⚠ market rates vary. |

**Recommendation:** licensed library for breadth in v1, unless its licence bans subscription apps. Only 8–10 exercises are needed at launch, so commissioning is a real option.

---

## 4. Data model (first draft)

Plain-English note: each table is like one sheet in a spreadsheet. A row is one thing (one user, one set). `→` means "points to a row in another table".

| Table | Key fields | Notes |
|---|---|---|
| **users** | id, created_at, country, units (kg/lb), goal, experience_level, days_per_week, macro_targets, trial/subscription status (from RevenueCat) | No name needed. Email via auth only. |
| **consents** | user → , type (health / motion_upload / ai_photo / marketing), granted, timestamp, policy_version | Append-only. Needed for GDPR. |
| **gyms** | id, user → , name, lat/lng, radius_m | Per-user gym. Location is sensitive data. |
| **equipment** | id, name, category (barbell, dumbbell, cable, machine…) | Global list. |
| **gym_equipment** | gym → , equipment → , details (e.g. max dumbbell 40 kg) | Which gym has what. |
| **exercises** | id, name, primary/secondary muscles, movement pattern, required equipment, detectable (bool), animation_asset_id, licence_ref | The structured DB the AI selects from. |
| **progression_rules** | id, exercise or pattern, rep range, increment, deload rule | Explicit rules, versioned. |
| **workouts** | id, user → , gym → , started/ended_at, planned_duration, recovery_snapshot (summary only), generator_version | One session. |
| **workout_exercises** | id, workout → , exercise → , order, planned sets/reps/weight, reason_text | "Why this weight". |
| **sets** | id, workout_exercise → , set_no, **detected_exercise, detected_reps, detection_confidence**, confirmed_reps, confirmed_weight, **confirm_action** (confirmed / corrected_reps / corrected_exercise / manual), model_version, motion_ref (nullable) | Every set is also a training label. |
| **motion_recordings** | id, user → , set → , storage_path, sample_rate, watch_wrist, watch_model, consent → | Only if the user opted in. Raw file in private storage. |
| **meals** | id, user → , eaten_at, source (photo / memory / manual), photo_ref (nullable, short-lived), model + prompt_version | |
| **meal_items** | id, meal → , name, portion_desc, kcal_low, kcal_high, protein/carb/fat low+high, confidence | Ranges are stored as ranges. |
| **food_memory** | id, user → , label ("usual dal-rice"), item template, typical kcal range, times_logged, last_used | Lets repeat meals skip the LLM. |
| **coach_messages** (v1.2) | id, user → , role, content, data_refs, tokens, cost | Cost tracking per user. |

---

## 5. Collecting labelled motion data for rep detection

**Stage A: now, $0, no Mac**
- Install **Sensor Logger** (free iOS + watchOS app, ⚠ verify it still records watch accelerometer/gyro and exports CSV).
- Shaik + 3–4 gym friends record sets: 8–10 lifts × 3 sets each × 2–3 sessions. Log each one in a sheet: person, wrist, exercise, reps, weight, file name.
- Claude writes a **throwaway Python notebook** (runs on Windows in your existing Python env; it's a prototype, not production code): plot signals, count peaks, measure rep accuracy per lift.
- **Output:** a table of "rep-count accuracy by lift" before a single line of Swift. This is the cheapest test of the riskiest assumption.

**Stage B: in the beta app**
- Every one-tap action is a label. **Confirmed** = detection right. **Corrected reps/exercise** = detection wrong, with the right answer attached.
- Raw motion windows upload only with **separate opt-in consent** (default off). Upload low-confidence and corrected sets first; they teach the model the most.
- Store `model_version` on every set, so accuracy per model release can be measured.

**Stage C: retraining**
- Monthly: retrain, test on held-out users (people not in training), ship only if accuracy improves. Results logged in the repo.
- Watch out for: left vs right wrist, watch worn loose, different watch models, lifting tempo. Data must cover all of them.

---

## 6. Unit economics (per active user per month)

**Model prices (Anthropic API, checked today):** Haiku 5.5 $0.10 in / $0.50 out per million tokens. Sonnet 5.5 $2 / $10, cached input $0.20. A ~1,000 px photo is about 1,600 input tokens.

**Per-call estimates** (Sonnet numbers include a buffer for thinking tokens):

| Call | Tokens (in / out) | Haiku 5.5 | Sonnet 5.5 |
|---|---|---|---|
| Food photo | ~1.7k new + 1.5k cached / ~400 out + thinking | ~$0.001 | ~$0.01 |
| Coach message | ~1k new + 5k cached / ~600 | ~$0.0005 | ~$0.009 |
| Weekly review | ~10k / ~800 | ~$0.0015 | ~$0.03 |
| Workout generation | **rules engine, no LLM** | $0 | $0 |

**Monthly per user:**

| Scenario | Usage | All-Sonnet | Haiku food + Sonnet coach |
|---|---|---|---|
| Typical | 60 photos, 20 coach msgs, 4 reviews | ~$0.90 | ~$0.40 |
| Heavy | 120 photos, 60 coach msgs, 4 reviews | ~$1.80 | ~$0.80 |
| Abuser (no caps) | 500+ photos | $5+ | $0.60+ |

**Revenue per paying user (annual plan):**
- US $59.99/yr → after Apple 15% (Small Business Program) ≈ **$4.25/mo**. US App Store prices exclude sales tax.
- UK £49.99/yr includes 20% VAT → ex-VAT £41.66 → after 15% ≈ **£2.95/mo (~$3.75)**.
- Monthly plan at $9.99 → ~$8.49 net.

**Verdict:** AI costs about **10–25% of net revenue** for typical users. That works **as long as** you cap photo analyses per day, check food memory before any LLM call, and keep the coach on cached context. The real risk is **trial users**: they cost money and many never pay. A 14-day heavy trial costs about $0.50–1. At a 30–40% trial-to-paid rate, each paying user carries about $1.50–3 of trial cost once. Consider a **7-day** trial for that reason.

**Fixed costs once live (⚠ verify each):** Apple Developer $99/yr, Supabase Pro $25/mo (after the free tier), animation licence (unknown, possibly the largest fixed cost, so get quotes in Phase 0), domain ~$12/yr. Break-even on fixed costs is roughly 15–25 annual subscribers.

---

## 7. Milestones (part-time, ~7h/week)

**Phase 0 (no Mac, ≤$100):** see §1.6. Gate on **Dec 22, 2026**.

**Gate passed → spend decision for dad:** used M1 MacBook Air or Mac mini (~$400–550, ⚠ check local prices) + Apple Developer $99. About **$550–650 total**. Spent only after the gate passes, so a failed Phase 0 costs $0 in hardware.

| # | Milestone | ~Hours | "Done" means |
|---|---|---|---|
| M3 | Watch skeleton: workout session + raw sensor recording + sync to phone | 25 | Shaik records a real gym session on his own watch; data lands on the phone and exports |
| M4 | On-device rep counting, first 5 lifts | 30 | ±1 rep on ≥90% of Shaik's sets for 2 weeks of real training |
| M5 | Exercise DB + rules-based workout generator + gym equipment + phone UI | 35 | Generates a valid, deterministic workout for 3 different gyms; every weight shows "why" |
| M6 | One-tap confirm on watch + exercise classification (8–10 lifts) + geofence auto-start | 35 | F1, F4 and F5 acceptance criteria met on Shaik + 3 friends |
| M7 | Onboarding quiz, paywall (RevenueCat), HealthKit recovery read, TestFlight | 30 | Pre-order buyers on TestFlight redeem offer codes; 10 testers complete a week |
| M8 | Food photo + ranges + food memory (v1.1) | 30 | F6 and F7 met on the 50-meal test set |
| M9 | Coach + recipes (v1.2) | 25 | F8 and F9 met; cost per user tracked and under cap |
| M10 | App Store submission + launch | 15 | Approved, live in US + UK, privacy labels accurate |

M3–M7 ≈ 155h ≈ **22 weeks** → TestFlight around **June 2027** if the build starts in January. Your IB exams are in May 2027, so pencil in a pause for roughly April–May; that pushes TestFlight to July. Tell pre-order buyers "summer 2027".
**Fallback if Claude-written Swift stalls on watch debugging:** a short paid contractor engagement for M3–M4 only (cost to be quoted, dad approves).

---

## 8. Top risks and the cheapest test for each

| Risk | Type | Cheap test | Cost |
|---|---|---|---|
| Wrist motion can't count reps reliably enough | Technical | Sensor Logger + Python notebook (§5 Stage A) | $0 |
| Exercise classification fails on leg/machine lifts | Technical | Same data; see which lifts separate cleanly. Shrink the launch set if needed | $0 |
| Train Fitness (or Apple itself) already does this well | Market | Use Train Fitness for a week; read its 1–2★ reviews; watch Apple's watchOS release notes | $0 |
| Lifters won't pay | Market | The Phase 0 gate (pre-orders at real price) | ≤$100 |
| Geofence misfires | Technical | iPhone Shortcuts "arrive at gym" automation for 2 weeks | $0 |
| Food ranges too wide or too wrong | Technical | 50 weighed meals through Claude.ai / API trial credits | ~$0–2 |
| Animation licence too expensive or bans subscription use | Cost/legal | Email 2–3 vendors for quotes now | $0 |
| Battery drain during workouts | Technical | Sensor Logger recording a 60-min session; note battery % | $0 |
| Solo non-coder can't ship watchOS code | Execution | M3 is deliberately tiny; if it takes more than 2× the estimate, bring in the contractor fallback | — |
| Too many projects (Qra, clinic, VISHWAKARMA, design bureau) | Execution | Decide the priority on purpose; track weekly hours honestly | $0 |
| Name already trademarked | Legal | Free USPTO + UKIPO searches before buying the domain | $0 |

**For a lawyer (not legal advice; flagging only):**
- UK GDPR: health and fitness data is likely **special category data**, so an explicit-consent basis plus a DPIA is likely needed. Data transfer from the UK to an Indian controller.
- US state consumer-health-data laws (e.g. Washington **My Health My Data Act**, Nevada, Connecticut): consent rules and private right of action.
- Apple App Review rules on HealthKit (no ads use of health data, no health data in iCloud) and on disclosing personal data sent to third-party AI (⚠ verify current guideline numbers).
- Pre-order terms: refund promise, UK 14-day cancellation rules, what happens if the app ships late or never.
- FTC / UK ASA: concept-video labelling, creator posts must disclose #ad.
- India side: tax on foreign income (GST on exports of services, LUT): ask a CA.

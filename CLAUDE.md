# CLAUDE.md — ZeroLog (codename, name TBD)

Read this first every session. Plan lives in `PLAN.md`.

## Status
**Build-first (decided 2026-10-28).** Shaik chose to build the core app now and market later. The waitlist page (already built, `phase0/site/`) still goes live Nov 10 with no video, to collect signups while building. Concierge test, video and creator outreach are parked.
**No Mac.** Build order: Mac-free core first (rep-detection prototype in Python on Sensor Logger data; workout engine in `core/`, a Python reference implementation to port to Swift later). Mac (buy or rent) only when the core works and app screens are next. Do not create accounts, add API keys, install paid services or spend money without Shaik's explicit OK. Dad (Ali) approves all billing.

## Repo layout
- `core/` Python reference engine + tests (runs on Windows: `python -m unittest -v`)
- `app/` iPhone + Watch app (Swift/SwiftUI). No local Mac: GitHub Actions (`.github/workflows/app.yml`, macOS runner) runs Swift tests and builds both apps on every push touching `app/` or `core/data/`. ~200 free Mac-minutes/month, so batch changes, don't push tiny fixes one by one.
- `phase0/` landing page + copy
- Engine rules and the exercise JSON exist in both Python and Swift; CI fails if the JSON copies differ. Change both.

## Product in one line
iPhone + Apple Watch app that removes manual fitness tracking: "Hevy + MyFitnessPal + a coach, and you never type a thing."

## Core loop (the moat)
1. Arrive at gym → geofence + motion detect it → today's workout generated from history, HealthKit recovery, time available, that gym's equipment.
2. Each exercise shown with a **licensed** 3D animation (never AI-generated video).
3. Watch auto-detects the exercise and counts reps. User only **confirms** weight with one tap ("confirm, don't enter").
4. Food: one photo or one tap. Calorie **ranges with confidence**, never fake-exact numbers. Remembers repeat home meals ("personal food memory").
5. Recipes / meal suggestions that fit macro targets.
6. AI coach ties workouts + food + recovery together.

Food photo logging alone is a commodity. **Automatic lift detection + the full zero-input loop is the moat.**

## Decisions already made (don't re-litigate)
- **Market:** US + UK first. Not India. Built from Hyderabad, priced in USD/GBP via App Store.
- **First niche:** Apple Watch lifters, 18–35, already using Hevy/Strong + MyFitnessPal, hate manual logging. Bevel users publicly asking for auto rep detection = validated demand.
- **Tone:** clean, confident, honest about laziness. Not gym-bro.
- **Platform:** iOS + watchOS first. Android later.
- **Monetisation:** onboarding quiz → 7–14 day free trial → hard paywall. Annual ~$49.99–$79.99/yr + monthly option.
- **Marketing:** short-form demo videos via small fitness creators first. Paid ads only after organic traction.
- **Competitors to study:** Bevel, Google Health Coach (ex-Fitbit), Cal AI, MyFitnessPal, Train Fitness, Riven, Fitbod, Hevy.
- **Founder:** solo, part-time student. Plan in small shippable milestones. Shaik is test user #1 (Apple Watch, Hevy, MyFitnessPal, Bevel).

## Design rules (non-negotiable)
- **AI never free-writes workouts.** It selects from a structured exercise database and applies explicit progression rules.
- **Calories/macros always shown as ranges with confidence.**
- **Code does the numbers; AI only chooses and words things.** Every weight, rep count or calorie the user sees comes from code, never from a model.
- **Every automatic change shows its reason and can be undone** ("What I changed" on Today: weight up or down now; more kinds later).
- **Look (from FitG, decided 2026-10-29):** dark only. True black, competition-plate data colours (red = workouts, green = done, yellow = wins, blue = protein), each paired with a word. Big Shoulders Display for numbers and titles, Atkinson Hyperlegible for text, white primary buttons. Every colour and font lives in `app/ZeroLog/Style.swift`.
- **No template look in the app:** sentence case (no ALL-CAPS labels), no "·" between facts ("3 × 6 at 135 lb"), no "→" in buttons, no emoji, no gradient or glass decoration.
- **Responsible design:** no shaming, no streak-guilt or obsessive tracking mechanics, no medical claims.
- **Health data is sensitive.** Flag for a lawyer (don't give legal advice): UK GDPR special-category data; US state consumer-health-data laws (e.g. Washington My Health My Data Act).

## Phase 0 gate (before any app code)
- Landing page + 30-sec demo video + waitlist + paid pre-order.
- Concierge test: 20 US/UK Apple Watch lifters coached manually over messaging.
- **Pass:** 500+ waitlist AND 30+ paid pre-orders within 6 weeks of the Nov 10 launch (**gate: 2026-12-22**). Miss → rethink before building.

## How to work with Shaik
- Non-coder: every code block gets a 2–4 sentence plain-English explanation.
- Direct, honest feedback. Kill scope creep. Surface costs before recommending any paid service.
- End each working session with: Built / Working / Broken-pending / Next.

# How the people who won this market actually built it

Researched 2026-10-31 from primary sources: Hevy's own account of building the
app, their founder's interview on growth, and published retention benchmarks.

Hevy matters more than any general "how to design an app" advice, because Hevy
is the app ZeroLog is competing with. They went from zero to two million
downloads in four years, bootstrapped, and wrote down how.

---

## 1. The number that should shape every decision

**Health and fitness apps retain about 3% of users at day 30.** Activation runs
~26% on day one and falls to ~10% by day 28 (Business of Apps benchmarks).

Ninety-seven of every hundred people who install stop using it within a month.
This is the defining fact of the category, not a detail. Features do not fix
it; a reason to open the app tomorrow does.

---

## 2. Hevy nearly died of the disease we keep being tempted by

In their own words, before launch:

> "Before I realized it, I had essentially designed a super bloated app that
> tried doing *everything* yet did *nothing* well."

The recovery was to name **three pillars** — workout logging, analytics,
social — and treat everything else as peripheral:

> "If we nailed those three things, our product would be simpler and better
> than our bloated competition."

**ZeroLog's equivalent, written down so it can be enforced:**

1. **Automatic logging** — the wrist counts the set. The differentiator.
2. **The next workout** — the plan adapts to what was actually lifted.
3. **Proof it worked** — history and progress that justify opening it again.

Food, coaching, social and a paywall are peripheral until those three are
undeniably good. Note that "food" is not a pillar; it never was.

## 3. Their validation lesson is one we should not repeat

Hevy surveyed 16 people outside a gym. The founder's retrospective:

> "Survey data will never be an accurate approximation of people's response
> compared to them *really* using your product. That's especially true with
> innovative/different ideas, where the user needs to reach the 'AHA moment'."

For ZeroLog the AHA moment is precise and physical: **finish a set, look at the
wrist, the reps are already there.** Nobody can evaluate that from a
description, a screenshot, or a survey. It has to happen on a wrist in a gym.

This is why the Apple Watch session matters more than any amount of further
building, and why asking people whether they *would* like automatic logging is
close to worthless.

## 4. What they did before writing code

> "I planned the entire UI on Sketch and made Marvel prototypes... In addition,
> I also prepared a library of reusable components, a text & color style guide,
> and an icon library."

A design system BEFORE the features. ZeroLog has the same thing in
`Style.swift` and `Theme.swift` — a fixed palette, two typefaces with defined
roles, shared components. That is the professional pattern, and it is why
changing the Today screen was a small edit rather than a rewrite.

## 5. How they grew, and what it implies for us

**Two million downloads on about $15k of ad spend.** Product-led: word of
mouth plus App Store and Google Play ranking. They deliberately did very little
App Store Optimisation early. They bootstrapped specifically to avoid VC
pressure, and priced BELOW competitors while betting on virality.

Their retention engine was **social** — "the Strava of Weightlifting". Users
followed each other and came back for the people.

**ZeroLog's retention engine must be different, and should be stated plainly:
removing the work.** Hevy has already won the "better manual logger" contest
and has years of head start. Competing on logging UI is competing on their
strongest ground with none of their resources.

The honest consequence: **if automatic rep counting does not work on a loaded
barbell, there is no product here** — only a worse Hevy. That is not pessimism,
it is the correct reading of the competitive position, and it is why the
hardware test outranks every remaining feature.

---

## 6. How a professional app of this size is structured

ZeroLog already follows this, which is worth knowing rather than assuming:

| Layer | Rule | Ours |
|---|---|---|
| **Engine** | Pure logic, no UI, no platform APIs, fully testable | `ZeroLogCore` — 195 tests, runs on Linux |
| **Platform shims** | Thin wrappers over sensors, storage, sync | `WatchMotionCapture`, `PhoneSettingsSync` |
| **UI** | Displays state and sends intent; computes nothing | SwiftUI views |
| **Design system** | Palette, type, components defined once | `Theme.swift`, `Style.swift` |

The test is whether the hard parts run without a device. Ours do: rep counting,
planning, progression and history are all exercised on a Linux CI box in nine
seconds. That is what makes a solo founder on a Windows PC able to ship an
Apple app at all.

The rule that keeps the layers honest is already the product rule: **code does
the numbers; AI only chooses and words things.**

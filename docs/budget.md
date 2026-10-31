# ZeroLog budget

Prices checked 2026-10-31 against live sources. Anything not checked is marked
UNVERIFIED. Figures are UK, inc. VAT where applicable.

**Already owned, so not in any total:** iPhone 14 Pro Max, a Windows PC.
**Deliberately avoided:** a Mac. All Apple builds run in cloud CI, which is
free on a public repository. That alone is a £500+ purchase designed out.

---

## Stage 1 — prove the thing that makes this a company

The USP is automatic rep counting from the wrist. Without it, ZeroLog is
another manual logger competing with Hevy, which is free and excellent. So this
stage is not optional, and nothing after it matters until it is done.

| Item | Cost | Recurring? | Why mandatory |
|---|---|---|---|
| Apple Developer Program | **£78.99/yr** (VERIFIED) | yes | Only route to installing on a watch. No free alternative exists — free provisioning needs a Mac, HealthKit is a paid capability, and watch apps cannot be sideloaded. |
| Apple Watch SE (2nd gen), refurbished | **~£135** (VERIFIED, listed £134.99) | one-off | The product runs on it. |

**Stage 1 total: ~£214**, of which £79 repeats yearly.

### Which watch, and why the cheapest one is fine
The SE (2nd gen) lacks `CMBatchedSensorManager`, the newer high-rate motion API
on Series 8 and up. That does not matter here: the fallback path is already
written and runs at 100 Hz, and reps happen below 2 Hz, so the slower API has
roughly fifty times the resolution needed.

Testing on the WEAKER device is arguably the better test. Battery cost is the
largest unmeasured risk in the project, and an SE is the worst case — if
continuous capture is acceptable there, it is acceptable everywhere.

New SE 3 is ~£200 and a refurbished Series 8 from Apple is ~£349. Neither buys
anything this project needs.

**Before spending anything: ask to borrow one.** A week with someone else's
Apple Watch answers the battery and accuracy questions for £0, and those two
answers decide whether the £135 is worth spending at all.

---

## Stage 2 — put it in front of other people

Only worth doing once Stage 1 says rep counting works on a barbell.

| Item | Cost | Recurring? | Notes |
|---|---|---|---|
| Domain | ~£12/yr (UNVERIFIED today) | yes | Needed for a landing page and support email, not for the app itself |
| Company formation | ~£50 (UNVERIFIED — Companies House fees changed Feb 2026) | one-off | Apple guideline 5.1.1(ix) says health apps "should be submitted by a legal entity… not an individual developer". A recommendation, not an absolute bar, but a real rejection risk for a health app. |
| TestFlight, App Store listing | £0 | — | Included in the developer programme |
| Exercise animations | £0 | — | Free, legally usable sources already identified |
| Fonts | £0 | — | Open Font Licence |
| Backend | £0 | — | Lift logging runs entirely on the phone. No server, no database, no hosting. |

**Stage 2 total: ~£62**

---

## Stage 3 — the complete app (food, coach, paywall)

This is where costs stop being trivial, which is the main argument for not
starting it yet.

| Item | Cost | Recurring? | Notes |
|---|---|---|---|
| AI vision API | ~$0.07 per user per month, worst case | yes, scales | Measured, not guessed: 1.6% of net revenue per subscriber. Breaks only above ~101 photos/day per user. |
| Server / proxy for API keys | £0–£5/month | yes | Free tier covers early usage. An API key cannot ship inside the app. |
| UK trademark, 1 class | **£205** (VERIFIED, IPO online) | one-off | |
| Each additional class | **£60** (VERIFIED) | one-off | Classes 9 and 42 are the relevant pair → **£265 total** |
| Lawyer: health data review | **UNVERIFIED — budget £500–£2,000** | one-off | UK GDPR special-category data plus US state health-data laws. The single largest and least predictable cost in the project. |

**Stage 3 total: roughly £800–£2,300**, dominated by legal.

---

## What to actually spend, and when

**Now: £214.** Or £79 if a watch can be borrowed.

Everything else waits, and waits for a reason rather than for thrift:

- **Trademark (£265) waits** until the name is settled. Registering a name the
  product later abandons wastes the whole fee.
- **Lawyer (£500+) waits** until there is something to review and a real
  prospect of users. Paying for a privacy review of an app nobody runs is
  buying advice that will be out of date before it is needed.
- **Company (£50) waits** until just before App Store submission.
- **Server costs are £0** until food logging exists, and food logging is
  deliberately deferred.

## The question the £214 answers

Does automatic rep counting work on a loaded barbell, and what does continuous
capture cost in battery?

Both are currently unknown at any price, and both are unknowable without
hardware. Every other number in this document is contingent on the answer: if
rep counting fails on a barbell, the right move is to stop, and the loss is
£214 rather than £2,500 and a year.

That is the whole reason for spending in this order.

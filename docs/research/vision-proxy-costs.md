# ZeroLog food-logging: cheapest defensible vision-API architecture
Research date: **2 November 2026**. All prices USD unless stated. Verified against vendor docs on this date.

---

## 0. Executive answer

| Decision | Choice | Why |
|---|---|---|
| Proxy host | **Cloudflare Workers free plan** | 100,000 req/day free, no card, no "non-commercial" clause, built-in rate-limit binding |
| Quota store | **Cloudflare D1** (not KV) | KV free tier is 1,000 **writes**/day — it will break first |
| Vision model | `gpt-5.6-luna` ($0.20/$1.20 per 1M) | Cheapest model with *documented* image tokenisation + `reasoning.effort: none` |
| Image detail | Resize to 512×384 on device, send `detail: "low"` | 231 image tokens vs **14,364** on default `auto` — 62× |
| Output control | strict JSON schema, `max_output_tokens`, `reasoning.effort: "none"` | output is 65% of per-call cost at 150 tokens |
| Caching | exact-match hash only; **skip** semantic + provider prompt caching | see §4 |
| Realistic cost | **$0.0083/user/month** at 30 photos | vs the $0.07 worst-case estimate |

---

## 1. Why the API key cannot ship in the app

An iOS `.ipa` is a zip. Anything compiled in is extractable:
- `strings`/`nm` on the binary, or `class-dump`, recovers literals in minutes.
- `Info.plist`, `.xcconfig`-baked values, and asset catalogs are plaintext.
- Obfuscation, XOR, keychain-at-first-launch, CloudKit-delivered keys: all defeated by attaching a debugger or an mitM proxy (Charles/mitmproxy + a trusted root on a jailbroken or simulator device) and reading the `Authorization` header off the wire.
- TLS pinning raises effort but the key still exists in process memory on a device the attacker controls.

The threat is not theoretical for this product: a leaked key on a billing-enabled OpenAI org is a *direct charge to the founder's account*, and spend-limit enforcement is explicitly **not instantaneous** (OpenAI docs: "recorded spend can slightly exceed the configured amount").

### Minimal proxy — the critical design choice

Do **not** build a passthrough proxy (`/v1/chat/completions` forwarder). That is a free OpenAI key with extra steps. Build **one task-specific endpoint**:

```
POST /v1/identify-meal
  headers: Authorization: Bearer <app-issued session token>
  body:    { "image": "<base64 JPEG, <=200KB>", "hint": "<optional, <=64 chars>" }
  ->       { "items": [ {"fdc_id": 173410, "name": "...", "grams": 150, "confidence": 0.8} ] }
```

Server-owned and **not client-settable**: model, system prompt, `detail`, `max_output_tokens`,
`reasoning.effort`, response JSON schema, temperature. Client supplies only pixels.

Consequences:
- An abuser who extracts the endpoint gets a food-identifier, not an LLM. Resale value ≈ 0.
- Prompt-injection surface shrinks to the image itself.
- You can swap model/provider without an app update.
- Calories never come from the model — it returns an **FDC ID + grams**; the bundled USDA
  FoodData Central table does the arithmetic on device. This is the "code does the numbers" rule
  enforced *architecturally*, and it also keeps output tokens tiny (an ID is ~6 tokens, a
  nutrition paragraph is ~200).

Reject at the edge, before spending a token: wrong content-type, body > 200 KB, missing/invalid
session token, failed quota check, non-JPEG magic bytes.

---

## 2. Hosting — real numbers, checked 2 Nov 2026

### Cloudflare Workers — RECOMMENDED
Source: https://developers.cloudflare.com/workers/platform/pricing/ (Oct 2 2026) and
https://developers.cloudflare.com/workers/platform/limits/ (Oct 29 2026)

| | Free | Paid |
|---|---|---|
| Requests | **100,000/day** | $5/mo min, 10M/mo incl., +$0.30/M |
| CPU time | **10 ms/invocation** | 30 s default, up to 5 min; 30M CPU-ms incl., +$0.02/M |
| Subrequests | 50/request | 10,000 |
| Duration (wall) | unlimited on HTTP | unlimited |
| Request body | 100 MB | 100 MB |

- **CPU time ≠ wall time.** Waiting on `fetch()` to OpenAI does *not* count. A proxy that only
  validates + forwards uses ~1–3 ms. Average Worker is 2.2 ms per Cloudflare's own docs.
- **The 10 ms trap:** base64-decoding or re-encoding a 3 MB image in the Worker will blow 10 ms.
  **Resize on device.** This is a cost reason *and* a correctness reason.
- Over the daily cap you get Error 1027; route "fail mode" is configurable (fail open = bypass
  Worker, fail closed = 1027 page). Choose **fail closed** for a billing-exposed endpoint.
- No card needed for the free plan.

Storage, free tier (same pages + https://developers.cloudflare.com/kv/platform/pricing/ Oct 30 2026):

| Store | Free limits | Verdict for quota counters |
|---|---|---|
| **KV** | 100k reads/day, **1,000 writes/day**, 1 GB | ✗ writes cap breaks at ~33 active users |
| **D1** (SQLite) | 5M rows read/day, **100,000 rows written/day**, 5 GB | ✓ use this |
| **Durable Objects** | 100k req/day, 13,000 GB-s/day | ✓ strongly consistent, best for strict caps |
| **Rate Limiting binding** | free, part of Workers | ✓ use for burst control |
| Workers AI | **10,000 Neurons/day free** | fallback inference, see §3 |

### Deno Deploy
Source: https://deno.com/deploy/pricing (checked 2 Nov 2026)
Free: **1M requests/month**, 20 GiB egress, 10 CPU-hr, 150 GiB-hr memory, 10 apps, 5 custom
domains, Deno KV 1 GiB / 1M reads / **500k writes per month**. Pro $20/mo (5M req, then $2/M).
Note: Deno announced it is **joining Cloudflare** (banner on the pricing page) — migration risk.
Deno KV's 500k writes/month is far more generous than Workers KV's 1,000/day.

### Vercel
Source: https://vercel.com/docs/plans/hobby (last updated Sep 14 2026)
Hobby free: **1M function invocations/mo**, 4 CPU-hr Active CPU, 360 GB-hr provisioned memory,
1M CDN requests, 100 GB fast data transfer, 10 GB fast origin transfer.
**Blocker: the Hobby plan is explicitly non-commercial/personal use only** (fair-use guidelines).
A published App Store app with users is a poor fit; Pro is $20/mo. Also, exceeding a Hobby limit
pauses the feature for up to 30 days — a hard outage with no paid overflow.

### Fly.io
Source: https://docs.fly.io/about/pricing/ (checked 2 Nov 2026)
**No free allowance.** "No monthly platform fee… the smallest always-on app costs $2.19 per 30
days" (`shared-cpu-1x`/256 MB, `iad`). 512 MB = $3.69/mo, 1 GB = $6.70/mo. Egress $0.02/GB
NA+EU. Auto-stop machines reduce this but add cold starts. Wrong tool: a stateless 3 ms proxy
should not rent a VM.

### Ranking for a £0–100 budget
1. **Cloudflare Workers free** — highest free ceiling (100k/day = 3M/mo), no commercial
   restriction, rate-limiting + D1 + DO in the same free account, $5/mo escape hatch.
2. Deno Deploy free — simplest DX, 1M/mo, but acquisition/migration uncertainty.
3. Vercel Hobby — ample limits, wrong licence for a shipping app.
4. Fly.io — costs real money from day one.

Headroom check, 1,000 users × 30 photos/mo = 30,000 req/mo ≈ 1,000 req/day:
Workers free = 100× headroom. Workers KV writes = ~1× (would break). D1 = 100×.

---

## 3. Token / prompt optimisation for vision calls

OpenAI patch tokenisation (source: https://developers.openai.com/api/docs/guides/images-vision):
```
patch_count = ceil(w/32) * ceil(h/32)
if patch_count > patch_budget:  shrink proportionally to fit budget
billable_image_tokens = ceil(patch_count * model_multiplier)
```
Multiplier is **1.2** for gpt-6-astra, gpt-5.6-sol/terra/luna, gpt-5.5, gpt-5.4(+mini/nano),
gpt-5.2. (1.62 for gpt-4.1-mini, 2.46 gpt-4.1-nano, 1.5 gpt-5-nano, 1.72 o4-mini.)

Detail-level sizing for the gpt-5.6-* family:
- `low` → fits within **512 × 512**
- `high` → fits within 2048 × 2048 **and** a 2,500-patch budget
- `original` → native size (only capped at 65,535 px/side)
- **`auto` (the DEFAULT) == `original` for gpt-6-astra and the gpt-5.6-* family**

### The single biggest cost trap
A 12 MP iPhone photo (4032 × 3024) sent with default `detail`:

| detail | resized to | patches | **image tokens** |
|---|---|---|---|
| `low` | 512 × 384 | 192 | **231** |
| `high` | 1824 × 1368 | 2,451 | **2,942** |
| `auto`/`original` | 4032 × 3024 | 11,970 | **14,364** |

**62× difference** between the default and `low`. My implementation of the documented algorithm
reproduces all three of OpenAI's published worked examples for gpt-6-astra/high exactly
(1024×1024→1229, 2048×2048→3000, 4096×512→2458), so these figures are trustworthy.

Food identification does not need 12 MP. A plate of food at 512×384 is legible. If testing shows
`low` misses small items, 768×576 with `detail:"high"` costs 519 tokens — still 28× cheaper than
the default.

### Output tokens dominate — and reasoning is billed as output
`gpt-5.6-luna` supports `reasoning.effort: none | low | medium (DEFAULT) | high | xhigh | max`
(source: model page, developers.openai.com/api/docs/models/gpt-5.6-luna). Reasoning tokens bill
at the **output** rate ($1.20/1M).

Per-call cost, 231 image + 250 prompt tokens, gpt-5.6-luna standard tier:

| config | $/call | $/user-mo @30 | vs best |
|---|---|---|---|
| effort=none, 60-tok JSON | $0.000168 | $0.0050 | 1.0× |
| effort=none, 150-tok JSON | $0.000276 | $0.0083 | 1.6× |
| effort=low (~300 reas.) | $0.000636 | $0.0191 | 3.8× |
| **effort=medium (DEFAULT, ~800 reas.)** | $0.001236 | $0.0371 | **7.3×** |
| effort=high (~2000 reas.) | $0.002676 | $0.0803 | 15.9× |

(reasoning-token counts 300/800/2000 are my illustrative estimates — measure your own.)

At 150 output tokens, **output is 65% of the per-call cost**; at 400 output tokens it is 83%.
So after image resizing, the next-biggest lever is output length, not prompt length.

### Concrete techniques, in order of payoff
1. **Resize + recompress on device** before upload (`CGImageSourceCreateThumbnailAtIndex`, long
   edge 512 px, JPEG q0.7 → ~40 KB). 62× token cut, 88× upload cut (1.6 MB/user/mo vs 137 MB),
   faster UX, and keeps the Worker under 10 ms CPU. **Strip EXIF** while you are there (GPS!).
2. **Pin `detail: "low"` server-side.** Never let it default to `auto`.
3. **`reasoning.effort: "none"`.** Up to 7× on output.
4. **Set `max_output_tokens`** (e.g. 200). This is your hard ceiling against a runaway
   generation; it is the one guard that works even if everything else is misconfigured.
5. **Structured Outputs / strict JSON schema** returning `{fdc_id, grams, confidence}` only.
   No prose, no explanations, no calorie numbers (code does those). An FDC ID is ~6 tokens;
   a friendly paragraph is ~200.
6. **Short system prompt.** ~150–250 tokens is enough: role, the output schema, "return at most
   6 items", "if unsure set confidence low". Do not paste the USDA list into the prompt — ship it
   on device and have the model return IDs, or do a local fuzzy match on the returned name.
7. **One image per request.** Resist "send 3 angles".
8. **Batch API is 50% off** but is async/offline — unusable for interactive logging. Only
   relevant if you add an overnight "re-check low-confidence meals" job.

### Model comparison, same 231-image + 250-prompt + 150-output call
| model | input $/1M | output $/1M | $/call |
|---|---|---|---|
| gpt-6-luna | 0.10 | 0.50 | $0.000123 |
| **gpt-5.6-luna** | 0.20 | 1.20 | **$0.000276** |
| gpt-5.4-nano | 0.20 | 1.25 | $0.000284 |
| gemini-2.5-flash | 0.30 | 2.50 | $0.000519 |
| gpt-4.1-mini | 0.40 | 1.60 | $0.000432 |
| gemini-3.1-flash-lite | 0.45 | 2.70 | $0.000621 |

`gpt-6-luna` is cheapest and accepts image input, **but** it is absent from OpenAI's published
image-multiplier table and model-sizing table, so its vision token count is unverified. Cost it
at gpt-5.6-luna rates until you measure `usage.input_tokens` on a real call.

### Genuinely-zero-cost options (worth a spike)
- **Gemini free tier**: Gemini 3.8/3.6 Flash, 3.1 Flash-Lite, 2.5 Flash are "Free of charge"
  for input *and* output (https://ai.google.dev/gemini-api/docs/pricing). Two caveats:
  (a) free-tier data **is** used to improve Google's products — a real problem for photos of
  people's meals, and you must say so in your privacy policy; (b) per-model free RPM/TPM/RPD are
  **no longer published** — the rate-limits page says to view them in AI Studio. Unverified.
- **Cloudflare Workers AI**: 10,000 Neurons/day free on the Workers Free plan;
  `@cf/meta/llama-3.2-11b-vision-instruct` at $0.049/M in, $0.676/M out. Rough estimate
  ~600 calls/day inside the free allocation (image-token behaviour for this model unverified).
  Accuracy for food ID will be well below a frontier model — but it is a $0 degraded fallback.

---

## 4. Caching — what actually helps here

### (a) Exact-match cache — YES, cheap, do it
Key = `sha256(normalised_jpeg_bytes) + prompt_version + model`. Store the result JSON in D1/KV
with a TTL (30 days).

When it hits: the *same photo* re-submitted. Real causes — user taps "retry" after a network
error; duplicate upload from an offline queue flush; the user re-logs the identical saved photo;
your own retry logic. Realistically **5–15%** hit rate, and critically it is the cache that
protects you during an incident (a retry storm costs $0 instead of 10×).

Cost: 1 extra read + 1 conditional write. On Workers free, KV's 1,000 writes/day is the limiting
factor — **use D1** (100,000 rows written/day free). Worth it because it is ~20 lines of code.

Also hash **after** the device resize, so the key is stable (the original is never uploaded).

### (b) Semantic / similarity cache — NO
The idea: embed the query, ANN-search prior queries, return a cached answer above a cosine
threshold. Published results report 61–69% hit rates and ~68% API-call reduction on *text* LLM
traffic (GPT Semantic Cache, arXiv 2411.05276; MeanCache reports ~31%).

Why it fails for ZeroLog:
- **Wrong input type.** Those numbers are for natural-language queries. Two photos of
  "chicken salad" that embed as similar may differ in the thing you actually need — **portion
  size**. Returning a cached 150 g answer for a 400 g plate is a silent, wrong calorie number in
  a health app. This is the one failure mode you cannot ship.
- **The economics invert.** Each lookup needs an image embedding. `text-embedding-3-small` is
  $0.02/1M, but you need a *vision* embedding — i.e. another model call, plus a vector index.
  Cloudflare Vectorize is **paid-plan only** ($5/mo minimum).
- **It's defending a $0.0003 call.** You would spend engineering time and a vector DB to maybe
  shave 30% off $8/month at 1,000 users.

Revisit only if (i) you are spending >$50/mo on inference and (ii) you have labelled data showing
the false-hit rate on portions is acceptable. Not now.

### (c) Provider-side prompt caching — NO, it cannot engage
Source: https://developers.openai.com/api/docs/guides/prompt-caching

> "The minimum cacheable prompt length is **1,024 visible input tokens** for GPT-5.6 and later."

A ZeroLog request is ~250 prompt tokens + 231 image tokens = ~481 visible input tokens.
**Below the 1,024-token floor, so no cache entry is ever created.** Prompt caching is literally
inert for this workload.

Three further reasons not to chase it:
- You would have to pad the prompt past 1,024 tokens. Even if steady-state reads (0.1× input)
  then beat the unpadded 250 tokens, the saving is on the *input* half of a call where output is
  65% of cost — a ~9% total saving on an $8/month bill. Noise.
- Cache **writes** cost 1.25× uncached input (30 m) or 2.5× (12 h). Low-traffic apps pay writes
  and rarely collect reads.
- Cache entries live on individual machines and "traffic above 15 requests per minute can lead to
  overflow routing." A hobby app's traffic is too sparse and too scattered to land hits.

If the prompt later grows past 1,024 tokens (e.g. you inline a food taxonomy — don't, ship it on
device), then: put the static block first, add an explicit `prompt_cache_breakpoint` after it,
use `prompt_cache_options.mode: "explicit"` so the per-request image is never written to cache,
and keep the image **last**. The documented gotcha is that a static-prefix + dynamic-suffix
request in implicit mode writes *through* the dynamic content and never produces a reusable
prefix.

### (d) The cache that actually matters: on-device
A logged meal's nutrition is computed locally from the bundled USDA table, so re-opening,
editing, or recomputing a meal is **free** — zero API calls. Cache the per-photo
`{fdc_id, grams}` result in the local store and never re-call the model for a meal already
logged. This is worth more than every server-side cache combined.

---

## 5. Per-user rate limiting and quotas

### Identity before counting
You cannot rate-limit per user without a stable user identity, and IP is useless (CGNAT, shared
campus/school wifi). Options, cheapest first:

1. **Apple App Attest** (DeviceCheck framework, free, iOS 14+) — the right primitive.
   Flow (https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server):
   server issues a one-time challenge → app calls `DCAppAttestService.shared.generateKey()` +
   `attestKey(_:clientDataHash:)` → server validates the attestation object against Apple's App
   Attest Root CA, checks the nonce, the App ID (TeamID.bundleID), and stores the public key →
   thereafter the app signs each request with `generateAssertion` and the server verifies the
   signature and a monotonic counter.
   This proves the request came from **your genuine app on a genuine Apple device** — the single
   highest-leverage anti-abuse control available to a solo iOS dev, and it costs nothing.
   Also: `DeviceCheck`'s two per-device bits survive reinstall, so you can mark a device as
   "already used its free trial" without an account.
   Limit: Apple's own docs note a modified OS "might bypass restrictions", and the risk metric
   (receipt→Apple server→fraud metric) needs tuning. It is a strong filter, not a wall.
2. **Anonymous account + signed session token.** Server mints a short-lived (24 h) JWT/HMAC token
   keyed to an opaque `user_id`. Cheap, but trivially farmable without (1).
3. Firebase App Check — same idea, cross-platform, free tier, more moving parts.

### Three layers of limits (defence in depth)
| Layer | Mechanism | Suggested value |
|---|---|---|
| Burst | Cloudflare Rate Limiting binding, `key = user_id` | 5 / 60 s |
| Daily | D1/DO counter, `key = user_id:YYYY-MM-DD` | 25–30 photos/day |
| Monthly | D1/DO counter, `key = user_id:YYYY-MM` | 300 photos/mo |
| Global kill switch | single D1 row / DO: month-to-date spend estimate | hard stop at your £ cap |

The Rate Limiting binding (https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/):
```jsonc
"ratelimits": [{ "name": "MEAL_RL", "namespace_id": "1001",
                 "simple": { "limit": 5, "period": 60 } }]   // period MUST be 10 or 60
```
```js
const { success } = await env.MEAL_RL.limit({ key: userId });
if (!success) return json(429, { error: "rate_limited", retry_after: 60 });
```
**Read the caveat:** these limits are **per Cloudflare location** and approximate — "Requests can
exceed your configured limit while counts update in the background." Sydney and London keep
separate counters. That is fine for burst smoothing; it is **not** a spend cap. For the real cap
use a **Durable Object** (strongly consistent, single-threaded per key) or a D1 row with a
conditional `UPDATE ... WHERE used < limit` so the decrement is atomic.

### Count before you call, and count the right thing
- Decrement the quota **before** the upstream call, not after. Otherwise a crash between call and
  write gives a free request, and a concurrent burst slips through.
- Record **actual** `usage.input_tokens` / `output_tokens` from the response into a running
  month-to-date cost estimate. Don't trust your own estimate — the whole point is to detect the
  case where your estimate was wrong.
- Keep a per-user cost column, not just a count. One user sending 200 KB images costs more than
  one sending 40 KB, and a per-count quota hides that.

### Handling abuse specifically
- **Cap the input, not just the rate.** Reject bodies > 200 KB and non-JPEG magic bytes at the
  edge. This single rule removes the "upload a 30 MP image to burn 15,000 tokens" attack, which
  is a 39× cost amplification per request.
- **Reject client-supplied model parameters.** The server picks model/detail/effort/max_tokens.
  If the client can set them, your rate limit is meaningless — see the blast-radius table below.
- **Pin the task.** A fixed system prompt + strict output schema means a stolen endpoint can't be
  resold as general inference.
- **Escalating response:** 429 with `Retry-After` → 24 h soft block → device-level block via the
  App Attest public key (not the user_id, which they can re-register) → revoke.
- **Alerting:** a Workers cron trigger (5 free/account) that reads month-to-date spend from D1
  once an hour and emails/pushes at 50% / 80% / 100% of your cap. Free.
- **Belt and braces at the provider:** OpenAI **project-scoped** API key with a **hard** monthly
  spend limit *and* a per-model rate limit set in Project → Limits
  (https://developers.openai.com/api/docs/guides/spend-limits). Use a dedicated project so a
  mistake can't drain anything else. Enforcement is not instantaneous, so set the hard limit
  *below* what you can afford, e.g. hard-limit $20 when your real ceiling is £100.
- Gemini equivalent: spend-based rate limits exist but are **N/A on the Free tier**, Tier 1 is
  $10 per rolling 10 minutes (https://ai.google.dev/gemini-api/docs/rate-limits).

### Blast radius, if you get this wrong
| scenario | $/call | 1 req/s for 24 h |
|---|---|---|
| server-pinned cheapest config | $0.000168 | $14.53/day |
| client-controlled worst config (full-res image + high reasoning + 1000-tok output) | $0.006523 (**39×**) | **$563.57/day** |
| same at 5 req/s | | **$2,817.85/day** |

A 17-year-old with no card cannot absorb $563 in a day. The server-pinned configuration is not a
nicety; it is the difference between a bad day and a ruinous one.

---

## 6. Failing gracefully at the budget cap

Design rule: **the app must remain fully useful with the AI switched off.** Photo→food is a
*shortcut* for manual entry, never the only path. If that is true, every failure below degrades
to "normal app" instead of "broken app".

### Error taxonomy and client behaviour
| Condition | Status + body | App behaviour |
|---|---|---|
| Per-user daily/monthly quota used | `429 {code:"user_quota_exhausted", resets_at}` | "You've used your 25 photo logs today — resets at midnight. Log this meal by searching instead." Open manual search **pre-filled**. |
| Global budget cap hit | `503 {code:"ai_budget_reached", retry_after}` | "Photo logging is paused until <date>. Manual logging still works." No blame on the user; no retries. |
| Upstream 429 / 5xx | `503 {code:"upstream_unavailable"}` | One retry with jittered backoff, then fall back to manual. Never retry in a loop. |
| Low model confidence | `200` with `confidence < 0.5` | Show the guess as an *editable suggestion*, never auto-commit. |

### Specifics that matter
- **Check the cap before spending the token, server-side.** A client-side check is a suggestion.
- **Make the kill switch a config read, not a deploy.** One D1 row / KV key
  (`ai_enabled = false`) read at the top of the handler. You can stop the bleeding from your
  phone in seconds without shipping an app update.
- **Degrade, don't disable.** Tiered fallback: paid frontier model → Gemini/Workers AI free tier
  (accuracy warning shown) → manual entry. The middle rung means hitting the cap is a quality
  regression, not an outage.
- **Return `resets_at` / `retry_after` in the body** so the UI can say *when* it comes back.
  "Something went wrong" generates support email you don't have time for; "resets at midnight"
  doesn't.
- **Queue, don't drop.** If the user is offline or you're capped, store the photo locally with
  intent and offer to identify it later. Do **not** auto-flush a queue of 50 photos the instant
  the cap resets — that's a self-inflicted spike. Drip it, or require a user tap.
- **Distinguish "paused" from "broken" in the UI.** A paused feature with a date reads as
  deliberate; a spinner that fails reads as a bad app and earns 1-star reviews.
- **Don't put a payment wall in the error path** until you can actually take payments. Today the
  honest copy is "free photo logging, N per day."
- **Instrument it:** log every 429/503 with its code. If `user_quota_exhausted` fires constantly,
  your quota is too tight; if `ai_budget_reached` fires, your per-user quota × users is wrong.

### Sanity check on the £0–100 budget
At the recommended configuration ($0.000276/call), **$100 buys ~362,000 photo identifications** —
about 12,000 user-months at 30 photos each. The budget is not the binding constraint; a
misconfiguration is. Spend the effort on the three server-pinned parameters
(`detail:"low"`, `reasoning.effort:"none"`, `max_output_tokens`) and the atomic quota counter,
not on clever caching.

---

## 7. Flagged as unverified
- `gpt-6-luna` image tokenisation: cheapest listed vision model ($0.10/$0.50) and the model page
  confirms image input, but it is **absent from the published image-multiplier and model-sizing
  tables**. Measure `usage.input_tokens` before relying on it.
- Reasoning-token counts per effort level (300/800/2000) are my illustrative estimates, not
  published figures.
- Gemini free-tier RPM/TPM/RPD: **no longer published** in public docs; the rate-limits page
  defers to AI Studio. Do not design against assumed numbers.
- Workers AI `llama-3.2-11b-vision-instruct` image-token behaviour, hence the "~600 calls/day
  inside the free 10,000 Neurons" figure, is an estimate.
- JPEG file sizes in §3 are typical values, not measured on ZeroLog's actual photos.
- Deno Deploy's long-term terms are uncertain given the announced Cloudflare acquisition.
- This research did not test the accuracy of food identification at 512×384 vs full resolution.
  **That is the one experiment worth running before committing**, because it is the only input to
  the cost model that is not already settled by the published pricing.

## Sources (all checked 2 November 2026)
- https://developers.cloudflare.com/workers/platform/pricing/
- https://developers.cloudflare.com/workers/platform/limits/
- https://developers.cloudflare.com/kv/platform/pricing/
- https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
- https://developers.cloudflare.com/workers-ai/platform/pricing/
- https://deno.com/deploy/pricing
- https://vercel.com/docs/plans/hobby
- https://vercel.com/docs/limits/fair-use-guidelines
- https://docs.fly.io/about/pricing/
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/image-cost-calculator
- https://developers.openai.com/api/docs/guides/prompt-caching
- https://developers.openai.com/api/docs/guides/spend-limits
- https://developers.openai.com/api/docs/models/gpt-5.6-luna
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/rate-limits
- https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
- https://developer.apple.com/documentation/devicecheck/assessing-fraud-risk
- https://arxiv.org/html/2411.05276 (GPT Semantic Cache)

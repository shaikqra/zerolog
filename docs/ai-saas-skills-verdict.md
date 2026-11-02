# Can we use those "AI SaaS" skills? Researched answers

Dated 2026-11-02. Three questions researched against primary sources, with the
headline benchmark re-run independently before any of it was written down.

All three came back the same way: **we need LESS than the list said, not more.**

---

## 1. Billing — the list was wrong, and expensively so

**Stripe cannot be used for ZeroLog's subscription.** App Store Review
Guideline 3.1.1, verbatim:

> "If you want to unlock features or functionality within your app, (by way of
> example: subscriptions...) you must use in-app purchase. Apps may not use
> their own mechanisms to unlock content or functionality, such as license
> keys..."

A Stripe checkout that flips an `isPro` flag is an instant rejection. The
correct path is one auto-renewable subscription through **StoreKit 2**.

**Commission: 15%, from the first billing cycle.** The App Store Small Business
Program applies under $1M/year proceeds. The usual "30% then 15% after a year"
rule does NOT apply to Small Business Program members — they get 85% from day
one.

**No server required.** This matters more than the rate. Apple's own docs treat
server validation as optional: "If StoreKit returns a transaction as verified,
the transaction is valid for the device." Reinstalls and new devices are
handled automatically. A server only becomes necessary for external purchase
links, signed promotional offers, or real-time refund notifications — none of
which a single-tier subscription needs.

So Phase 4 billing is: one product, StoreKit 2, on-device verification, £0
infrastructure, no accounts, no new GDPR surface.

**Pricing correction worth noting.** A £4.99/month price nets roughly £3.53
after VAT and the 15% commission. To actually clear the ~$4.25/month the unit
economics assume, the price point needs to be nearer $5.99 in VAT territories.
(My arithmetic from Apple's published rules, not an Apple-published figure —
confirm in App Store Connect's pricing tool.)

**Free trial:** one introductory offer per subscription group, ever. Choose the
length deliberately; a lifting app shows its value within two gym sessions.

**US link-outs are currently commission-free but actively litigated** (Ninth
Circuit Dec 2025, Supreme Court cert granted Jun 2026, Apple proposing 5-15% on
remand). Do not build a revenue plan on that window. UK steering is not
permitted at all today.

---

## 2. Vision API cost — eight times cheaper, and one trap that could ruin us

**The real cost is $0.0083 per user per month**, not the $0.07 worst case I
estimated earlier. £100 buys roughly 362,000 food identifications. Budget is
not the constraint here.

**A misconfiguration is.** The finding that matters:

| What the client controls | Cost per call | Cost at 1 request/second |
|---|---|---|
| Server-pinned cheapest config | $0.000168 | $14.53/day |
| Client-controlled worst config | $0.006523 | **$563.57/day** |

A 39x difference. The specific trap: for current models the DEFAULT image
detail setting behaves as *original resolution*. A 12MP iPhone photo at default
costs 14,364 image tokens; the same photo resized to 512px costs 231. **62x, on
a default.**

So the rules are architectural, not optional:

- **Resize on device** to 512px long edge, strip EXIF/GPS. 62x fewer tokens,
  88x less upload.
- **The server pins model, detail, reasoning effort, max output tokens and the
  JSON schema.** The client sends pixels and nothing else.
- **Never build a passthrough proxy.** A `/v1/chat/completions` forwarder is a
  free API key with extra steps. One task-specific endpoint that returns a food
  ID and grams has no resale value if stolen.
- **The model returns an ID and a weight, never a calorie number.** The bundled
  USDA table does the arithmetic on device. This enforces "code does the
  numbers" in the architecture rather than in a prompt.

**Hosting: Cloudflare Workers free tier** — 100,000 requests/day, no card
required. One caveat found: Workers KV allows only 1,000 writes/day on free,
which would break first; use D1 (100,000/day) for quota counters.

**Caching:** exact-match only, keyed on the image hash. **Semantic caching is
actively dangerous here** — two photos of "chicken salad" can embed as nearly
identical while differing in the one thing that matters, portion size. A cached
150g answer for a 400g plate puts a silently wrong number into a health app.
Provider-side prompt caching cannot engage at all: it needs 1,024+ input
tokens and our request is ~481.

**Identity for rate limiting: Apple App Attest**, free, proves the request came
from the genuine app on a genuine device without requiring accounts.

---

## 3. RAG and vector databases — not justified, and the benchmark proves it

The recommendation to build RAG with a vector database (pgvector, Pinecone)
fails on three independent counts.

**The corpus is 25x smaller than assumed.** FoodData Central's ~400,000 foods
are overwhelmingly *branded* products carrying a barcode — matched by exact
GTIN lookup, not similarity. The text-matchable generic corpus is about
**15,000 short strings**. Published work on this exact problem (FoodScribe)
found that *including* branded foods made retrieval WORSE, and indexed only
13,590 generic descriptions.

**At that size, plain SQLite search ties the best published AI system.** The
paper most often cited to justify embeddings for food matching tested fuzzy
matching, TF-IDF, embeddings and LLMs — but never tested BM25, the algorithm
SQLite ships free on every iPhone. Their ground truth is public, so we ran the
missing arm. Re-run independently before publishing this:

| Method | Top-1 accuracy |
|---|---|
| Fuzzy matching | 7.21% |
| TF-IDF (word) | 57.85% |
| TF-IDF (char n-gram) | 59.82% |
| **SQLite FTS5 BM25** | **65.28% ± 0.94** |
| *Paper's best: embeddings + LLM rerank* | *65.4%* |

**A statistical tie with the best published system — with no embedding model,
no vector index, no server, and no second vendor.**

The paper's apparent dense-retrieval advantage came from abstention
calibration, not from embeddings: their lexical arms were forced to guess on
the 47% of queries that have no valid answer. Give BM25 the same ability to say
"I don't know" and the gap closes.

**The highest-leverage work is not the retrieval method at all.** Fitting an
abstention threshold moved accuracy from 41.5% to 65.3% — worth more than the
entire lexical-versus-dense question.

**Size on device:** a bundled FTS5 index over the generic foods is roughly
2-6MB and answers in under a millisecond. An embedding index over the full
400,000 would be 307-492MB and would not fit — an argument against indexing
400,000, not for renting a server.

**And a product finding that outranks all of it:** on the genuinely hard
queries, *nothing* exceeds ~57% top-1 accuracy — lexical, dense or LLM. Food
matching cannot be made reliable by any known method. **A confirm-and-correct
interface is mandatory**, not a nicety. Which is exactly the human-in-the-loop
pattern the app already uses for sets.

---

## What to actually build, if food ever happens

1. Bundle Foundation + SR Legacy as a prebuilt SQLite file with an FTS5 index.
2. Barcode scan → exact lookup for packaged food. Never text-match branded items.
3. Fit an abstention threshold against a labelled set. Highest-value step.
4. Rerank the top 50 with a free token-overlap pass (+1.6 points, 0.2ms).
5. Hand the top 10 to the vision model already in the pipeline to choose from —
   this reproduces the paper's best architecture at zero marginal cost.
6. Always show a confirm/disambiguate step.
7. About 200 hand-written synonym pairs (rocket/arugula, courgette/zucchini)
   via an FTS5 custom tokenizer — this buys the one thing embeddings are
   genuinely good at, for a few hours and 0MB.

**Do not build:** a vector database, a retrieval server, or a 400,000-row
embedding index.

---

## The pattern across all three

Every answer reduced the architecture rather than expanding it. No server for
billing. A 40-line Worker instead of a backend. A 4MB file instead of a vector
database.

That is not frugality for its own sake. ZeroLog's structural advantage is that
it costs £0 to run, works offline in a basement gym, and holds no user data to
breach. Each item on that "AI SaaS" list would have traded that away for
capability we measured and found we do not need.

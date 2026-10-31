# Food data: where the calorie numbers come from

Checked against primary sources 2026-10-31. This answers the *licensing* and
*scientific provenance* question. It does **not** answer the privacy-law
question — see the bottom.

## The architecture this has to fit

Product rule: **code does the numbers; AI only chooses and words things.**

Applied to food, that means a photo is processed in two separate steps:

1. **AI identifies and estimates** — what the food is, and roughly how much.
2. **A database supplies the numbers** — calories and macros come from a lookup
   against measured composition data, never from the model.

This matters for three reasons. The model cannot hallucinate a calorie count
that no laboratory ever measured. The expensive call (vision) happens once
while the lookup is free. And the confidence range we show reflects *portion*
uncertainty, which is the honest uncertainty, rather than uncertainty about
whether the model remembered a number correctly.

---

## Primary source: USDA FoodData Central

**Licence: public domain, CC0 1.0.** Quoted from their API guide:

> "USDA FoodData Central data are in the public domain and they are not
> copyrighted. They are published under CC0 1.0 Universal (CC0 1.0). No
> permission is needed for their use, but we request that users list FoodData
> Central as the source of the data."

That is the cleanest licence available: **commercial use, no attribution
requirement, no share-alike.** We will cite it anyway because they ask and it
costs nothing.

**Access:** free API at `api.nal.usda.gov/fdc/v1`, needs a free data.gov key.
Rate limit 1,000 requests/hour per IP. Bulk downloads are also published, which
is the better option for us — see below.

**The data types, and which we want:**

| Type | What it is | Use it? |
|---|---|---|
| **Foundation Foods** | Lab-measured, with sampling metadata: number of samples, locations, dates, analytical method | **Yes** — the most scientifically defensible |
| **SR Legacy** | The long-standing Standard Reference set, broad coverage of basic foods | **Yes** — breadth |
| **FNDDS / Survey** | Foods as actually eaten, including mixed dishes and recipes | **Yes** — real meals are mixed dishes |
| **Branded Foods** | Manufacturer-supplied label data, US-centric | Partially — see the caveat |
| Experimental Foods | Research data | No |

**Caveat on Branded Foods:** the values are what the manufacturer printed on the
label, not independent measurements, and coverage is strongly US-weighted. For
UK packaged products it is thin.

---

## UK coverage: McCance and Widdowson's CoFID

Published by the UK government, the UK equivalent of SR Legacy and the standard
reference for UK food composition since 1940.

**Licence: Open Government Licence v3.0** — commercial use permitted,
**attribution required** (unlike CC0, this one is a condition, not a request).

Worth adding because the first market is US **and UK**, and UK generic foods
(and portion conventions) are better served here than by USDA.

---

## Open Food Facts: useful, but read the licence first

Crowdsourced barcode database with strong coverage of European packaged goods —
the obvious fit for scanning a product.

**Licence: ODbL for the database**, DbCL for individual contents, CC-BY-SA for
images. From their terms:

> "Derivative works must be shared under the same conditions."

**This is a share-alike obligation and it is the one real legal trap here.**
Building a derived food database from it can oblige us to publish that derived
database under the same terms. That is a meaningful decision for a commercial
product, not a formality.

Two further issues: they explicitly disclaim accuracy ("The information and data
is provided only for indicative information... must not be used for medical
purposes"), and the data is contributor-entered, so quality is uneven.

**Position: do not take Open Food Facts into the core dataset.** Revisit only
with legal advice, and only if barcode coverage turns out to matter.

---

## Commercial APIs: not needed

Nutritionix, Edamam, FatSecret and Spoonacular all sell nutrition APIs with
better branded coverage and worse terms — per-call pricing, caching
restrictions, and a dependency that can be repriced. Given CC0 and OGL cover
the scientific core for free, paying for this early would be buying a liability.

---

## What this means for cost and architecture

- **Food composition data: £0, forever.** No licence fee, no per-call cost.
- **Bundle the data, do not call the API at runtime.** A trimmed subset ships
  inside the app: lookups become instant and offline, there is no rate limit to
  hit, no key to protect, and no third party who can take the service away. The
  public-domain licence is what makes bundling legal.
- **The only per-use cost stays the vision call** (~$0.07/user/month worst
  case, already measured).
- This also keeps Stage 3 infrastructure smaller than budgeted: the lookup
  needs no server at all, only the vision proxy does.

---

## What this does NOT solve

**Licensing and privacy law are different problems**, and only the first is
answered here.

Using the data is free and legal. **Storing a person's food intake is
processing health-adjacent personal data** — UK GDPR special-category rules and
US state consumer-health-data laws (such as Washington's My Health My Data Act)
apply to what we hold about users, regardless of where the calorie figures came
from.

That remains a lawyer question, it is unpriced, and it is the largest
uncertainty in the budget. Nothing in this document reduces it.

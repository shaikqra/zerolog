# Recipes, macros and allergens: the research

Checked against primary sources 2026-10-31. Companion to `food-data.md`, which
covers where calorie numbers come from. This covers RECIPES, which are a
different problem legally and a much more dangerous one in one specific way.

---

## 1. How a recipe's macros are actually calculated

Not by asking a model. The real method has four steps, and skipping any of them
produces numbers that look plausible and are wrong.

**Step 1 — ingredients to grams.** "1 cup flour" must become a mass. USDA
FoodData Central publishes portion weights per food, which is what makes this
possible without guessing.

**Step 2 — sum the nutrients** from the composition database for each
ingredient at its mass.

**Step 3 — apply COOKING YIELD.** Food changes weight when cooked, mostly from
water and fat loss. A 100 g raw chicken breast is not 100 g cooked, so the
per-100-g figures for the finished dish differ from the raw sum even though the
nutrients barely changed. USDA publishes the *Table of Cooking Yields for Meat
and Poultry* for exactly this.

**Step 4 — apply NUTRIENT RETENTION FACTORS.** USDA's *Table of Nutrient
Retention Factors* covers 16 vitamins, 8 minerals and alcohol across ~290
foods and many cooking methods. Mostly a micronutrient concern; for macros the
big one is fat lost to a pan or gained from one.

Both tables are USDA ARS publications, so they carry the same public-domain
status as the rest of FoodData Central.

### Calories: pick ONE method and never mix

**General Atwater factors** — 4 kcal/g protein, 9 fat, 4 carbohydrate, 7
alcohol — applied to all foods regardless of type.

**Specific Atwater factors** vary by food group (meat protein is 4.27 kcal/g,
not 4.00, for instance). More accurate, more fiddly.

Mixing them across a dish, or recomputing calories that the database already
measured, yields totals that disagree with the source for no visible reason.

**The rule for us: take the energy value from the database where it exists;
compute only when it does not, and then say which method was used.** That is
the same principle as the rep counter — the numbers come from measurement, and
where they come from is recorded.

---

## 2. Where recipes can legally come from

### The datasets everyone reaches for are the ones to avoid

**RecipeNLG** (2.2 million recipes) and **Recipe1M+** are the obvious choices
and both are barred. RecipeNLG's own terms, verified today:

> "Researcher shall use the Dataset only for non-commercial research and
> educational purposes."

It also requires the user to indemnify the university against
> "claims arising from Researcher's use of the Dataset including but not
> limited to Researcher's use of any copies of copyrighted images or text that
> he or she may create from the Dataset."

That second clause tells you what is inside: scraped text whose rights were
never cleared. Using it in a commercial app is a licence breach on top of a
copyright risk. **Do not use either, at any stage, including for training.**

### What copyright actually protects in a recipe

US Copyright Office, Circular 33:

> "A mere listing of ingredients or contents, or a simple set of directions, is
> uncopyrightable."

The law separates the *idea* (combine these things in this way) from the
*expression* (the author's prose, headnotes, photographs, story). The facts are
free; the writing is not. UK law reaches a similar result by a different route.

**So the safe construction is:** structured ingredient quantities and a method
written in our own words. Copying a published recipe's prose is infringement
even though the ingredient list is not.

### Public-domain starting points

- **USDA FNDDS** — "foods as eaten", including mixed dishes with their
  underlying recipes. Public domain, already consistent with FoodData Central.
- **MyPlate Kitchen** (USDA) — recipes published by a US government agency.

These are American in style and limited in number, which is a product problem
rather than a legal one.

---

## 3. Allergens — the part that is different in kind

### The list is legally defined, not a matter of opinion

UK and EU, Regulation (EU) 1169/2011 Annex II — **14 allergens**, verified
against legislation.gov.uk today:

cereals containing gluten · crustaceans · eggs · fish · peanuts · soybeans ·
milk · nuts (almond, hazelnut, walnut, cashew, pecan, Brazil, pistachio,
macadamia) · celery · mustard · sesame · sulphur dioxide and sulphites above
10 mg/kg · lupin · molluscs

The **US list is different**: 9 major allergens, with sesame added by the
FASTER Act in 2023. Celery, mustard, lupin and sulphites are **not** on the US
list. An app shipping in both markets cannot use one list for both.

### The rule that must never be broken

**Flag presence. NEVER certify absence.**

A false positive is an inconvenience. A false negative can kill someone, and
the asymmetry is the entire reason Natasha's Law exists. An app that infers
ingredients from a photograph cannot know about cross-contamination, substituted
ingredients, cooking surfaces or what the kitchen did off-camera.

So: no "nut-free" badge, no green tick, no "safe for you" wording — ever. The
most the app may say is "contains nuts" when it can see them, and it must be
explicit that silence is not clearance.

This single rule is more important than every other sentence in this document.

### Where we stand legally

We would not be a food business, so the labelling duties in 1169/2011 do not
bind us directly — those fall on whoever sells the food. But publishing
allergen information that someone relies on creates its own exposure under
negligence and consumer-protection law, and "the model estimated it" is not a
defence.

---

## 4. The other legal lines

- **Nutrition and health claims** — Regulation (EC) 1924/2006 governs claims
  like "high protein" or "supports muscle growth". Permitted claims are a fixed
  list with fixed conditions; wording one freely is an offence. Stating measured
  macros is fine; characterising them is regulated.
- **Medical advice** — telling someone what to eat for a *condition* crosses
  toward regulated territory. Ours is a lifting app; it should describe food,
  not prescribe it.
- **UK GDPR** — a user's food intake is health-adjacent personal data,
  special-category if it reveals a condition (a coeliac filter certainly does).
  This is the lawyer line already in the budget, and allergen preferences make
  it *more* expensive, not less.

---

## 5. What this means for ZeroLog

**The data is free. The liability is not.**

Calorie lookup is a solved, zero-cost, zero-risk problem — public-domain
composition data, bundled, no server. Recipes with allergen information are a
different product with a life-safety failure mode that rep counting simply does
not have. Nobody is hospitalised by a miscounted set.

A defensible sequence if this is ever built:

1. **Macros for foods, from the bundled public-domain database.** No recipes,
   no allergens, no claims.
2. **Our own small recipe set**, written in-house, with macros computed by the
   four-step method and the method stated.
3. **Allergen flags only on recipes we authored**, where the ingredients are
   known rather than inferred — presence only, absence never.
4. **Photograph-derived allergen detection: do not build.** The input cannot
   support the certainty the output would imply.

The honest summary: steps 1 and 2 are a weekend of work and no new risk. Step 3
needs the lawyer who is already in the budget. Step 4 should stay unbuilt no
matter how good the vision model gets, because the uncertainty is in the
kitchen, not in the model.

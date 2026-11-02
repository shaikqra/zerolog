# Does food matching need vector search / RAG? — evidence review

**Date:** 2026-11-02 · **For:** ZeroLog food-logging feature · **Status:** recommendation, with measured evidence
**Bottom line: NO. Build SQLite FTS5 BM25. Do not add a vector DB, and do not add a server for this.**

---

## 1. The premise is wrong: the corpus is ~15k foods, not 400k

The "400,000 foods" figure is real but it is the wrong number for this problem. FoodData Central
splits into text-matchable generic foods and barcode-keyed branded label data:

| Dataset | Approx. rows | How you match it |
|---|---|---|
| SR Legacy | 7,793 | text |
| Foundation Foods | 469 | text |
| FNDDS (Survey) | ~7,000 per cycle | text |
| **Generic subtotal** | **~8k–15k** | **text** |
| Branded Foods | hundreds of thousands (3 GB unzipped) | **GTIN/UPC barcode = exact lookup** |

Branded items carry a GTIN. Matching them is an **exact integer lookup on a barcode scan**, which is
the single cheapest query in computer science — not a semantic retrieval problem. A photo of a
packaged food should route to barcode scanning (`VNDetectBarcodesRequest`, free, on-device), not to
a 400k-way nearest-neighbour search.

And including branded foods actively *hurts* text matching. FoodScribe (PMC13409120) built exactly
this pipeline and reported: *"We observed that using the USDA database of branded foods reduced the
accuracy of prediction and semantic retrieval, and hence the foods only from the Foundational, SR
Legacy and FNDDS (Survey foods) were encoded."* They indexed 13,590 USDA descriptions.

**So the design target is ~15k short strings.** Every scaling argument for a vector database
evaporates at that size.

---

## 2. Measured head-to-head on the only published food-matching benchmark

Source: Lemay et al., *"Evaluation of Large Language Models for Mapping Dietary Data to Food
Databases"*, J Nutr 2026, PMID 42309308. Ground truth + their own accuracy tables are public at
github.com/dglemay/USDA-Food-Mapping. This is the paper that is cited to justify embeddings for food
matching — it tested fuzzy matching, TF-IDF, dense embeddings and LLMs.

**It never tested BM25** — the algorithm SQLite FTS5 ships with, on every iPhone, for free.

I ran it. Scripts: `bench2.py` (ASA24), `bench4.py` (NHANES, cross-validated).

### Task B — NHANES-to-DFG2 (256 targets, 47.2% of queries have NO valid match)

This is the task that resembles the real product: sometimes the photographed food genuinely isn't in
the database and the system must say so.

| Method | Accuracy | Source |
|---|---|---|
| fuzzy `fuzz.ratio` | 9.28% | paper |
| TF-IDF | 47.24% | paper |
| **semantic embedding (GTE-large)** | **48.01%** | paper |
| o3 LLM, full DB in prompt | 40.87% | paper |
| **embedding + LLM rerank (their best system)** | **65.4%** | paper |
| fuzzy, no abstention | 7.21% | **measured — reproduces their 9.28%, validates harness** |
| TF-IDF word + fitted threshold | 57.85% ± 1.18 | measured |
| TF-IDF char 3–5gram + fitted threshold | 59.82% ± 0.25 | measured |
| **SQLite FTS5 BM25 + fitted threshold** | **65.28% ± 0.94** | **measured** |

Threshold fitted on a training half, scored on a held-out half, 5× random 50/50 splits — not tuned
on test data.

**FTS5 BM25 alone statistically ties their best system (65.28% vs 65.4%)** — with no embedding
model, no LLM call, no server, no vector index.

The paper's headline conflates two different things: *representation* (lexical vs dense) and
*abstention calibration*. Their lexical arms had no abstention threshold, so they were forced to
guess on the 47% of queries with no answer. Give BM25 the same abstention mechanism the embedding
arm effectively had, and the representational advantage disappears.

### Task A — ASA24-to-FooDB (9,913 targets, 1,198 queries)

| Method | top-1 (by ID) | top-1 (by desc) | top-5 | top-10 |
|---|---|---|---|---|
| paper: fuzzy | 81.39% | — | — | — |
| paper: TF-IDF | 81.39% | — | — | — |
| paper: **embedding** | **87.81%** | — | 85% @k=5 | **95% @k=10** |
| paper: embed+LLM | 85.98% | — | — | — |
| measured: fuzzy | 84.06% | 87.73% | — | — |
| measured: TF-IDF word | 84.97% | 88.73% | 94.99% | 97.33% |
| measured: FTS5 BM25 (unicode61) | 84.22% | 87.81% | 93.82% | **96.58%** |
| measured: **FTS5 BM25@50 + token_set rerank** | **85.81%** | **89.07%** | **95.49%** | 96.58% |

Two things matter here:

1. **76.1% of this benchmark is byte-identical strings.** Exact string equality solves three
   quarters of it. The real discriminating set is 286 queries (23.9%), and on that hard quarter
   *nothing* exceeds ~57% top-1. No retrieval method — lexical or dense — makes hard food matching
   reliable. **You need a confirm/disambiguate UI regardless of retrieval technology.** That is the
   most important product finding in this document.
2. **For candidate generation, which is what a hybrid actually needs, plain BM25 top-10 (96.6%)
   matches or beats the published embedding top-10 (95%).** If you are going to show the user a
   shortlist, or hand candidates to the vision model you are already paying for, lexical recall is
   already ~97% and there is almost nothing left for embeddings to add.

My reproductions land 3–4 points above the paper's published lexical numbers under consistent
scoring, and my un-thresholded fuzzy reproduces theirs closely (7.21% vs 9.28%), so the harness is
sound. I could not perfectly reproduce their scoring; treat cross-paper comparisons as ±4 points.
**UNVERIFIED:** I did not re-run their embedding arm (needs GTE-large weights), so the embedding
figures are theirs, not mine.

---

## 3. When does vector search genuinely beat good lexical search?

Dense retrieval earns its complexity on **vocabulary mismatch** — paraphrase, synonymy, cross-lingual
("rocket leaves" → "arugula"). It *loses* on rare tokens, identifiers and proper nouns.

- **BEIR** (Thakur et al., arXiv:2104.08663), 18 datasets: "BM25 is a robust baseline"; dense
  retrievers trained on MS MARCO **underperform BM25 on most out-of-domain datasets**. Dense wins
  in-domain (MS MARCO 0.408 vs BM25 0.228) and loses out-of-domain (BioASQ 0.383 vs 0.465;
  Touché-2020 0.162 vs 0.367).
- **Why**: dense models "are unable to represent rare terms well within the embedding space"
  (arXiv:2306.07471). Brand names and food qualifiers are exactly such rare tokens.
- **Scale tiers** (vgtc.io): under ~1k docs, in-process; 1k–20k, "brute force may suffice";
  **20k–200k is where an ANN index starts to be warranted**; 200k+ needs a dedicated engine.
  A 15k-item corpus sits below the ANN threshold.
- arXiv:2505.11582 found bespoke *lexical* vector search beat off-the-shelf semantic vector search on
  rigidly-structured documents, and ran significantly faster.

Food names are short, controlled-vocabulary noun phrases with heavy token overlap
("chicken breast, grilled" vs "chicken, broilers or fryers, breast, meat only, cooked, roasted").
This is the regime where IDF weighting shines and semantic nuance is thin. The genuine dense win —
"rocket"→"arugula" — is a **synonym-dictionary problem** at this scale: a few hundred hand-written
synonym pairs, which FTS5 supports natively via a custom tokenizer, covers most of it for free.

---

## 4. On-device feasibility: measured

### FTS5 (what SQLite already gives you on iOS)

Measured, SQLite 3.53.1, 400k rows, avg 61.6 chars / 9.0 tokens per row, external-content FTS5:

| Config | Rows | Data | FTS index | Total file | Build | q p50 | q p95 |
|---|---|---|---|---|---|---|---|
| porter | 10,000 | 0.7 MB | 0.4 MB | **1.1 MB** | 0.0 s | **0.32 ms** | 1.33 ms |
| porter | 50,000 | 3.6 MB | 2.0 MB | 5.6 MB | 0.1 s | 1.54 ms | 7.00 ms |
| porter | 400,000 | 28.7 MB | 16.0 MB | **44.7 MB** | 0.8 s | 14.81 ms | 58.99 ms |
| unicode61 | 400,000 | 28.7 MB | 16.1 MB | 44.8 MB | 0.7 s | 14.23 ms | 58.07 ms |
| trigram | 400,000 | 28.7 MB | 76.4 MB | 105.1 MB | 5.0 s | 3.72 ms | 22.13 ms |

Even the worst case — the **full** 400k branded corpus, which §1 says you don't need — is a 45 MB
file answering in ~15 ms. At the realistic ~15k generic foods it is **~2 MB and well under 1 ms**.
FTS5 is not a compromise here; it is overkill-capable.
*Caveat: measured on x86 Linux. iPhone CPU is comparable single-thread; NVMe is fast; expect the same
order of magnitude, but confirm on the 14 Pro Max before shipping.*

### Embeddings on device — the size wall

Exact arithmetic for a flat index, plus ~1.6× for HNSW graph links:

| Corpus | 384d fp16 flat | +HNSW | 384d int8 flat | +HNSW |
|---|---|---|---|---|
| 8,262 (generic) | 6.3 MB | 10.2 MB | 3.2 MB | 5.1 MB |
| 15,000 (generic+FNDDS) | 11.5 MB | 18.4 MB | 5.8 MB | 9.2 MB |
| **400,000 (with branded)** | **307 MB** | **492 MB** | 154 MB | 246 MB |

The practical ceiling for a foreground iOS app index is roughly 150 MB before memory-pressure
jettison risk, and Apple's **cellular download limit is 200 MB**.

- At ~15k foods: an embedding index is **11–18 MB. Entirely feasible on device.**
- At 400k foods: **307–492 MB at fp16 — does not fit.** This is the case that forces either
  aggressive product quantization (recall loss) or a server.

So the honest answer to "does embedding 400k short food names force a server?" is **yes, roughly** —
but that is an argument for not indexing 400k, not an argument for buying a server.

### iOS embedding options, if you ever want one

- **`NLEmbedding.sentenceEmbedding(for:)`** — ships in iOS 14+, free, on-device, zero download, zero
  dependency. The obvious zero-cost experiment.
- **`NLContextualEmbedding`** — iOS 17+, requires `requestAssets()` download.
- **Core ML MiniLM-L6 (384d)**, INT8 ≈ 22 MB model; third-party benchmark claims ~18 ms/query on
  A17 Pro at recall@10 ≈ 0.91. **UNVERIFIED** — single blog source (mvpfactory.io), not reproduced.
- **Vector stores:** ObjectBox Swift 4.0 (HNSW, on-device), sqliteai/sqlite-vector (SIMD, iOS).
  Note `sqlite-vec` via `LoadExtension` is a `dlopen`, **which iOS forbids** — it must be statically
  linked. Real integration friction.

**pgvector / Pinecone are the wrong answer regardless**: they are server-side, they turn a $0
architecture into a recurring bill, they add a network round trip to a core interaction, and they
break offline logging in a gym with no signal.

---

## 5. Hybrid (lexical first, embeddings to re-rank) — does the complexity pay?

Hybrid is genuinely the state of the art for general retrieval; RRF fusion of BM25 + dense reliably
beats either arm. But the published gains come from corpora with vocabulary mismatch, and the measured
evidence above says this corpus is not one of them:

- BM25 top-10 candidate recall is already **96.6%** (measured). Ceiling for any re-ranker: ~3.4 points.
- Re-ranking those candidates with a **free** fuzzy scorer (`token_set_ratio`) already gained
  +1.6 points top-1 (84.22% → 85.81%) at a cost of 0.2 ms and about 10 lines of Swift. **This is the
  hybrid worth having** — lexical retrieve, lexical re-rank, no model.
- On the no-match task, BM25 + abstention threshold alone reached the paper's embedding+LLM hybrid.

**The re-rank stage you should actually use is the vision model you are already paying for.** ZeroLog
already sends food photos to `gpt-6-luna`/`claude-haiku-5-5` at ~$0.07/user/month with ~15× headroom
(`references/ai-inference-costs.md`). Returning 10 BM25 candidates for the model to choose among is
the paper's own best-performing architecture (semantic top-K → LLM pick), with FTS5 substituted for
the embedding stage at zero marginal cost and zero new infrastructure.

---

## 6. Recommendation

**Build this:**

1. Bundle **Foundation + SR Legacy (+ FNDDS if portion data is wanted)** as a prebuilt SQLite file
   with an external-content **FTS5 BM25** index, `porter unicode61`. ~2–6 MB, sub-millisecond, $0,
   no server, works offline in a basement gym.
2. **Barcode scan → exact GTIN lookup** for packaged foods. Do not text-match branded items. If the
   branded table is wanted later it is a 45 MB FTS5 file or an on-demand API call by barcode.
3. **Abstention threshold on the BM25 score** — fit it on a labelled set. This was worth more than
   the entire lexical-vs-dense question (41.5% → 65.3% measured).
4. **Free fuzzy re-rank** of the top ~50 BM25 candidates (`token_set_ratio`). +1.6 points, 0.2 ms.
5. **Return top-10 candidates to the vision model** already in the pipeline, and show a
   confirm/disambiguate UI. Hard food matching tops out near 57% top-1 for every known method —
   design for user confirmation rather than pretending to be right.
6. A small hand-curated **synonym table** (~200 pairs: aubergine/eggplant, rocket/arugula,
   courgette/zucchini, mince/ground beef) via an FTS5 custom tokenizer. This buys the specific thing
   embeddings are actually good at, for a few hours of work and 0 MB.

**Do not build:** pgvector, Pinecone, or any hosted vector DB. Do not stand up a server for
retrieval. Do not embed 400k branded food names.

**The cheapest experiment that could change this answer:** when FTS5 is working, measure its top-10
recall on 200 real ZeroLog photo descriptions. If it is below ~90%, try `NLEmbedding.sentenceEmbedding`
— free, on-device, already on the phone — on the same 200 before anyone pays for anything. That
sequencing means a wrong guess costs an afternoon, not a monthly bill.

---

## Sources

- Lemay et al., J Nutr 2026 — https://pubmed.ncbi.nlm.nih.gov/42309308/ · data & published accuracy
  tables: https://github.com/dglemay/USDA-Food-Mapping
- FoodScribe (branded foods reduced accuracy; 13,590 descriptions indexed) —
  https://pmc.ncbi.nlm.nih.gov/articles/PMC13409120/
- BEIR, Thakur et al. — https://arxiv.org/abs/2104.08663
- Reproducible BEIR references (rare-term explanation) — https://arxiv.org/html/2306.07471
- Lexical vs semantic vector search — https://arxiv.org/html/2505.11582v2
- FoodData Central downloads (dataset sizes) — https://fdc.nal.usda.gov/download-datasets/
- FDC data type documentation — https://fdc.nal.usda.gov/data-documentation/
- SQLite FTS5 (trigram tokenizer, detail=, external content) — https://www.sqlite.org/fts5.html
- `NLEmbedding.sentenceEmbedding` — https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding(for:)
- `NLContextualEmbedding` — https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding
- ObjectBox Swift on-device vector search — https://docs.objectbox.io/on-device-vector-search
- sqlite-vector (iOS, SIMD) — https://github.com/sqliteai/sqlite-vector/
- sqlite-vec `dlopen` forbidden on iOS — https://shinylib.net/efcore/sqlite-vector/
- iOS size limits (200 MB cellular, 4 GB uncompressed) — https://developer.apple.com/help/app-store-connect/reference/app-uploads/on-demand-resources-size-limits/
- Corpus-scale tiers for choosing retrieval — https://www.vgtc.io/insights/search-by-corpus-scale
- Core ML MiniLM on-device latency/index figures (**UNVERIFIED**, single blog) —
  https://mvpfactory.io/blog/wiring-core-ml-s-neural-engine-to-a-quantized-on-device-embedding-model-for/

## Reproducing

Scripts and downloaded ground truth: `/opt/data/cache/scratch/foodmatch/`
(`bench2.py` ASA24 head-to-head, `bench3.py` scale + index arithmetic, `bench4.py` cross-validated
NHANES). Requires `rapidfuzz`, `scikit-learn`, `numpy`.

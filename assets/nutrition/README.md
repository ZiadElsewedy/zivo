# The bundled nutrition catalog

`foods.json` is ZIVO's source of truth for what a food is worth. It is a
**build artifact**, not a hand-maintained file — see
[`scripts/nutrition/build_food_db.js`](../../scripts/nutrition/build_food_db.js).

## Why it's checked in

The app must resolve nutrition offline, identically for every user, identically
between the device and the server, and stably enough that a test can assert
exact values. A network lookup is none of those. It ships in the app bundle and
is parsed lazily on first use.

## Where the data comes from

USDA **FoodData Central** (US government, public domain) —
<https://fdc.nal.usda.gov>:

| Dataset | Role |
|---|---|
| Foundation Foods | small, deeply analysed core set — wins on collision |
| SR Legacy | the broad staple reference set |

Every row carries the real `fdcId` it came from (`sourceRef`), so any number on
screen can be traced back to a specific USDA record. **Nothing in this file was
written by hand or produced by a model** — that is the whole point (see
[`docs/DIET_COACH_AUDIT.md`](../../docs/DIET_COACH_AUDIT.md), T1/T2).

## Format

Positional tuple rows described by the file's own `fields` array, because
repeating ten key names across 7,000+ rows costs about a third of the file for
no information. All values are **per 100 g**; `portions` are
`[label, gramsPerOne]` pairs taken from the source record for that food.

## Rebuilding

1. Download both exports from <https://fdc.nal.usda.gov/download-datasets>
   (Foundation Foods JSON, SR Legacy JSON) and unzip them.
2. Run:

```bash
node --max-old-space-size=6144 scripts/nutrition/build_food_db.js \
  --foundation <FoodData_Central_foundation_food_json_*.json> \
  --sr-legacy  <FoodData_Central_sr_legacy_food_json_*.json> \
  --out assets/nutrition/foods.json
```

It writes **two** copies — this one and `functions/nutrition/foods.json` — plus
`foods.sha256`. Both suites assert the two are byte-identical: the app and the
coach quoting different calories for the same food is exactly the bug this
whole design exists to prevent.

3. Regenerate the shared golden vectors, or both test suites will fail against
   a stale fixture (which is the intended behaviour):

```bash
node scripts/nutrition/build_vectors.js
```

## Known limits

- **Coverage is US-shaped.** Regional and home cooking are poorly represented,
  so `FoodNotFound` is a common, expected outcome. Answering it honestly — and
  offering the user their own food — is correct; substituting something close
  is not.
- **SR Legacy is a 2018 snapshot** and contains some branded products whose
  recipes have since changed. They are still real sourced records, and search
  ranking prefers the plainer generic entries.
- **Preparation matters.** Raw and cooked forms are separate rows (raw rice is
  365 kcal/100 g; cooked is 130), and a query that matches both resolves to
  `FoodAmbiguous` rather than picking one.

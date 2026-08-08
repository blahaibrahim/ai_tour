# Differential parity harness

Runs the same corpus through the Flask server's pure functions and this port's,
and diffs the two JSON documents. It exists because the risky differences
between the two implementations are the *silent* ones — a Unicode class that
JavaScript reads more narrowly than Python, a rounding mode, a
`capitalize()` that lowercases the tail in one language and not the other.
None of those raise. They just quietly resolve a worse photo.

## Running it

From the repo root, on Windows (adjust the interpreter path elsewhere):

```sh
cd backend/server       && ./venv/Scripts/python.exe ../server-node/parity/dumpPython.py /tmp/py.json
cd ../server-node       && npx tsx parity/dumpTypescript.ts > /tmp/ts.json
python parity/diff.py /tmp/py.json /tmp/ts.json
```

`diff.py` exits non-zero and prints every mismatching path if the two disagree.

Note the Python side writes to a file argument rather than stdout: a Windows
console in cp1252 cannot encode the Arabic fixtures, and `print` dies on them.

## What it covers

Pure functions only — no network, no Supabase, so it is fast and deterministic.

| Section | Cases |
|---|---|
| `normalize`, `photos_normalize` | 36 strings (Latin, accented, Arabic, Cyrillic, fullwidth digits, punctuation) through both folds |
| `is_real_name` | the same 36 strings |
| `clean` | tag-value display casing |
| `category`, `excluded`, `name_variants` | 47 real tag sets |
| `score` | 17 names × 20 tag sets = 340 scores, each with its full breakdown |
| `score_pageviews` | the log-scaled pageview curve at 7 magnitudes |
| `compose` | 47 tag sets × 3 heritage statuses = 141 generated blurbs |
| `photo_tokens`, `photo_matches`, `tag_dump`, `photos_name_variants` | the 10 measured false-positive cases from `photos.ts`'s docstring |
| `tiles` | tile ids, bounds and coverings at 5 latitudes including the equator and the southern hemisphere |
| `haversine` | 5 distances, to 9 decimal places |

Last run: **identical across all 16 sections**.

The prompt-ranking sections that used to be here went with `routes/itinerary.py`'s
replacement — those rules belonged to the removed LLM candidate-ranking path and
have no counterpart in the Route Generation module. Everything left is the POI
ingestion pipeline, which the new design still depends on as its `api_seeded`
source.

## Adding cases

Add to both files, keeping the two corpora identical — a case present in only
one of them proves nothing and will show up as a length mismatch rather than a
behavioural difference. When a rule changes on one side only, that is exactly
what this is meant to catch.

## Deleting it

Once the Python server is retired, this goes with it. `src/testPoiRules.ts` is
the part that stays: it pins the rules against themselves rather than against
another implementation.

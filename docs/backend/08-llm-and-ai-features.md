# 08 — LLM & AI Features

## What's currently faked

| Feature | Where | Today |
| --- | --- | --- |
| Itinerary generation | `GenerateRouteEvent` → `app_bloc.dart:105` | Region filter over 8 hardcoded locations. Target: maps API fetch → deterministic scoring → LLM selection, see [12](12-poi-sources-and-ingestion.md) |
| "Ask about this place" | `AskQuestionEvent` (`app_event.dart:107`) | Caller passes both question *and* answer |
| "Modify my route" | `SendAIChangeEvent` (`app_event.dart:139`) | Canned response |
| Task generation | `RegenerateTaskEvent` | Cycles a fixed list |
| Thinking screen | `AppState.thinkingMessages` | Six hardcoded strings on a timer |

The thinking screen deserves a note: it's currently theatre over a synchronous
filter. Once a real model is behind it the delay becomes genuine, and the
existing copy ("Cross-referencing Constantine's bridges…") is well judged for
it. Keep it — just make the stages report actual progress.

## Architecture

Identical to the 3D endpoint, for the same reason: **the key never ships**.

```
App ──► Supabase Edge Function ──► LLM provider
        (JWT, rate limit, key)
```

One function, `ai-chat`, with a `mode` parameter (`itinerary` | `place` |
`modify` | `task`), rather than four near-identical functions.

`mode: itinerary` is the one exception to "just call the LLM": it first calls
`nearby_locations` (which itself may trigger `ingest-pois` on a cold tile, see
[12](12-poi-sources-and-ingestion.md)) to build the candidate set, *then*
calls the model. The other three modes go straight to the provider.

Streaming is worth the effort for the chat surfaces. Edge Functions can return
a `ReadableStream`; the app renders tokens as they arrive. A response that
starts in 300 ms feels faster than one that completes in 2 s. Itinerary
generation can't stream the candidate-fetch step, but it can stream the
model's response once candidates are in hand — pair that with the thinking
screen's staged copy so "Reading your radius…" corresponds to the real fetch,
not a fake delay.

---

## Free LLM providers

All of these have genuinely usable free tiers as of writing. **Verify current
limits before you depend on one** — these change often.

| Provider | Models | Free tier | Best for |
| --- | --- | --- | --- |
| **Google AI Studio** | Gemini 2.0 / 2.5 Flash | Generous RPM/RPD limits, no card | **Primary pick.** Fast, long context, native vision, strong Arabic and French |
| **Groq** | Llama 3.3 70B, Llama 4 Scout/Maverick | Solid daily limits | **Speed pick.** Extremely fast inference — ideal for streaming chat |
| **Cerebras** | Llama 3.3 70B, Qwen | Daily token allowance | Fastest tokens/sec available; smaller model choice |
| **OpenRouter** | `:free` variants of DeepSeek, Llama, Qwen | Rate-limited free routes | Fallback and A/B comparison across many models behind one API |
| **Mistral** | Mistral Small / Nemo | Free experimentation tier | Excellent French — relevant for Algeria |
| **Together AI** | Various open models | Trial credits + some free models | Fallback |
| **Cloudflare Workers AI** | Llama, Mistral | Daily neuron allowance | Fallback; nice if you ever move edge compute there |

### Recommendation

**Gemini Flash primary, Groq fallback.** Gemini for quality, long context, and
because its vision capability lets one provider also handle image
understanding. Groq for latency-sensitive chat and as the failover when Gemini
rate-limits.

Write the client as an interface with two implementations and a
`Retry-After`-aware failover. One provider's free tier is a single point of
failure; two is resilient at no extra cost.

```typescript
const providers = [geminiFlash, groqLlama];
for (const p of providers) {
  try { return await p.complete(messages); }
  catch (e) { if (!isRateLimit(e) && !isServerError(e)) throw e; }
}
throw new Error('all_providers_unavailable');
```

### Self-hosting

You already run Modal with GPU experience, so this is a real option: **vLLM
serving Qwen 2.5 7B / 14B Instruct or Llama 3.1 8B** on an A10G or L4. Only
worth it if free tiers become limiting — inference has a real per-hour cost,
whereas the free tiers are free. Keep it as the escape hatch, not the plan.

---

## Feature 1 — Itinerary generation

**This is a four-stage pipeline, and the LLM owns exactly one of the four
stages.** Full detail on stages 1–2 is in
[12](12-poi-sources-and-ingestion.md); this section covers stage 3, where this
document's concerns — prompting, schemas, cost — actually apply.

```
1. Maps API   Overpass/Geoapify → raw tourism POIs near the user     (12)
2. Score      Deterministic ranking — is this worth visiting at all? (12)
3. LLM        Given the top-scored candidates + user prompt + dates
              → a selected, reasoned subset                          (here)
4. Geometry   Route ordering — never the model's job                 (below)
```

**The most important design decision in this document: the LLM must not invent
places, and it must not be asked to judge quality from nothing.** A tourist
sent to a monument that doesn't exist is a product failure and a safety
problem — that's what step 1's grounding in a real maps provider prevents. A
tourist sent to a technically-real but uninteresting POI (a parking lot with a
`tourism` tag) is a quieter failure — that's what step 2's scoring prevents by
never presenting it as a candidate. The model's job is narrower than either:
**given a set that's already been vetted for existing and for being worth a
visit, pick the subset that fits this traveller's prompt.**

```sql
select * from public.nearby_locations(
  p_lat => :lat, p_lng => :lng, p_radius_km => :radius,
  p_categories => :categories, p_min_score => 25, p_limit => 50
);
```

That's the candidate set — up to 50 rows, each already carrying
`interest_score`, `heritage_status`, and a real blurb. Nothing reaches the
model that hasn't cleared the quality floor.

Constrain the output with a JSON schema (Gemini's structured output /
`response_mime_type: application/json`) and then *still* validate the ids
server-side against that exact candidate set. Structured output makes
malformed responses rare, not impossible.

```typescript
const schema = {
  type: "object",
  properties: {
    stops: {
      type: "array",
      items: {
        type: "object",
        properties: {
          location_id: { type: "string" },
          reason: { type: "string", description: "One sentence, addressed to the traveller" },
          suggested_order: { type: "integer" },
        },
        required: ["location_id", "reason", "suggested_order"],
      },
    },
  },
  required: ["stops"],
};
```

The `reason` field is a genuine product upgrade over what the swipe cards show
today — "Because you asked for quiet places away from crowds" beats a generic
blurb, and it costs nothing extra.

Prompt sketch:

```
You are planning a walking tour in Algeria.

Traveller's request: "{prompt}"
Dates: {start} to {end} ({n} days)
They want about {wanted_visits} stops.

Choose ONLY from these locations. Never invent a location.
Every one of them has already been verified to exist and to be worth
visiting — your job is fit to the traveller's request, not quality.
A high interest_score is a weak default preference, not a requirement:
"somewhere quiet, away from crowds" should favour a lower-traffic pick
over the single highest-scored option.

{candidates as id | name | category | distance_km | heritage_status | interest_score | blurb}

Order them to minimise backtracking. Prefer variety of category.
Reply with JSON matching the schema.
```

That instruction about `interest_score` matters: without it, the model
defaults to picking the highest-scored candidates every time, which turns
"pick what fits my prompt" back into "pick what's most famous" — exactly the
generic-itinerary failure mode the scoring stage was supposed to let the model
avoid, not reproduce.

### Route ordering

Don't ask the LLM for optimal travel order — it's bad at geometry and you have
real coordinates. Solve it properly:

- ≤ 10 stops: brute-force or nearest-neighbour + 2-opt in Dart, milliseconds
- More: **OSRM**, **Valhalla**, **OpenRouteService**, or **GraphHopper** — see
  the routing options in [12](12-poi-sources-and-ingestion.md#routing).

Let the model choose *which* places and *why*; let geometry choose the order.

### Cost note

Because stage 2 already did the hard filtering, the LLM call here is cheap and
low-stakes: 50 short candidate rows in, a small JSON object out. The expensive
part of itinerary generation is the maps ingestion and enrichment in
[12](12-poi-sources-and-ingestion.md), which is amortized across every user
who ever queries that tile — not the LLM call, which is per-request. Don't
over-invest in LLM cost controls here at the expense of the tile cache; the
tile cache is where the real savings are.

---

## Feature 2 — Place chat

`AskQuestionEvent` currently takes the answer as a parameter — the UI is
passing in a canned reply. The real version sends the question plus grounding
context.

```
System: You are a knowledgeable guide to Algerian heritage. Answer in {locale}.
        Be concise — 2–4 sentences. If you are unsure, say so.
        Never invent opening hours, ticket prices, or transport details.

Context: {location name, region, category, blurb, current task}
History: last 6 messages
User: {question}
```

That last system instruction matters. Hallucinated opening hours are the single
most likely way this feature strands a user at a closed gate.

Persist to `chat_messages` ([02](02-cloud-database-schema.md)) and cache
aggressively — the same questions recur across users. A normalized-question
hash → answer cache with a 30-day TTL will absorb a large fraction of traffic
for free.

---

## Feature 3 — Task generation

`RegenerateTaskEvent` with `taskRegenerationsLeft` (3) is already a good
mechanic. Real generation makes tasks specific to the place:

```
Generate one photo/video/scan challenge for {location}.
It must be doable in under 10 minutes, on foot, with a phone.
Type must be one of: mascot, video, scan, photo.
Do not suggest entering restricted areas, climbing, or trespassing.
Reply as JSON: { "type": ..., "label": ..., "points": 20-50 }
```

The safety line is not boilerplate. A model asked for "creative photo
challenges" at a gorge bridge (Sidi M'Cid, 175 m above the Rhumel) will
cheerfully suggest something dangerous. Constrain it, and validate `type`
against the enum before persisting.

Cache generated tasks per location — they're reusable across users, which turns
3 regenerations per user into near-zero marginal cost.

---

## Feature 4 — Semantic search (optional, high value)

The prompt bar (`lib/screens/result/widgets/ai_prompt_bar.dart`) invites
free-text intent like "somewhere quiet with old architecture". Keyword matching
can't serve that; embeddings can.

This slots in as a **third ranking signal alongside distance and
`interest_score`**, not a replacement for either. `nearby_locations` already
caps candidates at `p_limit` (default 50); the itinerary LLM call in Feature 1
handles up to that many rows comfortably. Semantic ranking earns its keep once
a popular tile has hundreds of scored POIs and you need to cut that down to 50
*before* it reaches the LLM — cosine similarity against the prompt is a much
better pre-filter than "top 50 by score", which would silently exclude
anything niche the user actually asked for.

```sql
alter table public.locations add column embedding vector(384);
create index on public.locations using hnsw (embedding vector_cosine_ops);
```

Free embedding models:

| Model | Dims | Notes |
| --- | --- | --- |
| `intfloat/multilingual-e5-small` | 384 | **Pick this** — handles English, French, and Arabic in one space |
| `BAAI/bge-m3` | 1024 | Stronger multilingual, heavier |
| `sentence-transformers/all-MiniLM-L6-v2` | 384 | English only — insufficient here |
| Gemini `text-embedding-004` | 768 | API-based, free tier, no hosting |

Multilingual matters: a French-speaking user typing "vieille ville tranquille"
must match an English blurb. A monolingual model fails that silently.

Embed each location **once, at ingestion time** — as the last step of the
per-tile pipeline in [12](12-poi-sources-and-ingestion.md), right after
scoring, using the English blurb (translate-then-embed, or use a multilingual
model on the source text directly). Never embed at request time; it's slow and
you'd pay for it on every search instead of once per place. Then filter by
radius in PostGIS, blend `interest_score` and cosine similarity into a single
ranking, and cap at `p_limit` before the LLM ever sees the set. Hybrid
retrieval — geography narrows, score and semantics together rank — is the
right shape.

---

## Feature 5 — Translation of content

Details in [09](09-internationalization.md). Options:

- **LLM translation** with Gemini/Groq — best quality for the flowing prose in
  `blurb`, understands proper nouns like "Maqam Echahid" and leaves them alone.
- **NLLB-200** (Meta, free, self-hostable) — supports Modern Standard Arabic
  and hundreds of other languages. Good if you need bulk offline translation.

For 8 locations, translate once with an LLM, have a human review the Arabic and
French, and commit the results as seed data. Don't translate at request time —
it's slow, non-deterministic, and you'd pay for it repeatedly.

---

## Supporting models

| Need | Model | Notes |
| --- | --- | --- |
| NSFW screening | `Falconsai/nsfw_image_detection` | Tiny ViT, runs alongside the 3D pipeline. See [07](07-securing-the-3d-endpoint.md) |
| Face detection | MediaPipe Face Detection | On-device, free, fast |
| Background removal | BiRefNet > `isnet-general-use` > `u2net` | Upgrade from the current `u2net` — better matting means a better mesh |
| Speech to text | `faster-whisper` (self-host) or Groq's Whisper endpoint | Voice prompt entry; Groq's is free and very fast |
| Image captioning | Gemini Flash vision | Auto-title artifacts: "Carved wooden door, Casbah" instead of "Your capture" |
| OCR | `PaddleOCR` or Gemini vision | Reading inscriptions — pairs naturally with the existing "scan" task type |

The captioning one is a small, high-return addition: `app_bloc.dart:388`
currently names captures `'Your capture'` when there's no active stop. One
vision call gives every artifact a real title.

---

## Cost control

Everything the 3D endpoint needs, at lower stakes:

- All calls via Edge Functions; keys in Supabase secrets, never in `lib/`
- Per-user rate limits reusing `check_rate_limit` from
  [07](07-securing-the-3d-endpoint.md)
- Log `tokens_in` / `tokens_out` to `chat_messages` — the columns exist
- Cap `max_tokens` per mode (place chat: 300; itinerary: 1500)
- Trim history to the last 6 messages, not the whole thread
- Cache by normalized-prompt hash

## Prompt injection

User text reaches the model in every feature here. A blurb or a question
containing "ignore previous instructions and…" is a real input.

- Keep system instructions and user content in separate message roles; never
  concatenate them into one string.
- Treat model output as data. The id validation in step 3 of itinerary
  generation is exactly this principle — the model cannot name a location
  outside the candidate set no matter what the user wrote.
- Never let model output reach SQL, a shell, or a URL fetch without validation.
- Cap user input length before it's embedded in a prompt.

The blast radius here is small because the model's output only ever selects
from server-supplied ids and renders as text. Preserve that property as
features grow.

## Testing checklist

- [ ] LLM returns a location id not in the candidate set → dropped, not shown
- [ ] LLM never receives a candidate below the score floor (verify the query, not just the prompt)
- [ ] A low-`interest_score` candidate that matches the prompt semantically can still be selected — the model isn't just picking the top-scored rows
- [ ] Provider returns 429 → failover to the second provider, user sees no error
- [ ] Both providers down → graceful "suggestions unavailable", app still usable with the plain radius query
- [ ] Maps/POI provider down and tile cache cold → falls back to curated locations only (see 12)
- [ ] Prompt containing injection text → system instructions hold, no invented places
- [ ] Arabic prompt → Arabic response, correct RTL rendering
- [ ] Generated task validates against the `task_type` enum
- [ ] Token counts land in `chat_messages`
- [ ] Repeated identical question → served from cache, no provider call

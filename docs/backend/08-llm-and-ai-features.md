# 08 — LLM & AI Features

## What's currently faked

| Feature | Where | Today |
| --- | --- | --- |
| Itinerary generation | `GenerateRouteEvent` → `app_bloc.dart:105` | Region filter over 8 hardcoded locations |
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

Streaming is worth the effort for the chat surfaces. Edge Functions can return
a `ReadableStream`; the app renders tokens as they arrive. A response that
starts in 300 ms feels faster than one that completes in 2 s.

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

**The most important design decision in this document: the LLM must not invent
places.** A tourist sent to a monument that doesn't exist is a product failure
and a safety problem. The database is the source of truth; the model only
selects and orders.

```
1. Postgres:  nearby_locations(lat, lng, radius, regions)  → 40 candidates
2. LLM:       given candidates + user prompt + dates       → ranked subset with reasons
3. Validate:  every returned id ∈ candidate set            → drop anything else
4. Postgres:  hydrate full rows, compute route order
```

Step 3 is not optional. Constrain the output with a JSON schema (Gemini's
structured output / `response_mime_type: application/json`) and then *still*
validate the ids server-side. Structured output makes malformed responses rare,
not impossible.

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
{candidates as id | name | category | region | distance_km | blurb}

Order them to minimise backtracking. Prefer variety of category.
Reply with JSON matching the schema.
```

### Route ordering

Don't ask the LLM for optimal travel order — it's bad at geometry and you have
real coordinates. Solve it properly:

- ≤ 10 stops: brute-force or nearest-neighbour + 2-opt in Dart, milliseconds
- More: **OSRM** (free public demo server, or self-hosted) for the real road
  matrix, or **Valhalla**. Both are open source and free.

Let the model choose *which* places and *why*; let geometry choose the order.

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

Embed once at seed time (8 locations — do it in a migration), then filter by
radius in PostGIS and rank by cosine similarity. Hybrid retrieval — geography
narrows, semantics ranks — is the right shape.

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
- [ ] Provider returns 429 → failover to the second provider, user sees no error
- [ ] Both providers down → graceful "suggestions unavailable", app still usable with the plain radius query
- [ ] Prompt containing injection text → system instructions hold, no invented places
- [ ] Arabic prompt → Arabic response, correct RTL rendering
- [ ] Generated task validates against the `task_type` enum
- [ ] Token counts land in `chat_messages`
- [ ] Repeated identical question → served from cache, no provider call

# 04 — Sync & Caching

> **Status: Not started.** No outbox, no sync engine, no Flutter changes.
> Everything below is still plan.

## The contract

> A user action commits locally and is reflected in the UI immediately. The
> network is a background concern that never blocks a tap.

Everything below follows from that sentence.

## Two directions, different mechanics

**Pull** (server → device) is a cheap incremental refresh of read-mostly data.
**Push** (device → server) is an ordered, retried, idempotent queue. They fail
differently and are built separately.

```
         ┌──────────────┐
 tap ───►│   AppBloc    │
         └──────┬───────┘
                ▼
         ┌──────────────┐   write + enqueue in ONE transaction
         │  Repository  │──────────────────────────┐
         └──────┬───────┘                          │
                ▼                                  ▼
         ┌──────────────┐                   ┌─────────────┐
         │  Drift DB    │◄──────────────────│   Outbox    │
         └──────┬───────┘   ack: mark synced└──────┬──────┘
                │                                  │
        watch() │                                  │ when online
                ▼                                  ▼
              UI                            Supabase
                ▲                                  │
                └──────── pull / realtime ─────────┘
```

## Push: the outbox

### Local write and enqueue must share a transaction

```dart
Future<void> toggleSaved(String locationId) => _db.transaction(() async {
  final existing = await _db.savedLocations.getById(locationId);
  if (existing == null) {
    await _db.savedLocations.insert(locationId, syncState: SyncState.pendingCreate);
    await _db.outbox.enqueue('saved_locations', locationId, 'insert', {...});
  } else {
    await _db.savedLocations.markDeleted(locationId);
    await _db.outbox.enqueue('saved_locations', locationId, 'delete', {...});
  }
});
```

If these are two transactions and the process dies between them, you get a
local change that never syncs, or a queued change that isn't in the data.
Both are silent corruption. One transaction, always.

### Processing

```dart
Future<void> drain() async {
  if (_running || !await _connectivity.isOnline) return;
  _running = true;
  try {
    while (true) {
      final batch = await _db.outbox.dueEntries(limit: 20);
      if (batch.isEmpty) break;
      for (final entry in batch) {
        try {
          await _apply(entry);
          await _db.markSynced(entry);
        } on PostgrestException catch (e) {
          await _handleFailure(entry, e);
          if (_isPermanent(e)) continue; else return;  // stop on transient
        }
      }
    }
  } finally { _running = false; }
}
```

Rules:

- **Ordered per entity.** Entries for the same `(entityTable, entityId)` must
  apply in insertion order — a create followed by an update, applied backwards,
  fails or resurrects stale data. Process by ascending `id` and skip an entity
  whose earlier entry is still pending.
- **Transient vs. permanent.** Network error, 5xx, 429 → back off and retry.
  409 conflict, 403 RLS denial, 400 validation → this will never succeed;
  mark it `conflict`, stop retrying, surface it. An outbox that retries a
  permanently-failing entry forever blocks every entry behind it.
- **Exponential backoff with jitter**: `min(2^attempts, 300) seconds ± 20%`.
  The jitter matters — without it, every device that lost connectivity in the
  same tunnel retries in lockstep.
- **Cap attempts** at ~10, then mark `conflict` and let the user retry
  manually.

### Triggers for a drain

`connectivity_plus` regaining a connection · app resume
(`AppLifecycleState.resumed`) · after any local write · a periodic timer while
foregrounded (60 s) · optionally `workmanager` for background flush.

Do not drain on a tight timer while offline. It burns battery for nothing.

### Idempotency

Every push must be safe to apply twice, because "request succeeded but the ack
was lost" is indistinguishable from "request failed".

- Inserts carry the client-generated id → `on conflict (user_id, local_id) do nothing`
- Updates are full-row upserts keyed by id, not deltas
- Deletes are soft (`deleted_at`), so a repeat is a no-op

## Pull

### Incremental by cursor

```sql
select * from public.trips
where user_id = auth.uid()
  and updated_at > :cursor
order by updated_at
limit 200;
```

Store `max(updated_at)` in `sync_state.cursor`. Use the *server's* returned
timestamp, never the device clock — phone clocks are wrong, sometimes by
years, and a skewed cursor silently skips rows.

Clock skew has one nasty edge: rows written in the same millisecond as the
cursor get skipped. Use `>=` with a `(updated_at, id)` keyset, or accept the
tiny overlap of `>=` and let idempotent upsert absorb the duplicates. The
second is simpler and adequate here.

### Catalogue refresh

This section originally assumed the catalogue was the 8 hand-written
locations — small, whole-table, rarely changing, fetchable with one ETag
check. **That no longer holds.** Locations now come from live POI ingestion
scoped to wherever the user's map viewport happens to be
([12](12-poi-sources-and-ingestion.md)), so there is no single "catalogue
version" to poll — the dataset is unbounded and only ever partially relevant
to any one device.

Pull model instead: **fetch by viewport, not by whole-table version.**

```dart
Future<void> ensureLocationsLoaded(LatLng center, double radiusKm) async {
  if (await _local.hasFetchedArea(center, radiusKm)) return;   // FetchedAreas, see 03

  final rows = await supabase.rpc('nearby_locations', params: {
    'p_lat': center.latitude, 'p_lng': center.longitude,
    'p_radius_km': radiusKm, 'p_locale': locale.languageCode,
  });
  await _local.upsertLocations(rows);
  await _local.recordFetchedArea(center, radiusKm, ttl: const Duration(days: 60));
}
```

This is a straight upsert-on-read, not an outbox item — `locations` is
server-authoritative and read-only to the client (RLS grants `select` only, see
[02](02-cloud-database-schema.md)), so there's no push direction to reconcile.
`FetchedAreas` ([03](03-local-database-schema.md)) is purely a local
optimization to avoid re-issuing the same RPC as the user pans a few hundred
metres.

Two things follow from moving to a viewport model:

- **The "thinking screen" delay becomes honest.** Route generation now
  genuinely waits on `nearby_locations`, which may itself trigger the server's
  tile ingestion on a cold area ([12](12-poi-sources-and-ingestion.md)). Surface
  real stages here rather than the old fixed-timer animation.
- **Re-visiting a warm area is instant and free.** `FetchedAreas` with a ~60-day
  TTL means a user who opens the app in the same city twice in a season makes
  zero location network calls the second time — the local cache already has
  every row the RPC would return.

The curated fallback (`isCurated = true`) rows are the one exception: those 8
are worth having everywhere regardless of viewport, so pull them in full on
first launch, independent of `FetchedAreas`.

### Realtime — where it's worth it

Supabase Realtime is right for one thing in this app: **`model_jobs` status**.
The user is staring at a spinner waiting for a 3D model; polling is wasteful
and laggy.

```dart
supabase.channel('jobs:$userId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public', table: 'model_jobs',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
    callback: (payload) => _onJobUpdate(payload.newRecord),
  ).subscribe();
```

**Realtime respects RLS only if you enable it.** Turn on the private-channel /
RLS-authorized setting for the publication; otherwise a subscriber can receive
rows they cannot select. Verify this explicitly — it's a common leak.

Do not put trips, stops, or saved locations on realtime. Single-device users
gain nothing and you pay a persistent socket for it. Add it if and when
multi-device editing becomes real.

## Conflict resolution

Per-table, chosen deliberately:

| Table | Strategy | Why |
| --- | --- | --- |
| `saved_locations` | Add-wins, delete by tombstone | A set; union is almost always what the user meant |
| `trip_stops.task_state` | Monotonic — `done` beats `pending`, never reverts | Completing a task can't be undone by a stale device |
| `trips.current_stop_idx` | Highest wins | Progress only moves forward |
| `trips` (other fields) | Last-write-wins on `updated_at` | Rare, low stakes |
| `artifacts` | Immutable after create; only `deleted_at` mutates | No conflict surface by construction |
| `profiles.total_points` | Server authoritative, computed by trigger | Never trust a client score |
| `chat_messages` | Append-only, id-deduped | No conflict surface |

Making `artifacts` immutable is a deliberate simplification. A capture never
changes; edits create a new row. That removes an entire class of merge
problems from the most-written table.

Where last-write-wins can lose data, keep the loser: write the discarded
version to a `conflicts` table so it's recoverable. You will want this the
first time a user complains.

## Caching tiers

| Tier | Contents | Store | Invalidation |
| --- | --- | --- | --- |
| Memory | Current queue, active trip, decoded thumbnails | Bloc state, `ImageCache` | Process death |
| Database | POI cache (by viewport), user data, chat history | Drift | `FetchedAreas` TTL (POI) / cursor (user data) |
| Files | Capture JPEGs, downloaded `.glb`, map tiles | App documents + cache dir | LRU with size budget |
| Signed URLs | Storage access tokens | Memory map, TTL-aware | Refresh at 80% of TTL |

### File cache with a budget

`media_cache` in [03](03-local-database-schema.md) drives an LRU:

```dart
const budget = 500 * 1024 * 1024;  // 500 MB

Future<void> evictIfNeeded() async {
  var total = await _db.mediaCache.totalBytes();
  if (total <= budget) return;
  final candidates = await _db.mediaCache.lruUnpinned();
  for (final c in candidates) {
    await File(c.localPath).delete();
    await _db.mediaCache.remove(c.remoteKey);
    total -= c.sizeBytes;
    if (total <= budget * 0.8) break;   // evict to 80%, not to the line
  }
}
```

`isPinned` protects what must never be evicted: **the user's own captures that
haven't been uploaded yet**. Evicting those destroys data that exists nowhere
else. Pin on create, unpin only after the upload is acknowledged.

Evicting to 80% rather than exactly to the budget stops the thrash where every
subsequent write triggers another eviction pass.

### Placement matters

- `getApplicationDocumentsDirectory()` — user data, backed up by iCloud/Google,
  **not** reclaimable by the OS. Un-uploaded captures go here (as they already
  do at `ar_hunt_screen.dart:596`).
- `getApplicationCacheDirectory()` — re-downloadable content. The OS may delete
  it under storage pressure, which is correct for downloaded `.glb` files and
  map tiles.

Putting cache in documents inflates the user's iCloud backup with regenerable
data and gets complaints. Putting user data in cache loses it.

### Signed URL cache

Signed URLs from Supabase Storage expire. Cache the URL with its expiry and
re-sign at 80% of TTL:

```dart
final cached = _urlCache[key];
if (cached != null && cached.expiresAt.isAfter(DateTime.now().add(_margin))) {
  return cached.url;
}
```

Never persist a signed URL to the database. That's the bug the `image_path` /
`photoUrl` split in [02](02-cloud-database-schema.md) exists to prevent.

### Image loading

`lib/widgets/net_image.dart` currently returns a bare `NetworkImage`, which has
only Flutter's in-memory cache — every cold start re-downloads. Move to
`cached_network_image` (disk-backed) or route through the `media_cache` table
so images share the LRU budget with `.glb` files. The second is more work but
gives you one number to reason about for total app storage.

## Sync status in the UI

Users tolerate slow sync. They don't tolerate not knowing whether their work is
safe. Expose a small indicator: synced / pending *n* / offline / failed. The
existing settings screen (`lib/screens/settings/settings_screen.dart`) is a
reasonable home for the detail view, with a subtle badge in the shell.

Make "retry failed items" a visible button. When sync is permanently stuck,
the alternative is a support ticket.

## Testing checklist

- [ ] Kill the app mid-write → no row exists without its outbox entry, and vice versa
- [ ] Queue 50 changes offline → all apply in order on reconnect, none duplicated
- [ ] Force a 403 on one entry → it is marked `conflict` and the queue behind it still drains
- [ ] Two devices complete the same task → `done` survives, no revert to `pending`
- [ ] Fill the file cache past budget → un-uploaded captures are never evicted
- [ ] Expired signed URL → transparently re-signed, no broken image
- [ ] Device clock set a year forward → sync does not skip rows
- [ ] Realtime subscription as user A receives no rows belonging to user B
- [ ] Panning inside a previously-fetched viewport issues zero `nearby_locations` calls
- [ ] Panning to a new area beyond the `FetchedAreas` TTL re-fetches correctly
- [ ] Curated fallback locations load on first launch with no network

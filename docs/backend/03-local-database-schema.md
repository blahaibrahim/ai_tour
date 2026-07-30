# 03 — Local Database Schema (Drift / SQLite)

## Why a real local database

The app is used at Djemila, at Timgad, on the Tassili plateau. Those are
exactly the places with no signal, and they're the places where the user is
completing tasks and capturing artifacts. A tour app that needs connectivity
to show the itinerary you already downloaded is broken at the moment it
matters most.

`SharedPreferences` cannot carry this. It has no queries, no transactions, and
serializing 27 fields of `AppState` into one JSON blob means a corrupted write
loses everything.

## Package choice

**Drift** (`drift` + `sqlite3_flutter_libs`). Reasons specific to this
project:

- Compile-time-checked SQL. The team already writes explicit, typed code —
  `copyWith` with a sentinel for nullables (`app_state.dart:186`) is not the
  work of people who want a loosely typed store.
- Watchable queries return `Stream`s, which drop straight into `flutter_bloc`
  via `emit.forEach`.
- Real migrations with a schema version, which you will need.

Alternatives considered: **Isar** (fast, but its maintenance status has been
uncertain — risky for a dependency this central), **Hive** (no queries, wrong
tool for relational data), **sqflite** (works, but you hand-write everything
Drift generates).

```yaml
dependencies:
  drift: ^2.20.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.6      # already present
dev_dependencies:
  drift_dev: ^2.20.0
  build_runner: ^2.4.13
```

## What lives locally, and why

Three categories with different rules:

| Category | Tables | Authority | Eviction |
| --- | --- | --- | --- |
| **Cached catalogue** | locations, regions, tasks, translations | Server | Refresh on ETag change; never evict fully |
| **Owned user data** | trips, stops, saved, artifacts, prefs | Local first, pushed up | Only on sign-out |
| **Sync machinery** | outbox, sync_state, media_cache | Local only | Rows die when acknowledged |

"Local first" for the middle category is the important claim: a write is
committed locally, the UI updates immediately, and the network push happens
later. The user never waits on a round trip to see their own tap take effect.

## Schema

```dart
// lib/data/local/tables.dart

// ---------- Catalogue (cached) ----------

class Regions extends Table {
  TextColumn get id => text()();
  IntColumn  get sortOrder => integer().withDefault(const Constant(0))();
  @override Set<Column> get primaryKey => {id};
}

class Locations extends Table {
  TextColumn   get id => text()();
  TextColumn   get regionId => text().references(Regions, #id)();
  TextColumn   get category => text()();
  RealColumn   get lat => real()();
  RealColumn   get lng => real()();
  TextColumn   get photoUrl => text().nullable()();
  BoolColumn   get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class LocationTranslations extends Table {
  TextColumn get locationId => text().references(Locations, #id)();
  TextColumn get locale => text()();
  TextColumn get name => text()();
  TextColumn get blurb => text()();
  @override Set<Column> get primaryKey => {locationId, locale};
}

class LocationTasks extends Table {
  TextColumn get id => text()();
  TextColumn get locationId => text().references(Locations, #id)();
  TextColumn get type => text()();          // task_type enum
  IntColumn  get points => integer().withDefault(const Constant(30))();
  @override Set<Column> get primaryKey => {id};
}

// ---------- User-owned (local first) ----------

class Trips extends Table {
  TextColumn     get id => text()();                 // uuid, generated locally
  TextColumn     get userId => text()();
  TextColumn     get title => text().nullable()();
  TextColumn     get prompt => text().nullable()();
  RealColumn     get centerLat => real().nullable()();
  RealColumn     get centerLng => real().nullable()();
  RealColumn     get radiusKm => real().withDefault(const Constant(5))();
  IntColumn      get wantedVisits => integer().nullable()();
  TextColumn     get selectedRegions => text()();    // JSON array
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn     get status => text().withDefault(const Constant('draft'))();
  IntColumn      get currentStopIdx => integer().withDefault(const Constant(0))();
  IntColumn      get regenerationsLeft => integer().withDefault(const Constant(3))();
  DateTimeColumn get updatedAt => dateTime()();
  // sync metadata
  IntColumn      get syncState => intEnum<SyncState>()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class TripStops extends Table {
  TextColumn     get id => text()();
  TextColumn     get tripId => text().references(Trips, #id)();
  TextColumn     get locationId => text().references(Locations, #id)();
  IntColumn      get position => integer()();
  TextColumn     get taskId => text().nullable()();
  TextColumn     get taskState => text().withDefault(const Constant('pending'))();
  IntColumn      get pointsAwarded => integer().withDefault(const Constant(0))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn      get syncState => intEnum<SyncState>()();
  @override Set<Column> get primaryKey => {id};
}

class SavedLocations extends Table {
  TextColumn     get locationId => text()();
  DateTimeColumn get savedAt => dateTime()();
  IntColumn      get syncState => intEnum<SyncState>()();
  @override Set<Column> get primaryKey => {locationId};
}

class Artifacts extends Table {
  TextColumn     get id => text()();           // local id, e.g. 'capture-1738…'
  TextColumn     get remoteId => text().nullable()();
  TextColumn     get tripId => text().nullable()();
  TextColumn     get locationId => text().nullable()();
  TextColumn     get kind => text()();
  TextColumn     get title => text().nullable()();
  TextColumn     get localImagePath => text().nullable()();  // absolute file path
  TextColumn     get remoteImagePath => text().nullable()(); // storage key
  TextColumn     get localModelPath => text().nullable()();  // cached .glb
  TextColumn     get remoteModelPath => text().nullable()();
  TextColumn     get modelJobId => text().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  BoolColumn     get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn      get syncState => intEnum<SyncState>()();
  @override Set<Column> get primaryKey => {id};
}

class ModelJobs extends Table {
  TextColumn     get id => text()();
  TextColumn     get artifactId => text().references(Artifacts, #id)();
  TextColumn     get status => text()();
  TextColumn     get inputSha256 => text()();
  TextColumn     get errorCode => text().nullable()();
  IntColumn      get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get queuedAt => dateTime()();
  DateTimeColumn get lastPolledAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class ChatMessages extends Table {
  TextColumn     get id => text()();
  TextColumn     get threadKey => text()();   // 'location:casbah' | 'trip:<uuid>'
  TextColumn     get role => text()();
  TextColumn     get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn      get syncState => intEnum<SyncState>()();
  @override Set<Column> get primaryKey => {id};
}

// ---------- Sync machinery ----------

class Outbox extends Table {
  IntColumn      get id => integer().autoIncrement()();
  TextColumn     get entityTable => text()();
  TextColumn     get entityId => text()();
  TextColumn     get operation => text()();   // insert | update | delete
  TextColumn     get payload => text()();     // JSON
  IntColumn      get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn     get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

class SyncState_ extends Table {
  @override String get tableName => 'sync_state';
  TextColumn     get key => text()();         // 'locations', 'trips', ...
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  TextColumn     get cursor => text().nullable()();  // ETag or max(updated_at)
  @override Set<Column> get primaryKey => {key};
}

class MediaCache extends Table {
  TextColumn     get remoteKey => text()();   // storage key or URL
  TextColumn     get localPath => text()();
  IntColumn      get sizeBytes => integer()();
  DateTimeColumn get lastAccessedAt => dateTime()();
  BoolColumn     get isPinned => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {remoteKey};
}

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override Set<Column> get primaryKey => {key};
}
```

```dart
enum SyncState { synced, pendingCreate, pendingUpdate, pendingDelete, conflict }
```

## Design notes

### IDs are generated on the device

Every user-owned row gets a UUID (or the existing
`capture-${millisecondsSinceEpoch}` format) locally at creation time. Waiting
for a server-assigned id means you cannot create anything offline. The server
accepts the client id as `local_id` and dedupes on it
([02](02-cloud-database-schema.md)).

### `syncState` on every owned row

This one column is the whole offline story. The sync engine's query is
"everything not `synced`". No separate change log to keep consistent with the
data.

### No geospatial index locally

SQLite has no PostGIS. Two options:

1. Do the radius filter in Dart over the cached catalogue. With a few hundred
   locations this is microseconds — `Distance().as(LengthUnit.Kilometer, a, b)`
   from `latlong2`, which is already a dependency.
2. Bounding-box pre-filter in SQL (`lat between ? and ?`), then refine in Dart.
   Worth it above ~5,000 rows.

Start with (1). The catalogue is 8 rows today.

The important thing is that **the same radius semantics apply in both places**.
If online uses `ST_DWithin` on a spheroid and offline uses flat Euclidean
distance, results differ near the poles and at large radii. Use
`latlong2`'s haversine (`Distance()`), which is close enough to the spheroid
at these scales, and write a test that compares both against a fixed set of
coordinates.

### Media files are not blobs

Images and `.glb` files stay on the filesystem; the DB stores paths. SQLite
handles multi-megabyte blobs badly and it makes the DB file unbackupable.

**A path stored today may be invalid tomorrow.** iOS changes the application
container UUID on reinstall and can change it on restore, so the absolute path
written at `lib/screens/ar_hunt/ar_hunt_screen.dart:596` will break. Store the
path *relative* to the documents directory and resolve at read time:

```dart
Future<File> resolve(String relativePath) async =>
    File(p.join((await getApplicationDocumentsDirectory()).path, relativePath));
```

This is an existing latent bug, not a new concern introduced by the backend.

### Encryption

Captures can include people and places; the DB holds trip history. On a
non-rooted device the app sandbox already protects it, so full-database
encryption is optional. If you want it, `sqlcipher_flutter_libs` swaps in for
`sqlite3_flutter_libs` with the key held in `flutter_secure_storage`.

What must be secure regardless: **the auth session** (covered in
[01](01-auth-and-accounts.md)). A stolen refresh token is worth far more than
a stolen local database.

## Migrations

```dart
@override int get schemaVersion => 1;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async {
    await m.createAll();
    await _seedCatalogueFromBundledJson();  // works on first launch offline
  },
  onUpgrade: (m, from, to) async {
    if (from < 2) await m.addColumn(artifacts, artifacts.localModelPath);
  },
  beforeOpen: (details) async {
    await customStatement('PRAGMA foreign_keys = ON');
  },
);
```

Two things people forget:

- **`PRAGMA foreign_keys = ON` in `beforeOpen`.** SQLite ignores foreign keys
  by default. Every `references` above is decorative without it.
- **Seed the catalogue from a bundled asset.** Port
  `lib/models/location_data.dart` to `assets/seed/catalogue.json` so a user on
  a plane with a fresh install still sees a map with content. The network pull
  then updates it.

## Repository layer

The blocs must not see Drift or Supabase types. One interface per aggregate:

```
lib/data/
  local/            drift database, tables, DAOs
  remote/           supabase client wrappers
  repositories/
    catalogue_repository.dart    nearby(), byId(), search()
    trip_repository.dart         active(), createFromSwipes(), reorder(), completeTask()
    artifact_repository.dart     all(), capture(), requestModel(), delete()
    profile_repository.dart      preferences, points
  sync/
    sync_engine.dart
    outbox_processor.dart
```

Repositories return streams; `AppBloc` subscribes:

```dart
on<_ArtifactsChanged>((e, emit) => emit(state.copyWith(capturedArtifacts: e.items)));

// in the constructor
_artifactSub = _artifacts.watchAll().listen((v) => add(_ArtifactsChanged(v)));
```

The existing event API barely changes. `AddCapturedArtifactEvent`
(`app_event.dart:190`) keeps its signature — the handler at
`app_bloc.dart:375` calls the repository instead of building an in-memory
`Artifact`, and the resulting stream emission updates state. This is why the
bloc refactor was worth doing before any of this.

## Testing checklist

- [ ] Airplane mode: accept a route, complete a task, capture an artifact — all persist across a cold restart
- [ ] Reconnect → outbox drains, rows flip to `synced`, no duplicates server-side
- [ ] Same capture flushed twice (kill mid-upload) → one row on the server
- [ ] Local radius filter and `nearby_locations` agree within 1% on a fixed coordinate set
- [ ] Fresh install with no network → bundled catalogue renders the map
- [ ] Foreign key violation actually raises (proves the pragma is on)
- [ ] DB opens after simulated schema upgrade from v1 to v2

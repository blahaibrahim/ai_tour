# 05 — Storage & Media

> **Status: Backend implemented.** Supabase Storage buckets (`captures`, `models`, `thumbnails`, `catalogue`) are created via SQL migrations with RLS policies in place. Maintenance cron jobs for purging orphan objects are active. Flutter frontend integration is pending.

Covers the binary side: capture photos, generated `.glb` models, thumbnails,
and how they move between the device and Supabase Storage.

## Buckets

| Bucket | Public | Contents | Typical size |
| --- | --- | --- | --- |
| `captures` | No | Source photos from the camera / AR snapshot | 200–800 KB after compression |
| `models` | No | Generated `.glb` from Hunyuan3D | 2–15 MB |
| `thumbnails` | No | 256 px previews for the folder grid | 15–40 KB |
| `catalogue` | **Yes** | Editorial photos of the 8+ locations | 100–400 KB |

Only `catalogue` is public — it's the same content for everyone and CDN
caching is worth more than access control on it. Everything user-generated is
private and served through short-lived signed URLs.

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('captures',   'captures',   false, 10485760, array['image/jpeg','image/png','image/webp']),
  ('models',     'models',     false, 52428800, array['model/gltf-binary','application/octet-stream']),
  ('thumbnails', 'thumbnails', false,   524288, array['image/webp','image/jpeg']),
  ('catalogue',  'catalogue',  true,  5242880,  array['image/jpeg','image/webp']);
```

`file_size_limit` and `allowed_mime_types` are enforced server-side. This is
your first line of defence against someone uploading a 4 GB file to your free
tier.

## Path convention

```
captures/{user_id}/{artifact_id}.jpg
models/{user_id}/{artifact_id}.glb
thumbnails/{user_id}/{artifact_id}.webp
catalogue/{location_id}/{variant}.webp        variant: card | hero | thumb
```

**The user id must be the first path segment.** Storage RLS policies work by
matching path components, and this layout makes "you can only touch your own
files" a one-line policy. It also makes account deletion a prefix delete.

## Storage RLS

```sql
create policy "read own captures"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "write own captures"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "delete own captures"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
```

Repeat for `thumbnails`. **`models` gets no client insert policy at all** —
only the Edge Function's service role writes there. If clients could write to
`models`, a user could upload an arbitrary file and claim it as a generated
model, bypassing the whole quota system.

`catalogue` is public read, service-role write.

## Upload path

### 1. Compress before upload

The AR snapshot at `ar_hunt_screen.dart:591` produces a full-resolution PNG.
PNG is the wrong format for a photograph — a 12 MP camera frame can be 8–15 MB
as PNG versus ~600 KB as quality-85 JPEG. On mobile data that's the difference
between an upload finishing and a user giving up.

```yaml
dependencies:
  flutter_image_compress: ^2.3.0
```

```dart
final compressed = await FlutterImageCompress.compressWithFile(
  sourcePath,
  minWidth: 1536,      // plenty for Hunyuan3D input
  minHeight: 1536,
  quality: 85,
  format: CompressFormat.jpeg,
  keepExif: false,     // see below
);
```

**`keepExif: false` is a privacy requirement, not an optimisation.** Camera
EXIF carries GPS coordinates, device model, and timestamp. Stripping it at the
source means a leaked or shared capture can't reveal where the user lives.
Where you *want* location on an artifact, store it as a column you control
(`artifacts.location_id`), not as metadata riding inside the file.

1536 px is above what the Hunyuan3D pipeline needs — it resizes internally —
while leaving room for a decent thumbnail and for future reprocessing.

### 2. Upload with resume

Files over ~6 MB should use resumable upload (Supabase Storage supports the
TUS protocol). Under that, a plain upload with retry is fine. Captures will
mostly be under; generated models are downloaded, not uploaded by the client.

```dart
await supabase.storage.from('captures').uploadBinary(
  '$userId/$artifactId.jpg',
  bytes,
  fileOptions: const FileOptions(
    contentType: 'image/jpeg',
    upsert: true,          // idempotent retry, matches the outbox contract
    cacheControl: '3600',
  ),
);
```

`upsert: true` is what makes a retried upload safe. See
[04](04-sync-and-caching.md).

### 3. Generate a thumbnail

The folder grid (`lib/screens/folder/widgets/artifacts_tab.dart`) renders many
artifacts at once. Downloading full captures for a grid of thumbnails is the
kind of thing that quietly eats your 2 GB egress allowance in a week.

Generate the thumbnail **on device** at capture time and upload both. It costs
nothing (the bytes are already in memory), works offline, and avoids running an
image pipeline on the server.

```dart
final thumb = await FlutterImageCompress.compressWithList(
  bytes, minWidth: 256, minHeight: 256, quality: 70, format: CompressFormat.webp,
);
```

## Download path

### Signed URLs

```dart
final url = await supabase.storage
    .from('captures')
    .createSignedUrl('$userId/$artifactId.jpg', 3600);
```

One hour is a reasonable TTL: long enough that a browsing session never
re-signs, short enough that a leaked URL is worthless by the time it's shared.

Batch it. Signing 30 grid thumbnails one at a time is 30 round trips:

```dart
final urls = await supabase.storage
    .from('thumbnails')
    .createSignedUrls(paths, 3600);
```

Cache the results in memory with their expiry, as described in
[04](04-sync-and-caching.md). Never write a signed URL into the database.

### Transformations

Supabase can resize images on the fly (`transform:` on the signed URL). It's
convenient, but on the free tier it's limited and it costs egress per variant.
Since you're generating thumbnails on device anyway, skip transformations for
user content. They're useful for the `catalogue` bucket where you control the
originals and want `card` / `hero` variants without pre-generating them.

### `.glb` download and cache

Models are the largest objects in the system and they never change once
generated. That makes them ideal cache candidates: download once, keep in the
cache directory, serve from disk forever.

```dart
Future<File> modelFile(Artifact a) async {
  final cached = await _mediaCache.lookup(a.remoteModelPath!);
  if (cached != null) return cached;
  final bytes = await supabase.storage.from('models').download(a.remoteModelPath!);
  return _mediaCache.store(a.remoteModelPath!, bytes);   // cache dir, LRU
}
```

## Rendering the model

`lib/widgets/cube3d.dart` builds a cube out of six `Transform`ed faces with a
photo on each — it is not a 3D model renderer, and it cannot display a `.glb`.
The 3D feature needs a real viewer.

Options, in order of fit:

| Package | Renderer | Notes |
| --- | --- | --- |
| `flutter_3d_controller` | Native (`SceneView` / `model-viewer`) | Simple API, plays animations, camera controls. Reasonable default. |
| `model_viewer_plus` | WebView + `<model-viewer>` | Very easy, works everywhere including web. Heavier — a WebView per model — and awkward inside a `PageView`. |
| `flutter_scene` | Impeller, pure Dart | No WebView, good performance. Younger; check maturity before committing. |
| `ar_flutter_plugin_2` | ARCore / ARKit | **Already a dependency.** It loads local `.glb` files from disk today (`ar_hunt_screen.dart:542`). Use it for viewing the model *in AR*. |

The strong play here: you already ship an AR renderer that loads a `file://`
GLB. "Place your generated model in the room" is a better feature than "spin it
in a box", and the code path exists. Use `flutter_3d_controller` for the
in-folder preview and the existing AR session for the full experience.

Either way `lib/screens/artifact_viewer/artifact_viewer_screen.dart` becomes a
branch: photo artifacts keep the existing cube, model artifacts get the real
viewer.

### Validate before rendering

A malformed `.glb` can crash the native renderer. `lib/ar/glb_bounds.dart`
already parses the glTF JSON header to read the bounding box — reuse it as a
validity gate. If the header doesn't parse or the bounds are degenerate
(zero or non-finite extent), show a "model unavailable" state and flag the
job, rather than handing bad bytes to the GPU.

## Retention

Storage is the free tier's tightest constraint: 1 GB. At ~10 MB per generated
model that's roughly 100 models across all users. You will hit this.

Policy:

- **Captures**: keep the compressed JPEG. It's small and it's the user's photo.
- **Models**: keep. This is the product.
- **Failed jobs' inputs**: delete after 7 days. No value once the failure is
  recorded.
- **Anonymous users' media**: delete with the account after 90 days of
  inactivity ([01](01-auth-and-accounts.md)).
- **Orphans**: any storage object with no matching `artifacts` row. These
  accumulate from interrupted uploads.

```sql
-- nightly, via pg_cron
select cron.schedule('purge-orphan-media', '0 4 * * *', $$
  select public.purge_orphan_storage_objects();
$$);
```

Write that function to list `storage.objects` and anti-join against
`public.artifacts`. Run it in report-only mode first and read the output before
letting it delete anything.

**Add a per-user storage cap** (say 200 MB) checked in the upload Edge
Function, so one enthusiastic user cannot consume the whole project quota.
Surface remaining space in settings.

## Testing checklist

- [ ] User A cannot read, write, or delete any object under `captures/{B}/`
- [ ] A client attempting to write directly to the `models` bucket is rejected
- [ ] Upload a 50 MB file to `captures` → rejected by the bucket size limit
- [ ] Upload a `.exe` renamed to `.jpg` → rejected by MIME type checking
- [ ] EXIF GPS is absent from every uploaded capture
- [ ] Retried upload of the same artifact produces one object, not two
- [ ] Grid of 30 artifacts issues one batched sign call, not 30
- [ ] Deleting an account removes every object under both `{uid}/` prefixes
- [ ] A truncated `.glb` shows the error state instead of crashing the renderer

-- The captures bucket was configured for photographs only, so every video
-- upload would have been refused by the bucket before it reached storage:
-- `video/mp4` is not in allowed_mime_types, and a 30-second clip routinely
-- exceeds the 10 MB ceiling that is generous for a JPEG.
--
-- quicktime is included because iOS records .mov, not .mp4 — an Android-only
-- allowance would have looked correct in testing and failed on half the
-- devices.
--
-- 60 MB matches the `models` bucket, which already carries multi-megabyte GLB
-- files, and bounds a 30-second clip at high bitrate with room to spare.
update storage.buckets
set allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp',
      'video/mp4', 'video/quicktime'
    ],
    file_size_limit = 62914560
where id = 'captures';

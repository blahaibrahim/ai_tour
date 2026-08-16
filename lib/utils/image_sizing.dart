/// Asking the image host for a photo the size we actually draw it.
///
/// Every catalogue photo in the app is one `pois.photo_url`, drawn at wildly
/// different sizes: a 56px list thumbnail, a 220px overview card, a full-bleed
/// swipe card. Before this, all of them fetched the same file — the seeded
/// 1280px Wikimedia thumbnail, or in a few dozen cases the untouched original,
/// which on Commons routinely runs to several megabytes. A list of ten saved
/// places pulled a few MB over mobile data to fill ten 56px squares, and the
/// decode cost of the full-size bitmap landed on the UI thread on top of it.
///
/// Wikimedia's thumbnailer will render any width on demand, so the fix is to
/// put the size we need into the URL. The rewrite is by string, not by
/// re-encoding through [Uri]: these paths are percent-encoded and Commons is
/// particular about them, so decoding and re-encoding risks changing bytes that
/// are part of the file's identity.
library;

/// The widths a photo may be requested at.
///
/// These are not free choices. Wikimedia stopped generating arbitrary widths on
/// demand (T414805): a hotlinked thumbnail request is now **rejected with HTTP
/// 400** unless its width is one of the standard sizes — 20, 40, 60, 120, 250,
/// 330, 500, 960, 1280, 1920, 3840. Only the ones this app has a use for are
/// listed here; anything below 120 is smaller than the smallest thumbnail it
/// draws, and anything above 1280 is past the resolution of the phone screens
/// it draws on (and past the 1280px the catalogue itself was seeded at).
///
/// Snapping to a bucket rather than using the exact measured size also means a
/// photo shown at 56px in one list and 76px in another shares a single cached
/// file instead of downloading twice, and keeps the disk cache bounded to a
/// handful of sizes per photo rather than one per layout.
///
/// Must stay sorted ascending — [imageWidthBucket] walks it in order.
const List<int> kImageWidthBuckets = <int>[120, 250, 330, 500, 960, 1280];

/// The bucket to request for a box [logicalWidth] wide on a [devicePixelRatio]
/// screen.
///
/// Rounds *up* — a photo drawn slightly softer than native is a worse trade
/// than one extra bucket of bytes, and [BoxFit.cover] crops, which means the
/// source often needs to be wider than the box to fill it.
int imageWidthBucket(double logicalWidth, double devicePixelRatio) {
  // Unbounded or nonsense constraints: no information to size from, so ask for
  // the largest bucket rather than guessing small and showing a blurry photo.
  if (!logicalWidth.isFinite || logicalWidth <= 0) return kImageWidthBuckets.last;
  final physical = logicalWidth * (devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1.0);
  for (final bucket in kImageWidthBuckets) {
    if (bucket >= physical) return bucket;
  }
  return kImageWidthBuckets.last;
}

const String _kUploadPrefix = 'https://upload.wikimedia.org/wikipedia/';

/// Largest bucket at which an *original* file is worth re-requesting as a
/// thumbnail. See the originals branch of [sizedImageUrl] for the reasoning.
const int _kOriginalRewriteMax = 500;

/// Matches the `1280px-` width marker in a Commons thumbnail filename.
///
/// Not anchored to the start: some thumbnails carry a prefix first, e.g.
/// `lossy-page1-1280px-Foo.tif.jpg` for a multi-page source.
final RegExp _thumbWidth = RegExp(r'(\d+)px-');

/// The extension Commons' thumbnailer emits for a source it cannot serve in its
/// own format. Vector and document sources are rasterised; TIFFs are converted.
String _thumbSuffixFor(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.svg')) return '.png';
  if (lower.endsWith('.tif') || lower.endsWith('.tiff')) return '.jpg';
  if (lower.endsWith('.pdf') || lower.endsWith('.djvu')) return '.jpg';
  return '';
}

/// Rewrites [url] to request a copy about [targetWidth] pixels wide.
///
/// Returns [url] unchanged when it isn't a Wikimedia upload URL, when it is
/// already a thumbnail no larger than [targetWidth] (widening it would cost
/// bytes to gain nothing), or when the path doesn't parse into a shape the
/// thumbnailer understands. Callers can therefore compare the result to the
/// input to tell whether a rewrite happened.
///
/// [targetWidth] must be one of [kImageWidthBuckets]; Wikimedia rejects widths
/// outside its standard set outright.
///
/// Even with a standard width, a rewrite is a request for a file that may not
/// exist — Commons will not upscale, so asking a 400px-wide original for a
/// 500px thumbnail fails. Callers that display the result should be prepared to
/// fall back to the original URL; [NetImage] does.
String sizedImageUrl(String url, int targetWidth) {
  if (url.isEmpty || targetWidth <= 0) return url;
  if (!url.startsWith(_kUploadPrefix)) return url;

  final rest = url.substring(_kUploadPrefix.length);
  // Anything with a query or fragment isn't a plain file path; leave it be.
  if (rest.contains('?') || rest.contains('#')) return url;
  final parts = rest.split('/');

  // Already a thumbnail: <project>/thumb/<a>/<ab>/<file>/<NNNpx-file>
  if (parts.length >= 6 && parts[1] == 'thumb') {
    final name = parts.last;
    final match = _thumbWidth.firstMatch(name);
    if (match == null) return url;
    final current = int.tryParse(match.group(1)!);
    // Already at or below what we need — serving a smaller file than asked for
    // is fine, and re-requesting at a different width would only miss the cache.
    if (current == null || current <= targetWidth) return url;
    parts[parts.length - 1] =
        name.replaceRange(match.start, match.end, '${targetWidth}px-');
    return '$_kUploadPrefix${parts.join('/')}';
  }

  // An untouched original: <project>/<a>/<ab>/<file>.
  //
  // Only worth rewriting when we want it substantially smaller. Measured across
  // the originals in the catalogue, they run from about 5KB to 555KB — mostly
  // web-sized uploads rather than the multi-megabyte scans an "original" might
  // suggest. Re-rendering one of those at 1280px routinely produces a *larger*
  // file than the original (one 103KB upload comes back as 275KB), and for an
  // original narrower than the bucket the thumbnailer refuses outright, costing
  // a wasted request before the fallback. So above [_kOriginalRewriteMax] the
  // original is left alone: it is already close to the right scale.
  if (targetWidth <= _kOriginalRewriteMax && parts.length == 4 && parts[1] != 'thumb') {
    final project = parts[0];
    final a = parts[1];
    final ab = parts[2];
    final file = parts[3];
    if (file.isEmpty || !file.contains('.')) return url;
    final suffix = _thumbSuffixFor(file);
    return '$_kUploadPrefix$project/thumb/$a/$ab/$file/${targetWidth}px-$file$suffix';
  }

  return url;
}

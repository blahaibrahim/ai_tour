import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/image_sizing.dart';
import '../widgets/net_image.dart';

/// Warms the image cache for photos the user is about to see.
///
/// Caching alone only helps the *second* time a photo is shown. The first time
/// is still a cold download, and the app has two places where that is
/// especially visible: the swipe deck, which builds only three cards deep while
/// a card is dismissed every second or two, and the overview's upcoming row,
/// which is lazy and so starts a download at the moment a card is scrolled into
/// view. In both, the URLs are known well before the widget that draws them is
/// built — so the download can start early and be finished, or nearly so, by
/// the time the image is on screen.
///
/// Writes into [DefaultCacheManager], which is the same store
/// [CachedNetworkImageProvider] reads from, so a warmed file is a plain cache
/// hit at display time with no coordination between the two.
class ImagePrefetch {
  const ImagePrefetch._();

  /// At most this many prefetches in flight at once.
  ///
  /// Prefetching competes for bandwidth with the image the user is actually
  /// looking at, which must win — fetching the whole deck at once would make
  /// the visible card slower to arrive in exchange for cards that may never be
  /// reached. Wikimedia also rate-limits bursts from one client, and a 429
  /// costs more than it saves.
  static const int _maxConcurrent = 3;

  /// URLs already requested this session, so a rebuilding list doesn't queue
  /// the same download repeatedly. Keyed by the resized URL, since that is what
  /// is actually fetched.
  static final Set<String> _requested = <String>{};

  static int _inFlight = 0;
  static final List<String> _queue = <String>[];

  /// Starts downloading [urls] at the size a box [logicalWidth] wide will draw
  /// them, skipping blanks and anything already fetched.
  ///
  /// Returns immediately; failures are ignored, since a prefetch that doesn't
  /// land simply leaves the normal load to do its job.
  static void warm(
    Iterable<String> urls, {
    required double logicalWidth,
    required double devicePixelRatio,
  }) {
    final width = imageWidthBucket(logicalWidth, devicePixelRatio);
    for (final url in urls) {
      if (url.isEmpty) continue;
      final resized = sizedImageUrl(url, width);
      if (!_requested.add(resized)) continue;
      _queue.add(resized);
    }
    _pump();
  }

  static void _pump() {
    while (_inFlight < _maxConcurrent && _queue.isNotEmpty) {
      _inFlight++;
      unawaited(_fetch(_queue.removeAt(0)));
    }
  }

  static Future<void> _fetch(String url) async {
    try {
      await DefaultCacheManager().downloadFile(url, authHeaders: kImageRequestHeaders);
    } catch (_) {
      // A prefetch is best-effort. The most likely failure is the thumbnailer
      // refusing to upscale a small original, which NetImage recovers from on
      // its own by re-requesting the full-size URL. Forget the URL so a later
      // attempt isn't suppressed by this one being remembered as done.
      _requested.remove(url);
    } finally {
      _inFlight--;
      _pump();
    }
  }
}

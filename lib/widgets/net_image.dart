import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/image_sizing.dart';
import 'shimmer.dart';

/// Sent with every remote image request.
///
/// Nearly all catalogue photos are hosted on upload.wikimedia.org, whose
/// User-Agent policy throttles or refuses requests that don't identify
/// themselves — an empty UA gets a flat 403, and anonymous-looking clients are
/// first in line for a 429 when several cards load their images at once.
/// Identifying the app is the difference between a grid of photos and a grid
/// of broken-image icons under load.
const kImageRequestHeaders = <String, String>{
  'User-Agent': 'ai_tour/1.0 (Flutter; contact via github.com/AB00R/ai_tour)',
};

/// Resolves either a network URL or a local file path to the right
/// [ImageProvider] — used anywhere an artifact photo might be either.
///
/// The network case goes through the shared disk cache rather than
/// [NetworkImage], whose cache is memory-only and so starts empty every launch.
ImageProvider resolveImageProvider(String source, {bool isLocalFile = false}) {
  return isLocalFile
      ? FileImage(File(source)) as ImageProvider
      : CachedNetworkImageProvider(source, headers: kImageRequestHeaders);
}

/// Stand-in for a location with no photograph in the catalogue.
///
/// The navy field and fennec mark match the app icon and splash, so an
/// unphotographed place reads as "we don't have a picture of this yet"
/// rather than showing a stock photo of somewhere it isn't.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.deepNavy, AppTheme.accentDark],
        ),
      ),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Scale with the slot so the mark reads at both a 56px list thumb
          // and a full-bleed detail header.
          final side = constraints.biggest.shortestSide;
          return Opacity(
            opacity: 0.55,
            child: Image.asset(
              'assets/icon/app-icon-transparent.png',
              width: side.isFinite ? side * 0.5 : 64,
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }
}

/// Small caption marking a photo as not being of the place it illustrates.
///
/// Most POIs have no photograph of their own, so the alternative to a
/// neighbourhood picture is an empty placeholder. Showing one unlabelled
/// would repeat the mistake of the old picsum fallback — a real photograph of
/// somewhere else, presented as if it were here. This is what makes the
/// difference between a helpful illustration and a false one, so it is
/// deliberately legible rather than tucked away.
class StockPhotoTag extends StatelessWidget {
  const StockPhotoTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: AppTheme.brPill,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 11, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image (network or local file) with a shimmer skeleton while loading, a
/// soft fade-in once the first frame lands, and a graceful fallback if the
/// load fails.
///
/// Remote images are fetched at a size chosen from the box they are drawn in
/// (see [sizedImageUrl]) and held in a disk cache that survives restarts, so a
/// photo is downloaded at full size at most once and usually never.
class NetImage extends StatelessWidget {
  final String url;
  final bool isLocalFile;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  /// Stable identity for the cached file, when [url] itself isn't one.
  ///
  /// Capture thumbnails live in a private bucket and are reached through a
  /// signed URL that carries a token and expires hourly. Keyed on the URL, the
  /// same photo would be re-downloaded every hour and left behind under a dead
  /// key each time; keyed on its storage path, it is fetched once.
  final String? cacheKey;

  const NetImage({
    super.key,
    required this.url,
    this.isLocalFile = false,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    // No photo for this place. Draw the brand mark rather than borrowing an
    // unrelated stock photograph, which is what the old picsum fallback did.
    if (!isLocalFile && url.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: PhotoPlaceholder(width: width, height: height),
      );
    }

    // An explicit width is the width — a thumbnail in a ListTile.leading slot
    // is handed a far roomier box than the 56px it asks for, so measuring the
    // box would fetch a bucket or two too large. It also means no LayoutBuilder
    // in the common list-thumbnail case.
    if (width != null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: _sized(imageWidthBucket(width!, MediaQuery.devicePixelRatioOf(context))),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) => _sized(
          imageWidthBucket(constraints.maxWidth, MediaQuery.devicePixelRatioOf(context)),
        ),
      ),
    );
  }

  /// The image itself, once the width it will be drawn at is known.
  Widget _sized(int targetWidth) {
    if (isLocalFile) {
      return Image.file(
        File(url),
        width: width,
        height: height,
        fit: fit,
        // Decode at display size. A full-resolution phone capture decodes to
        // tens of megabytes of bitmap, which is slow and on its own enough to
        // evict everything else from the image cache.
        cacheWidth: targetWidth,
        frameBuilder: _frameBuilder,
        errorBuilder: (context, error, stack) => _errorBox(width, height),
      );
    }
    return _RemoteImage(
      url: url,
      cacheKey: cacheKey,
      targetWidth: targetWidth,
      width: width,
      height: height,
      fit: fit,
    );
  }
}

Widget _frameBuilder(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOut,
    child: child,
  );
}

Widget _errorBox(double? width, double? height) => Container(
      width: width,
      height: height,
      color: AppTheme.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported_outlined, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
    );

/// A cached remote image that retries at full size if the resized URL fails.
///
/// [sizedImageUrl] asks Wikimedia's thumbnailer for a width the source may not
/// be able to satisfy — Commons will not upscale, so a photo whose original is
/// narrower than the bucket we asked for 404s. That is rare, but the failure is
/// a visible broken tile, so it is worth one retry against the URL the
/// catalogue actually gave us before giving up.
class _RemoteImage extends StatefulWidget {
  const _RemoteImage({
    required this.url,
    required this.cacheKey,
    required this.targetWidth,
    required this.width,
    required this.height,
    required this.fit,
  });

  final String url;
  final String? cacheKey;
  final int targetWidth;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  bool _useOriginal = false;

  @override
  void didUpdateWidget(_RemoteImage old) {
    super.didUpdateWidget(old);
    // A different photo (or a different size of it) deserves its own attempt;
    // otherwise a single failure would pin this slot to full-size loads.
    if (old.url != widget.url || old.targetWidth != widget.targetWidth) {
      _useOriginal = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resized = sizedImageUrl(widget.url, widget.targetWidth);
    final canRetry = !_useOriginal && resized != widget.url;
    final imageUrl = _useOriginal ? widget.url : resized;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      // Signed URLs rotate; the width is part of the identity of the file.
      cacheKey: widget.cacheKey == null ? null : '${widget.cacheKey}@${widget.targetWidth}',
      httpHeaders: kImageRequestHeaders,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      // Decode to the size drawn rather than the size downloaded. Buckets round
      // up, so this also trims the overshoot.
      memCacheWidth: widget.targetWidth,
      fadeInDuration: const Duration(milliseconds: 350),
      fadeInCurve: Curves.easeOut,
      // A cache hit should appear immediately — fading it in makes a warm
      // scroll look slower than it is.
      fadeOutDuration: Duration.zero,
      placeholder: (context, _) => const ShimmerFill(),
      errorWidget: (context, _, _) {
        if (canRetry) {
          // Rebuild against the original URL. Deferred because errorWidget runs
          // during build, where setState is not allowed.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useOriginal = true);
          });
          return const ShimmerFill();
        }
        return _errorBox(widget.width, widget.height);
      },
    );
  }
}

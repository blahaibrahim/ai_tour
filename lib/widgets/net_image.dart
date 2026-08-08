import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
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
ImageProvider resolveImageProvider(String source, {bool isLocalFile = false}) {
  return isLocalFile
      ? FileImage(File(source)) as ImageProvider
      : NetworkImage(source, headers: kImageRequestHeaders);
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
class NetImage extends StatelessWidget {
  final String url;
  final bool isLocalFile;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const NetImage({
    super.key,
    required this.url,
    this.isLocalFile = false,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
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

    Widget frameBuilder(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
      if (wasSynchronouslyLoaded) return child;
      return AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        child: child,
      );
    }

    Widget errorBuilder(BuildContext context, Object error, StackTrace? stack) => Container(
          width: width,
          height: height,
          color: AppTheme.surfaceAlt,
          alignment: Alignment.center,
          child: Icon(Icons.image_not_supported_outlined, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
        );

    return ClipRRect(
      borderRadius: borderRadius,
      child: isLocalFile
          ? Image.file(
              File(url),
              width: width,
              height: height,
              fit: fit,
              frameBuilder: frameBuilder,
              errorBuilder: errorBuilder,
            )
          : Image.network(
              url,
              headers: kImageRequestHeaders,
              width: width,
              height: height,
              fit: fit,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const ShimmerFill();
              },
              frameBuilder: frameBuilder,
              errorBuilder: errorBuilder,
            ),
    );
  }
}

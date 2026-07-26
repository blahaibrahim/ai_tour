import 'dart:io';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'shimmer.dart';

/// Resolves either a network URL or a local file path to the right
/// [ImageProvider] — used anywhere an artifact photo might be either.
ImageProvider resolveImageProvider(String source, {bool isLocalFile = false}) {
  return isLocalFile ? FileImage(File(source)) as ImageProvider : NetworkImage(source);
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
          child: Icon(Icons.image_not_supported_outlined, color: AppTheme.textSecondary.withOpacity(0.6)),
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

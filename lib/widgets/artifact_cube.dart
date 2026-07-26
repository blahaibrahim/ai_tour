import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/location.dart';
import '../theme.dart';
import 'cube3d.dart';
import 'net_image.dart';

/// A slowly auto-rotating 3D cube used as a folder-grid thumbnail — the
/// artifact photo wraps the front/back faces, solid panels form the sides.
class ArtifactCubeThumbnail extends StatefulWidget {
  final Artifact artifact;
  final double size;

  const ArtifactCubeThumbnail({super.key, required this.artifact, this.size = 120});

  @override
  State<ArtifactCubeThumbnail> createState() => _ArtifactCubeThumbnailState();
}

class _ArtifactCubeThumbnailState extends State<ArtifactCubeThumbnail> with SingleTickerProviderStateMixin {
  // A gentle side-to-side rock rather than a full spin, so the photo face
  // stays mostly toward the viewer — a full 360 turn hides the photo behind
  // solid side panels for most of the cycle, which reads poorly as a preview.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = NetImage(
      url: widget.artifact.photoUrl,
      isLocalFile: widget.artifact.isLocalFile,
      fit: BoxFit.cover,
    );
    final edge = Container(color: AppTheme.tertiary);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return Cube3D(
          size: widget.size,
          rotateX: -0.16 + math.sin(t * 0.5) * 0.03,
          rotateY: math.sin(t) * 0.5,
          front: image,
          back: image,
          left: edge,
          right: edge,
          top: edge,
          bottom: edge,
        );
      },
    );
  }
}

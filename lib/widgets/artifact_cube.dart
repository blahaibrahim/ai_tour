import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/location.dart';
import '../theme.dart';
import 'cube3d.dart';

/// Solid-color placeholder faces for an artifact cube — no photo texture.
/// The cube is a stand-in for "something was captured here," shaded like a
/// simple flat-design die (lighter top, mid front, darker sides/back) and
/// colored by kind so scans and videos read apart at a glance.
List<Widget> artifactCubeFaces(Artifact artifact, {double iconSize = 28}) {
  final isVideo = artifact.kindLabel.toLowerCase() == 'video';
  final base = isVideo ? AppTheme.secondaryAccent : AppTheme.accent;
  final icon = isVideo ? Icons.videocam_rounded : Icons.qr_code_scanner_rounded;

  Color shade(double amount) {
    if (amount >= 0) return Color.lerp(base, Colors.white, amount)!;
    return Color.lerp(base, Colors.black, -amount)!;
  }

  Widget face(Color color, {Widget? child}) => ColoredBox(color: color, child: Center(child: child));

  return [
    face(base, child: Icon(icon, color: Colors.white.withOpacity(0.85), size: iconSize)), // front
    face(shade(-0.28)), // back
    face(shade(-0.16)), // left
    face(shade(-0.16)), // right
    face(shade(0.22)), // top
    face(shade(-0.10)), // bottom
  ];
}

/// A slowly auto-rotating 3D cube used as a folder-grid thumbnail.
class ArtifactCubeThumbnail extends StatefulWidget {
  final Artifact artifact;
  final double size;

  const ArtifactCubeThumbnail({super.key, required this.artifact, this.size = 120});

  @override
  State<ArtifactCubeThumbnail> createState() => _ArtifactCubeThumbnailState();
}

class _ArtifactCubeThumbnailState extends State<ArtifactCubeThumbnail> with SingleTickerProviderStateMixin {
  // A gentle side-to-side rock rather than a full spin, so the front face
  // stays mostly toward the viewer.
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
    final faces = artifactCubeFaces(widget.artifact);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return Cube3D(
          size: widget.size,
          rotateX: -0.16 + math.sin(t * 0.5) * 0.03,
          rotateY: math.sin(t) * 0.5,
          front: faces[0],
          back: faces[1],
          left: faces[2],
          right: faces[3],
          top: faces[4],
          bottom: faces[5],
        );
      },
    );
  }
}

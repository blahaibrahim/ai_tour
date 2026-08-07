import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import '../../models/location.dart';
import '../../services/media_cache.dart';
import '../../theme.dart';
import '../../widgets/artifact_cube.dart';
import '../../widgets/cube3d.dart';
import '../../widgets/pressable_scale.dart';

/// Full interactive viewer for artifacts.
///
/// Photo/video artifacts are rendered as a 3D photo cube.
/// Generated 3D GLB models (when modelStatus == succeeded) are rendered using
/// a real native 3D GLB viewer via [Flutter3DViewer].
class ArtifactViewerScreen extends StatefulWidget {
  final Artifact artifact;

  const ArtifactViewerScreen({super.key, required this.artifact});

  @override
  State<ArtifactViewerScreen> createState() => _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends State<ArtifactViewerScreen>
    with SingleTickerProviderStateMixin {
  // Cube control state
  double _rotX = -0.22;
  double _rotY = 0.5;
  double _scale = 1.0;
  double _baseScale = 1.0;

  Duration _lastElapsed = Duration.zero;
  DateTime _lastInteraction = DateTime.now().subtract(const Duration(seconds: 5));
  late final Ticker _ticker;

  // Real GLB model file state
  File? _glbFile;
  bool _loadingGlb = false;
  String? _glbError;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();

    if (widget.artifact.modelPath != null &&
        widget.artifact.modelStatus == ModelStatus.succeeded) {
      _loadGlbModel();
    }
  }

  Future<void> _loadGlbModel() async {
    setState(() => _loadingGlb = true);
    final file = await MediaCache.getModel(widget.artifact.modelPath!);
    if (mounted) {
      setState(() {
        _glbFile = file;
        _loadingGlb = false;
        if (file == null) _glbError = 'Could not load 3D model file';
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (DateTime.now().difference(_lastInteraction) >
        const Duration(milliseconds: 1100)) {
      setState(() => _rotY += dt * 0.32);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastInteraction = DateTime.now();
    _baseScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _lastInteraction = DateTime.now();
    setState(() {
      _rotY += details.focalPointDelta.dx * 0.012;
      _rotX = (_rotX - details.focalPointDelta.dy * 0.012).clamp(-1.3, 1.3);
      _scale = (_baseScale * details.scale).clamp(0.6, 2.4);
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _lastInteraction = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.artifact;
    final isRealGlb = art.modelStatus == ModelStatus.succeeded && art.modelPath != null;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  PressableScale(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        shape: BoxShape.circle,
                        boxShadow: AppTheme.shadowSm,
                      ),
                      child: const Icon(Icons.arrow_back, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          art.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontSize: 17),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          art.region,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isRealGlb
                  ? _buildGlbViewer()
                  : _buildPhotoCubeViewer(art),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                isRealGlb
                    ? 'Interactive 3D Model — Touch to rotate'
                    : 'Drag to rotate · Pinch to zoom',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlbViewer() {
    if (_loadingGlb) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accent),
            SizedBox(height: 16),
            Text(
              'Loading 3D model…',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Checked before _glbFile so a viewer that fails after the file loaded
    // (a corrupt GLB, say) replaces itself with the message rather than
    // sitting there blank.
    if (_glbError == null && _glbFile != null) {
      return Flutter3DViewer(
        // Must be a file:// URI, not a bare path. The viewer's local HTTP proxy
        // branches on the scheme: anything without one is treated as a Flutter
        // asset key and sent to rootBundle.load(), which throws for a cache
        // path. The request for /model then never completes and <model-viewer>
        // draws an empty canvas — a blank screen with no error.
        src: Uri.file(_glbFile!.path).toString(),
        onError: (error) {
          if (!mounted) return;
          setState(() => _glbError = 'Could not display 3D model — $error');
        },
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.amber),
            const SizedBox(height: 12),
            Text(
              _glbError ?? 'Could not display 3D model',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoCubeViewer(Artifact art) {
    final faces = artifactCubeFaces(art, iconSize: 46);
    final cubeSize = MediaQuery.of(context).size.shortestSide * 0.62;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: Center(
        child: Transform.scale(
          scale: _scale,
          child: Cube3D(
            size: cubeSize,
            rotateX: _rotX,
            rotateY: _rotY,
            front: faces[0],
            back: faces[1],
            left: faces[2],
            right: faces[3],
            top: faces[4],
            bottom: faces[5],
          ),
        ),
      ),
    );
  }
}

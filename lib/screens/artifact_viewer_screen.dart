import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/location.dart';
import '../theme.dart';
import '../widgets/cube3d.dart';
import '../widgets/net_image.dart';
import '../widgets/pressable_scale.dart';

/// Full interactive 3D view of an artifact — drag to turn it around, pinch
/// to zoom. Auto-rotates gently for show, and pauses the moment a finger
/// touches it.
class ArtifactViewerScreen extends StatefulWidget {
  final Artifact artifact;

  const ArtifactViewerScreen({super.key, required this.artifact});

  @override
  State<ArtifactViewerScreen> createState() => _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends State<ArtifactViewerScreen> with SingleTickerProviderStateMixin {
  double _rotX = -0.22;
  double _rotY = 0.5;
  double _scale = 1.0;
  double _baseScale = 1.0;

  Duration _lastElapsed = Duration.zero;
  DateTime _lastInteraction = DateTime.now().subtract(const Duration(seconds: 5));
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (DateTime.now().difference(_lastInteraction) > const Duration(milliseconds: 1100)) {
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
    final image = NetImage(url: art.photoUrl, isLocalFile: art.isLocalFile, fit: BoxFit.cover);
    final edge = Container(color: AppTheme.tertiary);
    final cubeSize = MediaQuery.of(context).size.shortestSide * 0.62;

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
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 17),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          art.region,
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
              child: GestureDetector(
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
                      front: image,
                      back: image,
                      left: edge,
                      right: edge,
                      top: edge,
                      bottom: edge,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Drag to rotate · Pinch to zoom',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

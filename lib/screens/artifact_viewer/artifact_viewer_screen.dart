import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import 'package:video_player/video_player.dart';

import '../../models/location.dart';
import '../../services/media_cache.dart';
import '../../theme.dart';
import '../../widgets/artifact_cube.dart';
import '../../widgets/cube3d.dart';
import '../../widgets/net_image.dart';
import '../../widgets/pressable_scale.dart';

/// Full viewer for artifacts, which opens each kind as what it actually is.
///
/// It did not always: every artifact that was not a finished GLB opened as a
/// rotating photo cube, so a photograph could only be looked at wrapped around
/// a spinning box and a video showed a still of nothing on six faces. The cube
/// is a nice object for an artifact with no real media behind it — a fennec, a
/// model still generating — and a poor one for a picture somebody took.
///
///   * **3D model** (`modelStatus == succeeded`) → the native GLB viewer.
///   * **Video** → a player with play/pause and a scrubber.
///   * **Photo** → the photograph, pan and zoom.
///   * **Anything with no media** → the cube, as before.
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
            Expanded(child: _buildBody(art, isRealGlb)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                _hintFor(art, isRealGlb),
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

  /// True when this artifact has real media on disk or in storage — as opposed
  /// to a fennec or a model still generating, which have nothing to show and
  /// are what the cube exists for.
  bool _hasMedia(Artifact art) {
    if (art.photoUrl.isEmpty) return false;
    if (art.isLocalFile) return File(art.photoUrl).existsSync();
    return art.photoUrl.startsWith('captures/');
  }

  bool _isVideo(Artifact art) => art.kindLabel == 'Video';

  Widget _buildBody(Artifact art, bool isRealGlb) {
    if (isRealGlb) return _buildGlbViewer();
    if (_isVideo(art) && _hasMedia(art)) return _ClipPlayer(artifact: art);
    if (_hasMedia(art)) {
      return art.isLocalFile
          ? _buildPhotoViewer(art)
          // Restored from storage: the key has to be signed before it can be
          // loaded, so it opens as a photo rather than falling back to the
          // cube the way it used to.
          : _StoredPhotoViewer(key: ValueKey(art.id), artifact: art);
    }
    return _buildPhotoCubeViewer(art);
  }

  String _hintFor(Artifact art, bool isRealGlb) {
    if (isRealGlb) return 'Interactive 3D model — touch to rotate';
    if (_isVideo(art) && _hasMedia(art)) return 'Tap the video to play or pause';
    if (_hasMedia(art)) return 'Pinch to zoom · drag to pan';
    return 'Drag to rotate · pinch to zoom';
  }

  /// The photograph itself.
  ///
  /// [InteractiveViewer] rather than the cube's bespoke gesture handling: pan
  /// and zoom on a flat image is a solved problem, and it bounds the transform
  /// so the picture cannot be flung off screen and lost.
  Widget _buildPhotoViewer(Artifact art) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.file(
          File(art.photoUrl),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _buildPhotoCubeViewer(art),
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

/// Plays a clip from the folder.
///
/// Not looping, unlike the review player at capture time: there the clip was
/// being judged and a loop kept it in front of you, here it is being watched
/// and a video that silently restarts is a video you cannot tell has ended.
class _ClipPlayer extends StatefulWidget {
  const _ClipPlayer({required this.artifact});

  final Artifact artifact;

  @override
  State<_ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends State<_ClipPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final art = widget.artifact;
    VideoPlayerController? controller;
    try {
      if (art.isLocalFile) {
        controller = VideoPlayerController.file(File(art.photoUrl));
      } else {
        // Stored clips live in a private bucket, so the URL has to be signed
        // before it can be handed to the player.
        final url = await MediaCache.captureSignedUrlForPath(art.photoUrl);
        if (url == null) throw StateError('could not sign the clip URL');
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await controller.initialize();
      await controller.play();
    } catch (_) {
      await controller?.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // Reaching the end flips isPlaying to false without anything calling
    // setState, so without this the play overlay never comes back and the
    // clip looks like it is still running.
    controller.addListener(_onPlaybackChanged);
    setState(() => _controller = controller);
  }

  bool _wasPlaying = true;

  void _onPlaybackChanged() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlaybackChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        // Replay from the start once it has run to the end, rather than
        // resuming from a final frame that is already over.
        if (controller.value.position >= controller.value.duration) {
          controller.seekTo(Duration.zero);
        }
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_rounded,
                  size: 32, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(
                "This clip can't be played — the file may have been removed.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    // Only while paused: an overlay on a playing video is in
                    // the way of the thing it is overlaying.
                    if (!controller.value.isPlaying)
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 36),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor: AppTheme.accent,
              bufferedColor: AppTheme.accentSoft,
              backgroundColor: AppTheme.surfaceAlt,
            ),
          ),
        ),
      ],
    );
  }
}

/// A photo restored from Supabase storage, whose `photoUrl` is a private key
/// rather than something an image widget can load directly.
class _StoredPhotoViewer extends StatefulWidget {
  const _StoredPhotoViewer({super.key, required this.artifact});

  final Artifact artifact;

  @override
  State<_StoredPhotoViewer> createState() => _StoredPhotoViewerState();
}

class _StoredPhotoViewerState extends State<_StoredPhotoViewer> {
  String? _url;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final url = await MediaCache.captureSignedUrlForPath(widget.artifact.photoUrl);
    if (!mounted) return;
    setState(() {
      _url = url;
      _resolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final url = _url;
    if (url == null) {
      return Center(
        child: Text(
          "This photo couldn't be loaded.",
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(child: NetImage(url: url, fit: BoxFit.contain)),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/location.dart';
import '../../../services/media_cache.dart';
import '../../../theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/net_image.dart';
import '../../../widgets/shimmer.dart';
import '../../../widgets/pressable_scale.dart';
import '../../../widgets/staggered_entrance.dart';
import '../../../widgets/artifact_cube.dart';
import '../../artifact_viewer/artifact_viewer_screen.dart';

/// Grid tab showing captured and example artifacts with 3D generation status badges.
class ArtifactsTab extends StatelessWidget {
  const ArtifactsTab({super.key, required this.artifacts});

  final List<Artifact> artifacts;

  @override
  Widget build(BuildContext context) {
    return artifacts.isEmpty
        ? _emptyState(context)
        : GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: artifacts.length,
            itemBuilder: (context, i) {
              final art = artifacts[i];
              return StaggeredEntrance(
                index: i,
                child: PressableScale(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ArtifactViewerScreen(artifact: art)),
                  ),
                  child: GlassSurface(
                    borderRadius: AppTheme.brLg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Center(child: _buildMediaPreview(context, art)),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: _buildBadge(context, art),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                art.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                art.modelStatus == ModelStatus.failed
                                    ? modelFailureMessage(
                                        AppLocalizations.of(context), art.errorCode)
                                    : art.region,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: art.modelStatus == ModelStatus.failed
                                      ? Colors.redAccent
                                      : AppTheme.text.withValues(alpha: 0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
  }

  Widget _buildMediaPreview(BuildContext context, Artifact art) {
    // A clip is not an image, so no image widget can show it. Without this it
    // falls through to Image.file, fails to decode an mp4, and lands on the
    // cube thumbnail — which reads as a broken 3D model rather than as a
    // video. Drawing it deliberately is both honest and less work than the
    // alternative, which is a frame-extraction dependency.
    if (art.kindLabel == 'Video') return _VideoThumbnail(artifact: art);

    if (art.isLocalFile && File(art.photoUrl).existsSync()) {
      return Image.file(
        File(art.photoUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ArtifactCubeThumbnail(artifact: art, size: 104),
      );
    }
    // Restored from Supabase: photoUrl is a private storage key. Key on the
    // artifact id so the sign-and-load isn't redone every time the search box
    // rebuilds the grid.
    if (!art.isLocalFile && art.photoUrl.startsWith('captures/')) {
      return _StoredCapturePreview(key: ValueKey(art.id), artifact: art);
    }
    return ArtifactCubeThumbnail(artifact: art, size: 104);
  }

  Widget _buildBadge(BuildContext context, Artifact art) {
    if (art.modelStatus == ModelStatus.generating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.ink,
          borderRadius: AppTheme.brPill,
          boxShadow: AppTheme.shadowSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.sand),
            ),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context).artifactGenerating3d,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.sand),
            ),
          ],
        ),
      );
    }

    if (art.modelStatus == ModelStatus.failed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: AppTheme.brPill,
          boxShadow: AppTheme.shadowSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context).artifact3dFailed,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (art.modelStatus == ModelStatus.succeeded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: AppTheme.brPill,
          boxShadow: AppTheme.shadowSm,
        ),
        child: Text(
          AppLocalizations.of(context).artifact3dModel,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.onAccent),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: AppTheme.brPill,
        boxShadow: AppTheme.shadowSm,
      ),
      child: Text(
        art.kindLabel,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.accent),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.deepNavy),
            child: const Icon(Icons.photo_library_outlined, color: AppTheme.onNavy, size: 32),
          ),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context).folderNoScans, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).folderNoScansBody,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.text.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// Thumbnail for an artifact restored from Supabase, whose capture lives in the
/// private `captures` bucket.
///
/// The signed URL is resolved once in [initState] rather than from a
/// FutureBuilder in the grid's build method, which would mint a fresh one on
/// every keystroke in the search field.
class _StoredCapturePreview extends StatefulWidget {
  const _StoredCapturePreview({super.key, required this.artifact});

  final Artifact artifact;

  @override
  State<_StoredCapturePreview> createState() => _StoredCapturePreviewState();
}

class _StoredCapturePreviewState extends State<_StoredCapturePreview> {
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
    if (_resolving) return const ShimmerFill();
    if (_url == null) {
      return ArtifactCubeThumbnail(artifact: widget.artifact, size: 104);
    }
    // Keyed on the storage path, not the URL: the URL is a signed one that
    // expires hourly, so caching under it would re-download the same capture
    // every hour and strand the previous copy under a key nothing looks up.
    return NetImage(
      url: _url!,
      cacheKey: widget.artifact.photoUrl,
      fit: BoxFit.cover,
    );
  }
}

/// The tile for a recorded clip.
///
/// Deliberately not a still from the video: extracting one needs a
/// frame-grabbing dependency, and the first frame of a clip is a poor summary
/// of it anyway — a pan starts pointed at whatever the traveller happened to
/// be facing before they began. A drawn tile says "this is a video" more
/// reliably than a blurry frame would, and it cannot fail to load.
class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.artifact});

  final Artifact artifact;

  @override
  Widget build(BuildContext context) {
    final missing = artifact.isLocalFile && !File(artifact.photoUrl).existsSync();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.deepNavy, AppTheme.accentDark],
        ),
      ),
      child: Center(
        child: Icon(
          // A clip whose file has gone — the OS reclaimed it, or a reinstall
          // moved the container — says so rather than promising playback that
          // cannot happen.
          missing ? Icons.videocam_off_rounded : Icons.play_circle_fill_rounded,
          color: Colors.white.withValues(alpha: missing ? 0.4 : 0.85),
          size: 34,
        ),
      ),
    );
  }
}

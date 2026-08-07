import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/location.dart';
import '../../../services/media_cache.dart';
import '../../../theme.dart';
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
                              Center(child: _buildMediaPreview(art)),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: _buildBadge(art),
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
                                    ? (modelFailureMessages[art.errorCode] ?? 'Generation failed')
                                    : art.region,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: art.modelStatus == ModelStatus.failed
                                      ? Colors.redAccent
                                      : AppTheme.text.withOpacity(0.6),
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

  Widget _buildMediaPreview(Artifact art) {
    if (art.isLocalFile && File(art.photoUrl).existsSync()) {
      return Image.file(
        File(art.photoUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => ArtifactCubeThumbnail(artifact: art, size: 104),
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

  Widget _buildBadge(Artifact art) {
    if (art.modelStatus == ModelStatus.generating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.ink,
          borderRadius: AppTheme.brPill,
          boxShadow: AppTheme.shadowSm,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.sand),
            ),
            SizedBox(width: 6),
            Text(
              'Generating 3D…',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.sand),
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 12, color: Colors.white),
            SizedBox(width: 4),
            Text(
              '3D Failed',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
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
        child: const Text(
          '3D Model',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.onAccent),
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
          Text('No scans yet', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Complete scan and video tasks on your route to fill this folder.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.text.withOpacity(0.7)),
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
    return NetImage(url: _url!, fit: BoxFit.cover);
  }
}

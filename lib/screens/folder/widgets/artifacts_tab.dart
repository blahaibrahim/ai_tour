import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';
import '../../../widgets/pressable_scale.dart';
import '../../../widgets/staggered_entrance.dart';
import '../../../widgets/artifact_cube.dart';
import '../../artifact_viewer/artifact_viewer_screen.dart';

/// Grid tab showing captured and example artifacts.
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
                              Center(child: ArtifactCubeThumbnail(artifact: art, size: 104)),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
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
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(art.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(art.region, style: TextStyle(fontSize: 11, color: AppTheme.text.withOpacity(0.6)), maxLines: 1, overflow: TextOverflow.ellipsis),
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

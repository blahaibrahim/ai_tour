import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../models/location.dart';
import '../widgets/artifact_cube.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/staggered_entrance.dart';
import 'artifact_viewer_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Combine done tasks with example artifacts. state.tasks[i] always
    // corresponds to state.accepted[i] (both built from the same route in
    // order), so pair them by index rather than searching for a matching
    // Task instance — the tasks list holds fresh Task copies, not the same
    // objects as loc.task, so identity-based lookup would never match.
    final doneArtifacts = <Artifact>[
      for (var i = 0; i < state.tasks.length && i < state.accepted.length; i++)
        if (state.tasks[i].state == 'done')
          Artifact(
            id: state.accepted[i].id,
            name: state.accepted[i].name,
            region: state.accepted[i].region,
            kindLabel: state.tasks[i].type == 'video' ? 'Video' : 'Scan',
            photoUrl: state.accepted[i].artifactUrl,
          ),
    ];

    final allItems = [...state.capturedArtifacts, ...doneArtifacts, ...exampleArtifacts];
    
    final query = _searchController.text.toLowerCase();
    final filtered = allItems.where((a) => a.name.toLowerCase().contains(query)).toList();

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('FOLDER', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                  Text('Scanned artifacts', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23)),
                  const SizedBox(height: 16),
                  
                  // Search
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: AppTheme.brMd,
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search your scans',
                        prefixIcon: Icon(Icons.search, color: AppTheme.text.withOpacity(0.5)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          const Icon(Icons.photo_library_outlined, color: AppTheme.accent, size: 38),
                          const SizedBox(height: 12),
                          Text('No scans yet', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18)),
                          const SizedBox(height: 8),
                          Text(
                            'Complete scan and video tasks on your route to fill this folder.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppTheme.text.withOpacity(0.7)),
                          ),
                        ],
                      ),
                    )
                  else
                    GridView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final art = filtered[i];
                        return StaggeredEntrance(
                          index: i,
                          child: PressableScale(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ArtifactViewerScreen(artifact: art)),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: AppTheme.brLg,
                                boxShadow: AppTheme.shadowSm,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Container(color: AppTheme.surfaceAlt),
                                        Center(
                                          child: ArtifactCubeThumbnail(artifact: art, size: 104),
                                        ),
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
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

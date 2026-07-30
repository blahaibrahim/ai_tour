import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../models/location.dart';
import '../widgets/app_backdrop.dart';
import '../widgets/artifact_cube.dart';
import '../widgets/glass_surface.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/staggered_entrance.dart';
import 'artifact_viewer_screen.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  TextEditingController? _searchControllerInstance;
  TextEditingController? _savedSearchControllerInstance;

  TextEditingController get _searchController => _searchControllerInstance ??= TextEditingController();
  TextEditingController get _savedSearchController => _savedSearchControllerInstance ??= TextEditingController();

  @override
  void dispose() {
    _searchControllerInstance?.dispose();
    _savedSearchControllerInstance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Combine done tasks with example artifacts.
    final doneArtifacts = <Artifact>[
      for (var i = 0; i < state.tasks.length && i < state.accepted.length; i++)
        if (state.tasks[i].state == 'done')
          Artifact(
            id: state.accepted[i].id,
            name: state.accepted[i].name,
            region: state.accepted[i].region,
            kindLabel: switch (state.tasks[i].type) {
              'video' => 'Video',
              'mascot' => 'Fennec',
              _ => 'Scan',
            },
            photoUrl: state.accepted[i].artifactUrl,
          ),
    ];

    final allItems = [...state.capturedArtifacts, ...doneArtifacts, ...exampleArtifacts];
    
    final query = _searchController.text.toLowerCase();
    final filtered = allItems.where((a) => a.name.toLowerCase().contains(query)).toList();

    // Saved Locations
    final allSavedLocations = <Location>[];
    final allStateLocations = [...state.queue, ...state.accepted, ...state.rejected];
    for (var loc in allStateLocations) {
      if (state.savedLocationIds.contains(loc.id) && !allSavedLocations.any((l) => l.id == loc.id)) {
        allSavedLocations.add(loc);
      }
    }
    final savedQuery = _savedSearchController.text.toLowerCase();
    final savedLocations = allSavedLocations.where((loc) => loc.name.toLowerCase().contains(savedQuery) || loc.region.toLowerCase().contains(savedQuery)).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: AppBackdrop(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YOUR FOLDER', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.white70, fontWeight: FontWeight.bold)),
                    Text('Saved & Scanned', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 23, color: Colors.white)),
                    const SizedBox(height: 24),
                    const TabBar(
                      indicatorColor: AppTheme.sand,
                      labelColor: AppTheme.sand,
                      unselectedLabelColor: Colors.white70,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(icon: Icon(Icons.photo_library_outlined)),
                        Tab(icon: Icon(Icons.bookmark_border)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildArtifactsTab(filtered),
                    _buildSavedTab(savedLocations),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedTab(List<Location> savedLocations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: GlassSurface(
            borderRadius: AppTheme.brMd,
            child: TextField(
              controller: _savedSearchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search saved locations',
                prefixIcon: Icon(Icons.search, color: AppTheme.text.withOpacity(0.5)),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: savedLocations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border, size: 48, color: AppTheme.text.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text('No saved locations', style: TextStyle(color: AppTheme.text.withOpacity(0.6))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: savedLocations.length,
                  itemBuilder: (context, i) {
                    final loc = savedLocations[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassSurface(
                        borderRadius: AppTheme.brLg,
                        child: ListTile(
                          onTap: () => context.read<AppState>().openDetail(loc),
                          contentPadding: const EdgeInsets.all(12),
                          leading: ClipRRect(
                            borderRadius: AppTheme.brMd,
                            child: Image.network(loc.thumbUrl, width: 56, height: 56, fit: BoxFit.cover),
                          ),
                          title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(loc.region, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildArtifactsTab(List<Artifact> filtered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: GlassSurface(
            borderRadius: AppTheme.brMd,
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search your scans',
                prefixIcon: Icon(Icons.search, color: AppTheme.text.withOpacity(0.5)),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.deepNavy,
                        ),
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
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
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
                        child: GlassSurface(
                      borderRadius: AppTheme.brLg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
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
        ),
      ],
    );
  }
}

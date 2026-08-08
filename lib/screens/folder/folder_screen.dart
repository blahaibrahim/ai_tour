import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/app/app_bloc.dart';
import '../../models/location.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/glass_surface.dart';
import 'widgets/artifacts_tab.dart';
import 'widgets/saved_tab.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _savedSearchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _savedSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppBloc>().state;

    // Stops whose task is done but which produced no capture of their own —
    // a quiz or a task marked complete without the camera. Anything the user
    // actually captured is already in capturedArtifacts (and, since it is
    // persisted, survives a restart), so those ids are skipped here rather
    // than shown twice.
    final capturedIds = state.capturedArtifacts.map((a) => a.id).toSet();
    final doneArtifacts = <Artifact>[
      for (var i = 0; i < state.tasks.length && i < state.accepted.length; i++)
        if (state.tasks[i].state == 'done' &&
            !capturedIds.contains(state.accepted[i].id))
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

    final allItems = [...state.capturedArtifacts, ...doneArtifacts];
    final query = _searchController.text.toLowerCase();
    final filteredArtifacts = allItems.where((a) => a.name.toLowerCase().contains(query)).toList();

    // Saved Locations
    final allStateLocations = [...state.queue, ...state.accepted, ...state.rejected];
    final allSavedLocations = <Location>[];
    for (var loc in allStateLocations) {
      if (state.savedLocationIds.contains(loc.id) && !allSavedLocations.any((l) => l.id == loc.id)) {
        allSavedLocations.add(loc);
      }
    }
    final savedQuery = _savedSearchController.text.toLowerCase();
    final filteredSaved = allSavedLocations
        .where((loc) =>
            loc.name.toLowerCase().contains(savedQuery) ||
            loc.region.toLowerCase().contains(savedQuery))
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: AppBackdrop(
          variant: AppBackdropVariant.deep,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppTheme.space5, AppTheme.space4, AppTheme.space5, 16),
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
                    Column(
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
                                prefixIcon: Icon(Icons.search, color: AppTheme.text.withValues(alpha: 0.5)),
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
                        Expanded(child: ArtifactsTab(artifacts: filteredArtifacts)),
                      ],
                    ),
                    Column(
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
                                prefixIcon: Icon(Icons.search, color: AppTheme.text.withValues(alpha: 0.5)),
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
                        Expanded(child: SavedTab(locations: filteredSaved)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../../widgets/glass_surface.dart';

/// List tab showing saved locations in the Folder screen.
class SavedTab extends StatelessWidget {
  const SavedTab({super.key, required this.locations});

  final List<Location> locations;

  @override
  Widget build(BuildContext context) {
    return locations.isEmpty
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
            itemCount: locations.length,
            itemBuilder: (context, i) {
              final loc = locations[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassSurface(
                  borderRadius: AppTheme.brLg,
                  child: ListTile(
                    onTap: () => context.read<AppBloc>().add(OpenDetailEvent(loc)),
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
          );
  }
}

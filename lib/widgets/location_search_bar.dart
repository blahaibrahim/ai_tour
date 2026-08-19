
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../blocs/app/app_bloc.dart';
import '../blocs/app/app_event.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';
import '../utils/geojson_parser.dart';

class LocationSearchBar extends StatefulWidget {
  const LocationSearchBar({super.key});

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final SearchController _searchController = SearchController();
  List<WilayaPolygon> _lastResults = [];

  Future<void> _handleMyLocation(BuildContext context) async {
    final bloc = context.read<AppBloc>();

    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context).locationServicesDisabled)));
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(AppLocalizations.of(context).locationPermissionDenied)));
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)
                  .locationPermissionPermanentlyDenied)));
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).locationLocating)));
      }

      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      bloc.add(SetMapCenterEvent(LatLng(position.latitude, position.longitude)));
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains('MissingPluginException')) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context).locationRestartRequired)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context).genericError(e.toString()))));
        }
      }
    }
  }

  Future<List<WilayaPolygon>> _fetchPlaces(String query) async {
    final wilayas = await loadWilayasGeoJson();
    if (query.trim().isEmpty) return wilayas;

    final q = query.toLowerCase();
    _lastResults = wilayas.where((w) => w.name.toLowerCase().contains(q)).toList();
    return _lastResults;
  }

  void _onSubmitted(String query) async {
    _searchController.closeView(query);
    if (query.trim().isEmpty) return;

    final results = await _fetchPlaces(query);
    if (results.isNotEmpty && mounted) {
      final first = results.first;
      if (first.polygons.isNotEmpty && first.polygons.first.isNotEmpty) {
        final pt = first.polygons.first.first;
        context.read<AppBloc>().add(SetMapCenterEvent(pt));
        context.read<AppBloc>().add(SelectWilayaEvent(first.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      searchController: _searchController,
      viewBackgroundColor: AppTheme.bg,
      viewElevation: 0,
      headerHintStyle: TextStyle(color: AppTheme.text.withValues(alpha: 0.4), fontSize: 16),
      headerTextStyle: const TextStyle(color: AppTheme.text, fontSize: 16),
      dividerColor: AppTheme.divider,
      builder: (BuildContext context, SearchController controller) {
        return SearchBar(
          controller: controller,
          // SearchBar's own minimum is 56, which is a lot of height for one
          // line of text in a panel that has to hold four other controls
          // above the fold. Both bounds are pinned so it cannot grow back.
          constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
          padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.symmetric(horizontal: 12.0)),
          onTap: () => controller.openView(),
          onChanged: (_) => controller.openView(),
          onSubmitted: _onSubmitted,
          leading: const Icon(Icons.search, size: 19, color: AppTheme.text),
          hintText: AppLocalizations.of(context).searchWilayaHint,
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 14)),
          hintStyle: WidgetStatePropertyAll(
              TextStyle(color: AppTheme.text.withValues(alpha: 0.5), fontSize: 14)),
          backgroundColor: const WidgetStatePropertyAll(AppTheme.surface),
          elevation: const WidgetStatePropertyAll(2.0),
          side: const WidgetStatePropertyAll(BorderSide(color: AppTheme.divider, width: 1)),
        );
      },
      suggestionsBuilder: (BuildContext context, SearchController controller) async {
        // Read before the await: the suggestions are built after a network
        // round-trip, by which point this context may be gone.
        final l10n = AppLocalizations.of(context);
        final query = controller.text;
        final places = await _fetchPlaces(query);

        return [
          ListTile(
            leading: const Icon(Icons.my_location, color: AppTheme.accent),
            title: Text(l10n.searchMyLocation,
                style: const TextStyle(
                    color: AppTheme.accent, fontWeight: FontWeight.bold)),
            onTap: () {
              controller.closeView(controller.text);
              _handleMyLocation(context);
            },
          ),
          const Divider(height: 1),
          if (query.isNotEmpty && places.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(l10n.searchNoWilayas),
            ),
          ...places.map((place) {
            return ListTile(
              leading: const Icon(Icons.map_outlined, color: AppTheme.text),
              title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                controller.closeView(place.name);
                if (place.polygons.isNotEmpty && place.polygons.first.isNotEmpty) {
                  final pt = place.polygons.first.first;
                  context.read<AppBloc>().add(SetMapCenterEvent(pt));
                  // Auto select it too!
                  context.read<AppBloc>().add(SelectWilayaEvent(place.id));
                }
              },
            );
          }),
        ];
      },
    );
  }
}

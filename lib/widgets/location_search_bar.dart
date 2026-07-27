import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../state/app_state.dart';
import '../theme.dart';

class LocationSearchBar extends StatefulWidget {
  const LocationSearchBar({super.key});

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final SearchController _searchController = SearchController();
  String _lastQuery = '';
  List<Map<String, dynamic>> _lastResults = [];

  Future<void> _handleMyLocation(BuildContext context) async {
    final state = context.read<AppState>();
    
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services disabled.')));
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions denied.')));
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions permanently denied.')));
        return;
      } 

      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Locating...')));

      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      state.setMapCenter(LatLng(position.latitude, position.longitude));
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains('MissingPluginException')) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please completely STOP and restart flutter run to compile the GPS plugin!')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPlaces(String query) async {
    if (query.trim().length < 2) return [];
    
    // Simple debounce
    await Future.delayed(const Duration(milliseconds: 400));
    if (_searchController.text != query) return _lastResults; // Query changed while waiting

    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5');
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(url);
      request.headers.set('User-Agent', 'ai_tour_app');
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final List data = jsonDecode(jsonString);
        _lastResults = data.cast<Map<String, dynamic>>();
        return _lastResults;
      }
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      httpClient.close();
    }
    return _lastResults;
  }

  void _onSubmitted(String query) async {
    _searchController.closeView(query);
    if (query.trim().isEmpty) return;
    
    final results = await _fetchPlaces(query);
    if (results.isNotEmpty && mounted) {
      final first = results.first;
      final lat = double.tryParse(first['lat'].toString()) ?? 0.0;
      final lon = double.tryParse(first['lon'].toString()) ?? 0.0;
      context.read<AppState>().setMapCenter(LatLng(lat, lon));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      searchController: _searchController,
      builder: (BuildContext context, SearchController controller) {
        return SearchBar(
          controller: controller,
          padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.symmetric(horizontal: 16.0)),
          onTap: () => controller.openView(),
          onChanged: (_) => controller.openView(),
          onSubmitted: _onSubmitted,
          leading: const Icon(Icons.search, color: AppTheme.text),
          hintText: 'Search any location...',
          hintStyle: WidgetStatePropertyAll(TextStyle(color: AppTheme.text.withOpacity(0.5))),
          backgroundColor: const WidgetStatePropertyAll(AppTheme.surface),
          elevation: const WidgetStatePropertyAll(2.0),
        );
      },
      suggestionsBuilder: (BuildContext context, SearchController controller) async {
        final query = controller.text;
        
        List<Map<String, dynamic>> places = [];
        if (query.isNotEmpty) {
          places = await _fetchPlaces(query);
        }

        return [
          ListTile(
            leading: const Icon(Icons.my_location, color: AppTheme.accent),
            title: const Text('My location', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
            onTap: () {
              controller.closeView(controller.text);
              _handleMyLocation(context);
            },
          ),
          const Divider(height: 1),
          if (query.isNotEmpty && places.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Searching...'),
            ),
          ...places.map((place) {
            final name = place['display_name'] ?? 'Unknown location';
            return ListTile(
              leading: const Icon(Icons.place_outlined, color: AppTheme.text),
              title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                controller.closeView(name.split(',').first);
                final lat = double.tryParse(place['lat'].toString()) ?? 0.0;
                final lon = double.tryParse(place['lon'].toString()) ?? 0.0;
                context.read<AppState>().setMapCenter(LatLng(lat, lon));
              },
            );
          }),
        ];
      },
    );
  }
}

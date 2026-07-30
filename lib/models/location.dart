/// Domain models shared across the app.
///
/// Static seed data (allLocations, exampleArtifacts, regions) lives in
/// location_data.dart to keep this file focused on type definitions.

class Task {
  final String type;
  final String label;
  final String state; // 'pending' or 'done'
  final int points;

  const Task({
    required this.type,
    required this.label,
    this.state = 'pending',
    this.points = 30,
  });

  Task copyWith({
    String? type,
    String? label,
    String? state,
    int? points,
  }) {
    return Task(
      type: type ?? this.type,
      label: label ?? this.label,
      state: state ?? this.state,
      points: points ?? this.points,
    );
  }
}

class Location {
  final String id;
  final String name;
  final String region;
  final String category;
  final int distanceKm;
  final String blurb;
  final Task task;
  final double lat;
  final double lng;

  const Location({
    required this.id,
    required this.name,
    required this.region,
    required this.category,
    required this.distanceKm,
    required this.blurb,
    required this.task,
    required this.lat,
    required this.lng,
  });

  String get photoUrl => 'https://picsum.photos/seed/$id/640/900';
  String get thumbUrl => 'https://picsum.photos/seed/$id/120/120';
  String get artifactUrl => 'https://picsum.photos/seed/$id-artifact/300/300';
  String get overviewPhotoUrl => 'https://picsum.photos/seed/$id/640/420';
  String get detailPhotoUrl => 'https://picsum.photos/seed/$id/640/500';

  String distanceLabel(bool isMiles) {
    if (isMiles) {
      return '${(distanceKm * 0.621371).round()} mi';
    }
    return '${distanceKm.round()} km';
  }
}

class Artifact {
  final String id;
  final String name;
  final String region;
  final String kindLabel;
  final String photoUrl;
  final bool isLocalFile;

  const Artifact({
    required this.id,
    required this.name,
    required this.region,
    required this.kindLabel,
    required this.photoUrl,
    this.isLocalFile = false,
  });
}

/// Domain models shared across the app.
///
/// Static seed data (allLocations, exampleArtifacts, regions) lives in
/// location_data.dart to keep this file focused on type definitions.
library;

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

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      type: json['type'] as String? ?? 'photo',
      label: json['label'] as String? ?? '',
      points: (json['points'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'label': label,
      'points': points,
    };
  }
}

class Location {
  final String id;
  final String name;
  final String region;
  final String category;
  // distanceKm is a double from the API (was int in the static mock data)
  final double distanceKm;
  final String blurb;
  final Task task;
  final double lat;
  final double lng;
  // LLM-provided personalised reason for including this stop
  final String? reason;
  // Real photo URL from Supabase catalogue (null falls back to picsum)
  final String? remotePhotoUrl;
  // True when the photo is of the surrounding area rather than this place.
  // Most POIs have no photograph of their own, and a labelled picture of the
  // neighbourhood is more use than an empty placeholder — but it must be
  // labelled, or it is the same lie the old picsum fallback told.
  final bool photoIsStock;
  final String? photoStockNote;

  /// How long this stop is expected to take, from `pois.avg_visit_duration_minutes`.
  ///
  /// Carried on the Location and not just the RouteStop because the review
  /// step works in Locations, and it is what the budget gate counts: a
  /// traveller cannot be told whether they have kept enough of their day
  /// without knowing what each card costs.
  final int dwellMinutes;

  const Location({
    required this.id,
    required this.name,
    required this.region,
    required this.category,
    required this.distanceKm,
    required this.blurb,
    required this.task,
    this.dwellMinutes = 0,
    required this.lat,
    required this.lng,
    this.reason,
    this.remotePhotoUrl,
    this.photoIsStock = false,
    this.photoStockNote,
  });

  /// Constructs a Location from the JSON shape returned by POST /api/itinerary.
  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      region: json['region'] as String? ?? '',
      category: json['category'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      blurb: json['blurb'] as String? ?? '',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      reason: json['reason'] as String?,
      remotePhotoUrl: json['photo_url'] as String?,
      photoIsStock: json['photo_is_stock'] as bool? ?? false,
      photoStockNote: json['photo_stock_note'] as String?,
      task: Task(type: 'photo', label: 'Take a photo of this location.'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'region': region,
      'category': category,
      'distance_km': distanceKm,
      'blurb': blurb,
      'lat': lat,
      'lng': lng,
      'reason': reason,
      'photo_url': remotePhotoUrl,
      'photo_is_stock': photoIsStock,
      'photo_stock_note': photoStockNote,
    };
  }

  /// Whether the catalogue actually has a photo of this place.
  bool get hasPhoto => remotePhotoUrl != null && remotePhotoUrl!.isNotEmpty;

  /// Short label for the stock-image chip. Null when the photo really is of
  /// this place, or when there is no photo at all.
  String? get photoCredit =>
      (hasPhoto && photoIsStock) ? (photoStockNote ?? 'Nearby photo') : null;

  // These used to fall back to `picsum.photos/seed/$id`, which returns a real
  // photograph of somewhere else entirely — a stock image presented as if it
  // were the location. An empty string instead tells [NetImage] to draw the
  // branded placeholder, which is honest about there being no photo yet.
  String get photoUrl => remotePhotoUrl ?? '';
  String get thumbUrl => remotePhotoUrl ?? '';
  String get artifactUrl => remotePhotoUrl ?? '';
  String get overviewPhotoUrl => remotePhotoUrl ?? '';
  String get detailPhotoUrl => remotePhotoUrl ?? '';

  String distanceLabel(bool isMiles) {
    if (isMiles) {
      return '${(distanceKm * 0.621371).round()} mi';
    }
    return '${distanceKm.round()} km';
  }
}

/// Status of the 3D generation job associated with this artifact.
enum ModelStatus { generating, succeeded, failed }

/// Human-readable failure messages keyed by the backend's error_code.
const modelFailureMessages = {
  'no_subject': 'No clear object found — try a different angle',
  'timeout': 'Timed out — tap to retry',
  'gpu_oom': 'Server busy — tap to retry',
  'internal': 'Something went wrong — tap to retry',
};

class Artifact {
  final String id;
  final String name;
  final String region;
  final String kindLabel;
  final String photoUrl;
  final bool isLocalFile;
  // 3D model fields — null for photo/video/fennec artifacts
  final String? modelPath;       // Supabase storage key, e.g. models/{uid}/{id}.glb
  final ModelStatus? modelStatus;
  final String? jobId;
  final String? errorCode;       // Backend error code for specific failure messages
  /// `artifacts.captured_at` — set for anything rehydrated from Supabase, null
  /// for an artifact that only exists in this session so far. Orders the folder
  /// grid across sessions.
  final DateTime? capturedAt;

  const Artifact({
    required this.id,
    required this.name,
    required this.region,
    required this.kindLabel,
    required this.photoUrl,
    this.isLocalFile = false,
    this.modelPath,
    this.modelStatus,
    this.jobId,
    this.errorCode,
    this.capturedAt,
  });

  Artifact copyWith({
    String? id,
    String? name,
    String? region,
    String? kindLabel,
    String? photoUrl,
    bool? isLocalFile,
    String? modelPath,
    ModelStatus? modelStatus,
    String? jobId,
    String? errorCode,
    DateTime? capturedAt,
  }) {
    return Artifact(
      id: id ?? this.id,
      name: name ?? this.name,
      region: region ?? this.region,
      kindLabel: kindLabel ?? this.kindLabel,
      photoUrl: photoUrl ?? this.photoUrl,
      isLocalFile: isLocalFile ?? this.isLocalFile,
      modelPath: modelPath ?? this.modelPath,
      modelStatus: modelStatus ?? this.modelStatus,
      jobId: jobId ?? this.jobId,
      errorCode: errorCode ?? this.errorCode,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

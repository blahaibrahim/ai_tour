import 'package:latlong2/latlong.dart';

import '../services/api_client.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Thresholds for the hot/cold proximity bands.
class BandThresholds {
  const BandThresholds({
    this.coldMeters = 300,
    this.warmMeters = 150,
    this.hotMeters = 60,
    this.burningMeters = 25,
  });

  final double coldMeters;
  final double warmMeters;
  final double hotMeters;
  final double burningMeters;

  factory BandThresholds.fromJson(Map<String, dynamic> j) => BandThresholds(
        coldMeters: (j['cold_meters'] as num?)?.toDouble() ?? 300,
        warmMeters: (j['warm_meters'] as num?)?.toDouble() ?? 150,
        hotMeters: (j['hot_meters'] as num?)?.toDouble() ?? 60,
        burningMeters: (j['burning_meters'] as num?)?.toDouble() ?? 25,
      );
}

/// One mascot's asset metadata inside a manifest entry.
class MascotInfo {
  const MascotInfo({
    required this.id,
    required this.key,
    required this.name,
    required this.rarity,
    required this.modelGlbUrl,
    required this.modelUsdzUrl,
    required this.modelChecksum,
    required this.scaleMeters,
  });

  final String id;
  final String key;
  final String name;
  final String rarity;
  final String modelGlbUrl;
  final String modelUsdzUrl;
  final String modelChecksum;
  final double scaleMeters;

  factory MascotInfo.fromJson(Map<String, dynamic> j) => MascotInfo(
        id: j['id'] as String,
        key: j['key'] as String,
        name: j['name'] as String? ?? '',
        rarity: j['rarity'] as String? ?? 'common',
        modelGlbUrl: j['model_glb_url'] as String? ?? '',
        modelUsdzUrl: j['model_usdz_url'] as String? ?? '',
        modelChecksum: j['model_checksum'] as String? ?? '',
        scaleMeters: (j['scale_meters'] as num?)?.toDouble() ?? 0.6,
      );
}

/// One entry in a spawn manifest — the client caches these for the whole hunt.
class SpawnManifestEntry {
  const SpawnManifestEntry({
    required this.spawnId,
    required this.poiId,
    required this.location,
    required this.captureRadiusMeters,
    required this.hotRadiusMeters,
    required this.bandThresholds,
    required this.presentationDistanceMeters,
    required this.mascot,
  });

  final String spawnId;
  final String poiId;
  final LatLng location;
  final double captureRadiusMeters;
  final double hotRadiusMeters;
  final BandThresholds bandThresholds;
  final double presentationDistanceMeters;
  final MascotInfo mascot;

  factory SpawnManifestEntry.fromJson(Map<String, dynamic> j) =>
      SpawnManifestEntry(
        spawnId: j['spawn_id'] as String,
        poiId: j['poi_id'] as String,
        location: LatLng(
          (j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(),
        ),
        captureRadiusMeters:
            (j['capture_radius_meters'] as num?)?.toDouble() ?? 25,
        hotRadiusMeters: (j['hot_radius_meters'] as num?)?.toDouble() ?? 60,
        bandThresholds: BandThresholds.fromJson(
            (j['band_thresholds'] as Map<String, dynamic>?) ?? {}),
        presentationDistanceMeters:
            (j['presentation_distance_meters'] as num?)?.toDouble() ?? 4.0,
        mascot: MascotInfo.fromJson(
            (j['mascot'] as Map<String, dynamic>?) ?? {}),
      );
}

/// The full manifest for a route — all AR-enabled stops with their spawns.
class SpawnManifest {
  const SpawnManifest({required this.routeId, required this.spawns});

  final String routeId;
  final List<SpawnManifestEntry> spawns;

  factory SpawnManifest.fromJson(Map<String, dynamic> j) => SpawnManifest(
        routeId: j['route_id'] as String,
        spawns: (j['spawns'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SpawnManifestEntry.fromJson)
            .toList(),
      );
}

/// A signed capture token issued after the server verifies proximity.
class CaptureToken {
  const CaptureToken({required this.token, required this.expiresAt});

  final String token;
  final String expiresAt;

  factory CaptureToken.fromJson(Map<String, dynamic> j) => CaptureToken(
        token: j['capture_token'] as String,
        expiresAt: j['expires_at'] as String? ?? '',
      );
}

/// The server's verdict on a capture attempt.
class CaptureResult {
  const CaptureResult({
    required this.outcome,
    this.points,
    this.isFirstCatch = false,
  });

  final String outcome;
  final int? points;
  final bool isFirstCatch;

  bool get accepted => outcome == 'accepted';

  factory CaptureResult.fromJson(Map<String, dynamic> j) {
    final reward = j['reward'] as Map<String, dynamic>?;
    return CaptureResult(
      outcome: j['outcome'] as String? ?? 'unknown',
      points: (reward?['points'] as num?)?.toInt(),
      isFirstCatch: j['is_first_catch'] as bool? ?? false,
    );
  }
}

/// A user's mascot collection entry.
class CollectionEntry {
  const CollectionEntry({
    required this.mascotId,
    required this.firstCapturedAt,
    required this.captureCount,
  });

  final String mascotId;
  final String firstCapturedAt;
  final int captureCount;

  factory CollectionEntry.fromJson(Map<String, dynamic> j) => CollectionEntry(
        mascotId: j['mascot_id'] as String,
        firstCapturedAt: j['first_captured_at'] as String? ?? '',
        captureCount: (j['capture_count'] as num?)?.toInt() ?? 1,
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Client for the AR Capture module (Node backend).
///
/// Mirrors the six HTTP endpoints in `backend/server-node/src/routes/mascots.ts`:
///
///   POST /api/routes/:routeId/mascots/generate  → [generateManifest]
///   GET  /api/routes/:routeId/mascots           → [getManifest]
///   POST /api/mascots/:spawnId/proximity        → [issueProximityToken]
///   POST /api/mascots/:spawnId/capture          → [submitCapture]
///   GET  /api/collection                        → [getCollection]
///   POST /api/devices/push-token               → [registerPushToken]
class MascotRepository {
  const MascotRepository._();

  // -------------------------------------------------------------------------
  // Flow A — generate the spawn manifest when the hunt starts
  // -------------------------------------------------------------------------

  /// Generates (and persists) spawn points for every AR-enabled stop on
  /// [routeId]. Idempotent — repeated calls return the same spawns.
  static Future<SpawnManifest> generateManifest(String routeId) async {
    final data = await ApiClient.post(
      '/api/routes/$routeId/mascots/generate',
    );
    return SpawnManifest.fromJson(data);
  }

  /// Fetches an already-generated manifest without creating new spawns.
  static Future<SpawnManifest> getManifest(String routeId) async {
    final data = await ApiClient.get('/api/routes/$routeId/mascots');
    return SpawnManifest.fromJson(data);
  }

  // -------------------------------------------------------------------------
  // Flow C — proximity check → signed token → submit capture
  // -------------------------------------------------------------------------

  /// Reports a verified proximity fix to the server and gets back a short-lived
  /// signed token that authorises the capture attempt.
  ///
  /// [spawnId] — the spawn being approached.
  /// [fix] — the device's current GPS position.
  /// [accuracyMeters] — GPS accuracy (σ), forwarded to the validator.
  static Future<CaptureToken> issueProximityToken({
    required String spawnId,
    required LatLng fix,
    required double accuracyMeters,
  }) async {
    final data = await ApiClient.post(
      '/api/mascots/$spawnId/proximity',
      body: {
        'fix': {'lat': fix.latitude, 'lng': fix.longitude},
        'accuracy_meters': accuracyMeters,
      },
    );
    return CaptureToken.fromJson(data);
  }

  /// Submits a capture attempt and gets back the server's verdict.
  ///
  /// [captureToken] — the short-lived token from [issueProximityToken].
  /// [nonce] — a UUID generated by the client for idempotency. The same nonce
  ///   may be sent multiple times (offline outbox replay); the server deduplicates.
  static Future<CaptureResult> submitCapture({
    required String spawnId,
    required String captureToken,
    required LatLng fix,
    required double accuracyMeters,
    required String clientTs,
    required String nonce,
    Map<String, dynamic> arTelemetry = const {},
    bool isOfflineReplay = false,
  }) async {
    final data = await ApiClient.post(
      '/api/mascots/$spawnId/capture',
      body: {
        'capture_token': captureToken,
        'fix': {'lat': fix.latitude, 'lng': fix.longitude},
        'accuracy_meters': accuracyMeters,
        'client_ts': clientTs,
        'nonce': nonce,
        'ar_telemetry': arTelemetry,
        'is_offline_replay': isOfflineReplay,
      },
    );
    return CaptureResult.fromJson(data);
  }

  // -------------------------------------------------------------------------
  // Collection
  // -------------------------------------------------------------------------

  static Future<List<CollectionEntry>> getCollection() async {
    final data = await ApiClient.get('/api/collection');
    return (data['collection'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CollectionEntry.fromJson)
        .toList();
  }

  // -------------------------------------------------------------------------
  // Device push token
  // -------------------------------------------------------------------------

  /// Registers or refreshes a push notification token.
  ///
  /// [platform] must be `'android'`, `'ios'`, or `'web'`.
  /// [arCapability] is optional telemetry: `'full'`, `'limited'`, or `'none'`.
  static Future<void> registerPushToken({
    required String token,
    required String platform,
    String? arCapability,
  }) async {
    await ApiClient.post('/api/devices/push-token', body: {
      'token': token,
      'platform': platform,
      if (arCapability != null) 'ar_capability': arCapability,
    });
  }
}

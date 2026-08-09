import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../ar/hunt_session_controller.dart';
import '../../ar/proximity.dart';
import '../../repositories/mascot_repository.dart'
    hide BandThresholds; // use proximity.dart's BandThresholds with the controller
import '../../services/api_client.dart';
import '../../services/heading_service.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pressable_scale.dart';
import 'ar_hunt_screen.dart';

/// C1 — the proximity hunt screen: a compass ring pointing toward the mascot
/// and a thermometer showing how hot the hunt is, per Figure 2 / §8 ("Hot/cold
/// proximity hunt") of the AR capture plan.
///
/// Pure presentation. All distance math and band state live in
/// [HuntSessionController] (C2); this screen only renders what it streams and
/// unlocks the camera once [HuntState.canCapture] is true.
class HuntRadarScreen extends StatefulWidget {
  const HuntRadarScreen({
    super.key,
    required this.spawnLocation,
    this.stopName,
    this.isTestSpawn = false,
    this.routeId,
    this.poiId,
  });

  /// Where the mascot is hiding. When [routeId] + [poiId] are provided this
  /// is replaced by the real spawn location from the backend manifest.
  final LatLng spawnLocation;

  /// Name of the stop being explored, shown in the header.
  final String? stopName;

  /// True when [spawnLocation] was generated near the tester's own position
  /// rather than a real POI — shown as a banner so testing mode is never
  /// mistaken for the real hunt.
  final bool isTestSpawn;

  /// When set together with [poiId], generates the real spawn manifest from
  /// the backend and uses the server's spawn location + band thresholds.
  final String? routeId;

  /// The POI id for the stop being hunted — used to look up the correct spawn
  /// entry in the manifest when [routeId] is set.
  final String? poiId;

  @override
  State<HuntRadarScreen> createState() => _HuntRadarScreenState();
}

class _HuntRadarScreenState extends State<HuntRadarScreen> {
  late HuntSessionController _hunt;
  StreamSubscription<HuntState>? _huntSub;
  StreamSubscription<double>? _headingSub;
  Timer? _pulseTimer;

  HuntAvailability? _availability;
  HuntState? _state;
  double? _heading;

  // --- real-mode spawn data -----------------------------------------------
  /// The spawn entry fetched from the backend (null in test mode or before load).
  SpawnManifestEntry? _spawnEntry;
  bool _spawnLoading = false;

  /// Signed proximity token, set once the device enters the burning band.
  CaptureToken? _captureToken;
  bool _tokenRequested = false;

  @override
  void initState() {
    super.initState();
    _hunt = HuntSessionController(target: widget.spawnLocation);
    _headingSub = HeadingService.radiansStream.listen((heading) {
      if (mounted) setState(() => _heading = heading);
    });
    // Fetch real spawn manifest from backend if routeId + poiId are provided.
    if (!widget.isTestSpawn &&
        widget.routeId != null &&
        widget.poiId != null) {
      _loadSpawnManifest();
    } else {
      _start();
    }
  }

  /// Fetches the spawn manifest and restarts the hunt controller targeting
  /// the server's real spawn location.
  Future<void> _loadSpawnManifest() async {
    if (!mounted) return;
    setState(() {
      _spawnLoading = true;
    });
    try {
      final manifest =
          await MascotRepository.generateManifest(widget.routeId!);
      final entry = manifest.spawns
          .where((s) => s.poiId == widget.poiId)
          .firstOrNull;
      if (!mounted) return;
      if (entry == null) {
        // No AR content for this stop — fall back to test/stop location.
        setState(() {
          _spawnLoading = false;
        });
        _start();
        return;
      }
      // Restart the hunt controller with the real spawn location + thresholds.
      _hunt.dispose();
      _hunt = HuntSessionController(
        target: entry.location,
        thresholds: BandThresholds(
          coldMeters: entry.bandThresholds.coldMeters,
          warmMeters: entry.bandThresholds.warmMeters,
          hotMeters: entry.bandThresholds.hotMeters,
          burningMeters: entry.bandThresholds.burningMeters,
        ),
      );
      setState(() {
        _spawnEntry = entry;
        _spawnLoading = false;
      });
      _start();
    } on ApiException catch (_) {
      if (!mounted) return;
      setState(() {
        _spawnLoading = false;
      });
      // Fall back to the stop's real location.
      _start();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _spawnLoading = false;
      });
      _start();
    }
  }

  Future<void> _start() async {
    final availability = await _hunt.start();
    if (!mounted) return;
    setState(() => _availability = availability);
    if (availability == HuntAvailability.ready) {
      _huntSub = _hunt.stream.listen(_onHuntState);
    }
  }

  void _onHuntState(HuntState state) {
    final previousBand = _state?.band;
    setState(() => _state = state);
    if (previousBand != state.band) {
      HapticFeedback.mediumImpact();
      _restartPulse(state.band);
    }
    // When the device first enters the burning band, issue a proximity token
    // so the capture screen has it ready.
    if (state.band == ProximityBand.burning &&
        !_tokenRequested &&
        _spawnEntry != null) {
      _requestProximityToken(state);
    }
  }

  Future<void> _requestProximityToken(HuntState huntState) async {
    if (_tokenRequested) return;
    _tokenRequested = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 4));
      final token = await MascotRepository.issueProximityToken(
        spawnId: _spawnEntry!.spawnId,
        fix: LatLng(pos.latitude, pos.longitude),
        accuracyMeters: pos.accuracy,
      );
      if (mounted) setState(() => _captureToken = token);
    } catch (_) {
      // Non-fatal: the capture screen will fall back to re-issuing or
      // the server will handle the missing token.
      _tokenRequested = false;
    }
  }

  /// Haptic pulse rate escalates with the band, per §5.3's feedback table —
  /// the same cadence a real device would drive the UI's shimmer/pulse from.
  void _restartPulse(ProximityBand band) {
    _pulseTimer?.cancel();
    final interval = _pulseInterval(band);
    if (interval == null) return;
    _pulseTimer = Timer.periodic(interval, (_) => HapticFeedback.lightImpact());
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _huntSub?.cancel();
    _headingSub?.cancel();
    _hunt.dispose();
    super.dispose();
  }

  void _openCamera() {
    final entry = _spawnEntry;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArHuntScreen(
          stopName: widget.stopName,
          spawnLocation: entry?.location ?? widget.spawnLocation,
          spawnId: entry?.spawnId,
          captureToken: _captureToken?.token,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepNavy,
      body: AppBackdrop(
        variant: AppBackdropVariant.deep,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          PressableScale(
            onTap: () => Navigator.of(context).pop(),
            child: GlassSurface(
              tint: GlassTint.dark,
              borderRadius: AppTheme.brPill,
              padding: const EdgeInsets.all(11),
              child: const Icon(Icons.close, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassSurface(
              tint: GlassTint.dark,
              borderRadius: AppTheme.brPill,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Find the fennec',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.isTestSpawn
                        ? 'Testing mode — hunting near you'
                        : widget.stopName ?? 'Somewhere nearby',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Show loading while fetching the real spawn manifest.
    if (_spawnLoading) {
      return const _CenteredMessage(
        icon: Icons.explore_outlined,
        message: 'Loading AR data…',
        showSpinner: true,
      );
    }
    switch (_availability) {
      case null:
        return const _CenteredMessage(
          icon: Icons.explore_outlined,
          message: 'Finding your position…',
          showSpinner: true,
        );
      case HuntAvailability.serviceDisabled:
        return _CenteredMessage(
          icon: Icons.location_off_outlined,
          message: 'Turn on location services to start the hunt.',
          action: ('Try again', _start),
        );
      case HuntAvailability.permissionDenied:
        return _CenteredMessage(
          icon: Icons.location_off_outlined,
          message: 'The hunt needs your location to guide you to the fennec.',
          action: ('Allow location', _start),
        );
      case HuntAvailability.permissionDeniedForever:
        return _CenteredMessage(
          icon: Icons.location_off_outlined,
          message: 'Location is turned off for this app. Enable it in Settings to hunt.',
          action: ('Open settings', openAppSettings),
        );
      case HuntAvailability.ready:
        final state = _state;
        if (state == null) {
          return const _CenteredMessage(
            icon: Icons.explore_outlined,
            message: 'Getting a fix on your position…',
            showSpinner: true,
          );
        }
        return _buildRadar(context, state);
    }
  }

  Widget _buildRadar(BuildContext context, HuntState state) {
    final heading = _heading;
    final color = _bandColor(state.band);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isTestSpawn) _buildTestBanner(),
        const Spacer(),
        _CompassRing(
          band: state.band,
          // Radians clockwise from "straight ahead of the phone" — the same
          // yaw formula the AR placement step uses (§5.5).
          screenAngle: heading == null ? null : state.bearingRadians - heading,
        ),
        const SizedBox(height: 22),
        Text(
          _bandLabel(state.band),
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _bandHint(state.band),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Text(
          _distanceLabel(state.distanceMeters),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _Thermometer(band: state.band),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: _CameraCta(enabled: state.canCapture, onTap: _openCamera),
        ),
      ],
    );
  }

  Widget _buildTestBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: GlassSurface(
        tint: GlassTint.dark,
        borderRadius: AppTheme.brPill,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_outlined, size: 15, color: AppTheme.sand),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'A mascot was spawned near your current location so you can '
                'test the hunt without visiting a real stop.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _distanceLabel(double meters) {
  if (meters < 1) return 'Right under your nose';
  if (meters < 1000) return '${meters.round()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

String _bandLabel(ProximityBand band) => switch (band) {
      ProximityBand.frozen => 'Ice cold',
      ProximityBand.cold => 'Cold',
      ProximityBand.warm => 'Getting warmer',
      ProximityBand.hot => 'Hot!',
      ProximityBand.burning => "It's right here!",
    };

String _bandHint(ProximityBand band) => switch (band) {
      ProximityBand.frozen => 'Somewhere out there — follow the arrow',
      ProximityBand.cold => 'Keep exploring in that direction',
      ProximityBand.warm => "You're on the right track",
      ProximityBand.hot => 'So close now — a few more steps',
      ProximityBand.burning => 'Open the camera to catch it',
    };

Color _bandColor(ProximityBand band) => switch (band) {
      ProximityBand.frozen => const Color(0xFF7C89A6),
      ProximityBand.cold => AppTheme.compassBlue,
      ProximityBand.warm => AppTheme.amber,
      ProximityBand.hot => const Color(0xFFE8703A),
      ProximityBand.burning => const Color(0xFFE0503D),
    };

/// Pulse cadence per band — §5.3's feedback table. Null means no pulse
/// (FROZEN).
Duration? _pulseInterval(ProximityBand band) => switch (band) {
      ProximityBand.frozen => null,
      ProximityBand.cold => const Duration(milliseconds: 1200),
      ProximityBand.warm => const Duration(milliseconds: 800),
      ProximityBand.hot => const Duration(milliseconds: 400),
      ProximityBand.burning => const Duration(milliseconds: 120),
    };

/// Ring with an arrow pointing toward the mascot, relative to the phone's own
/// facing direction. Falls back to a static compass glyph when there's no
/// heading yet (compass unsupported, or not calibrated in time).
class _CompassRing extends StatelessWidget {
  const _CompassRing({required this.band, required this.screenAngle});

  final ProximityBand band;
  final double? screenAngle;

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(band);
    final angle = screenAngle;

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
            ),
          ),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
            ),
          ),
          if (angle != null)
            Transform.rotate(
              angle: angle,
              child: Icon(Icons.navigation_rounded, color: color, size: 56),
            )
          else
            Icon(Icons.explore_outlined, color: color.withValues(alpha: 0.8), size: 48),
        ],
      ),
    );
  }
}

/// Five segments, filled up to the current band — the same colour language as
/// the overview screen's per-stop progress track.
class _Thermometer extends StatelessWidget {
  const _Thermometer({required this.band});

  final ProximityBand band;

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(band);
    return Row(
      children: [
        for (final b in ProximityBand.values) ...[
          if (b != ProximityBand.values.first) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: AppTheme.motionBase,
              height: 6,
              decoration: BoxDecoration(
                color: b.index <= band.index ? color : Colors.white.withValues(alpha: 0.18),
                borderRadius: AppTheme.brPill,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CameraCta extends StatelessWidget {
  const _CameraCta({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? AppTheme.accent : Colors.white24,
          borderRadius: AppTheme.brLg,
          boxShadow: enabled ? AppTheme.shadowLg : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_rounded,
              color: enabled ? AppTheme.onAccent : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              enabled ? 'Open camera' : 'Get closer to unlock the camera',
              style: TextStyle(
                color: enabled ? AppTheme.onAccent : Colors.white54,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.showSpinner = false,
    this.action,
  });

  final IconData icon;
  final String message;
  final bool showSpinner;
  final (String, FutureOr<void> Function())? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: CircularProgressIndicator(color: AppTheme.sand),
              )
            else
              Icon(icon, color: Colors.white54, size: 34),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => action.$2(),
                child: Text(action.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

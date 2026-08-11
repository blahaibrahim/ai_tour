import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../ar/hunt_session_controller.dart';
import '../../../ar/proximity.dart';
import '../../../repositories/mascot_repository.dart'
    hide BandThresholds; // use proximity.dart's BandThresholds with the controller
import '../../../services/api_client.dart';
import '../../../services/heading_service.dart';
import '../../../services/notification_service.dart';
import '../../../theme.dart';
import '../../../widgets/pressable_scale.dart';
import '../../ar_hunt/ar_hunt_screen.dart';

/// C1 — the proximity hunt, rendered inline inside the current-task card
/// instead of on a screen of its own: a small compass dial pointing toward the
/// mascot plus a hot/cold thermometer, per Figure 2 / §8 ("Hot/cold proximity
/// hunt") of the AR capture plan.
///
/// Pure presentation. All distance math and band state live in
/// [HuntSessionController] (C2); this widget only renders what it streams and
/// unlocks the camera once [HuntState.canCapture] is true.
class InlineMascotHunt extends StatefulWidget {
  const InlineMascotHunt({
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

  /// Name of the stop being explored, forwarded to the capture screen.
  final String? stopName;

  /// True when [spawnLocation] was generated near the tester's own position
  /// rather than a real POI — shown as a note so testing mode is never
  /// mistaken for the real hunt.
  final bool isTestSpawn;

  /// When set together with [poiId], generates the real spawn manifest from
  /// the backend and uses the server's spawn location + band thresholds.
  final String? routeId;

  /// The POI id for the stop being hunted — used to look up the correct spawn
  /// entry in the manifest when [routeId] is set.
  final String? poiId;

  @override
  State<InlineMascotHunt> createState() => _InlineMascotHuntState();
}

class _InlineMascotHuntState extends State<InlineMascotHunt> {
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
    // Subscribe before starting: the controller's seed fix lands during
    // start(), and a broadcast stream drops events that arrive with no
    // listener attached.
    _huntSub?.cancel();
    _huntSub = _hunt.stream.listen(_onHuntState);

    final availability = await _hunt.start();
    if (!mounted) return;
    setState(() => _availability = availability);
    if (availability != HuntAvailability.ready) {
      _huntSub?.cancel();
      _huntSub = null;
    }
  }

  void _onHuntState(HuntState state) {
    final previousBand = _state?.band;
    setState(() => _state = state);
    if (previousBand != state.band) {
      HapticFeedback.mediumImpact();
      _restartPulse(state.band);
      _notifyBandChange(previousBand, state.band);
    }
    // When the device first enters the burning band, issue a proximity token
    // so the capture screen has it ready.
    if (state.band == ProximityBand.burning &&
        !_tokenRequested &&
        _spawnEntry != null) {
      _requestProximityToken(state);
    }
  }

  /// Trigger 3 — "you're getting warm", while the app is not being looked at.
  ///
  /// Fires on the way *up* into HOT and BURNING only: §5.3's two guards
  /// (hysteresis plus a two-fix debounce) already live in [HuntBandTracker], so
  /// by the time a change reaches here it is a real one — but a traveller
  /// walking away and back would still be told twice without the direction
  /// check, and the fifteen-minute cooldown in [NotificationPolicy] is what
  /// covers the rest.
  ///
  /// Deliberately a *local* notification and not a push: docs/mascot_plan.md
  /// §5.6 rules FCM out for proximity, because a server can only know the
  /// traveller is close if the traveller's live position is streamed to it.
  /// Everything needed to make this decision is already on the device.
  void _notifyBandChange(ProximityBand? previous, ProximityBand current) {
    if (current != ProximityBand.hot && current != ProximityBand.burning) return;
    if (previous != null && previous.index >= current.index) return;

    // In test mode the spawn is a synthetic point near the tester, with no
    // server spawn id to hang a cooldown off; the stop name keeps two
    // different test spawns from sharing one.
    final subject = _spawnEntry?.spawnId ??
        'test-${widget.stopName ?? widget.spawnLocation.hashCode}';

    NotificationService.instance.showMascotNearby(
      spawnId: subject,
      canCapture: current == ProximityBand.burning,
      stopName: widget.stopName,
    );
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
    return AnimatedSize(
      duration: AppTheme.motionBase,
      curve: AppTheme.motionCurve,
      alignment: Alignment.topCenter,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Show loading while fetching the real spawn manifest.
    if (_spawnLoading) {
      return const _HuntNote(message: 'Loading AR data…', showSpinner: true);
    }
    switch (_availability) {
      case null:
        return const _HuntNote(
          message: 'Finding your position…',
          showSpinner: true,
        );
      case HuntAvailability.serviceDisabled:
        return _HuntNote(
          icon: Icons.location_off_outlined,
          message: 'Turn on location services to start the hunt.',
          action: ('Try again', _start),
        );
      case HuntAvailability.permissionDenied:
        return _HuntNote(
          icon: Icons.location_off_outlined,
          message: 'The hunt needs your location to guide you to the fennec.',
          action: ('Allow', _start),
        );
      case HuntAvailability.permissionDeniedForever:
        return _HuntNote(
          icon: Icons.location_off_outlined,
          message: 'Location is turned off for this app. Enable it in Settings to hunt.',
          action: ('Settings', openAppSettings),
        );
      case HuntAvailability.ready:
        final state = _state;
        if (state == null) {
          return const _HuntNote(
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

    return _HuntShell(
      band: state.band,
      children: [
        Row(
          children: [
            _CompassDial(
              band: state.band,
              // Radians clockwise from "straight ahead of the phone" — the same
              // yaw formula the AR placement step uses (§5.5).
              screenAngle: heading == null ? null : state.bearingRadians - heading,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _bandLabel(state.band),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _distanceLabel(state.distanceMeters) +
                            _accuracyNote(state.accuracyMeters),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _bandHint(state.band),
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.25,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Thermometer(band: state.band),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _CameraCta(enabled: state.canCapture, onTap: _openCamera),
        if (widget.isTestSpawn) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 13, color: AppTheme.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Testing mode — this fennec was spawned near you, not at the stop.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.text.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _distanceLabel(double meters) {
  if (meters < 1) return 'Right under your nose';
  if (meters < 1000) return '${meters.round()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

/// Appended to the distance once the fix is loose enough that walking a few
/// metres won't visibly move the number — otherwise a noisy GPS reads as a
/// broken tracker.
String _accuracyNote(double accuracyMeters) =>
    accuracyMeters > 15 ? ' ±${accuracyMeters.round()} m' : '';

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
      ProximityBand.frozen => const Color(0xFF6E7A93),
      ProximityBand.cold => AppTheme.compassBlue,
      // Darker than the full-screen hunt's amber/orange — these sit on cream,
      // not navy, and have to carry label text at 14 px.
      ProximityBand.warm => const Color(0xFFB57118),
      ProximityBand.hot => const Color(0xFFD1541F),
      ProximityBand.burning => const Color(0xFFC8452F),
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

/// Tinted well the hunt sits in, so it reads as one unit inside the task card
/// and its temperature is legible at a glance from the fill alone.
class _HuntShell extends StatelessWidget {
  const _HuntShell({required this.children, this.band});

  final List<Widget> children;
  final ProximityBand? band;

  @override
  Widget build(BuildContext context) {
    final color = band == null ? AppTheme.textSecondary : _bandColor(band!);
    return AnimatedContainer(
      duration: AppTheme.motionBase,
      curve: AppTheme.motionCurve,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppTheme.brMd,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Dial with an arrow pointing toward the mascot, relative to the phone's own
/// facing direction. Falls back to a static compass glyph when there's no
/// heading yet (compass unsupported, or not calibrated in time). The
/// full-screen version's 220 px ring, shrunk to fit the task card.
class _CompassDial extends StatelessWidget {
  const _CompassDial({required this.band, required this.screenAngle});

  final ProximityBand band;
  final double? screenAngle;

  static const double _size = 60;

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(band);
    final angle = screenAngle;

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: AppTheme.motionBase,
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
            ),
          ),
          AnimatedContainer(
            duration: AppTheme.motionBase,
            width: 41,
            height: 41,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
            ),
          ),
          if (angle != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: angle, end: angle),
              duration: AppTheme.motionFast,
              builder: (_, value, child) =>
                  Transform.rotate(angle: value, child: child),
              child: Icon(Icons.navigation_rounded, color: color, size: 24),
            )
          else
            Icon(Icons.explore_outlined,
                color: color.withValues(alpha: 0.8), size: 22),
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
          if (b != ProximityBand.values.first) const SizedBox(width: 3),
          Expanded(
            child: AnimatedContainer(
              duration: AppTheme.motionBase,
              height: 5,
              decoration: BoxDecoration(
                color: b.index <= band.index
                    ? color
                    : AppTheme.ink.withValues(alpha: 0.10),
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
        duration: AppTheme.motionBase,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? AppTheme.accent : AppTheme.ink.withValues(alpha: 0.06),
          borderRadius: AppTheme.brSm,
          boxShadow: enabled ? AppTheme.shadowSm : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_rounded,
              color: enabled ? AppTheme.onAccent : AppTheme.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              enabled ? 'Open camera' : 'Get closer to unlock the camera',
              style: TextStyle(
                color: enabled ? AppTheme.onAccent : AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The loading / permission states, in the same well as the hunt itself so the
/// card doesn't jump when the first fix lands.
class _HuntNote extends StatelessWidget {
  const _HuntNote({
    required this.message,
    this.icon,
    this.showSpinner = false,
    this.action,
  });

  final String message;
  final IconData? icon;
  final bool showSpinner;
  final (String, FutureOr<void> Function())? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return _HuntShell(
      children: [
        Row(
          children: [
            if (showSpinner)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.textSecondary,
                ),
              )
            else
              Icon(icon ?? Icons.explore_outlined,
                  size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, color: AppTheme.text),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => action.$2(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action.$1, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

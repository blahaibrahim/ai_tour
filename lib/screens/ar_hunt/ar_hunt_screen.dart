import 'dart:async';
import 'dart:io';

import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:video_player/video_player.dart';

import '../../ar/ar_session_host.dart';
import '../../ar/geo_math.dart';
import '../../ar/glb_bounds.dart';
import '../../ar/mascot_placement.dart';
import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../models/location.dart';
import '../../repositories/mascot_repository.dart';
import '../../services/heading_service.dart';
import '../../services/object_detector.dart';
import '../../theme.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/artifact_naming.dart';
import '../../utils/uuid.dart';
import '../../widgets/camera_mode_selector.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/pressable_scale.dart';

/// What the camera screen is for.
enum ArCameraMode {
  /// Find the fennec hidden in the room, then photograph it.
  hunt,

  /// Plain capture: the same camera, chrome and shutter, no mascot. Used by
  /// the camera button in the nav bar.
  capture,
}

/// What the shutter does in [ArCameraMode.capture], swiped between above the
/// shutter itself — see [CameraModeSelector].
///
/// The two are the same shot taken for different reasons, which is why they
/// share one camera rather than sitting behind separate buttons: [media] keeps
/// what you shot, [scan] sends it off to be rebuilt as a 3D model and only
/// accepts frames with a real object in them.
enum CaptureMode {
  /// Tap for a photo, hold to film. One mode rather than two because it is the
  /// same decision made at the moment of pressing — every phone camera people
  /// already own works this way, so the hold is discovered rather than taught,
  /// and a moment worth filming rarely announces itself far enough ahead to
  /// swipe modes first.
  media,
  scan;

  /// Name shown in the mode strip.
  String label(AppLocalizations l10n) =>
      this == CaptureMode.media ? l10n.arModeMedia : l10n.arModeScan;
}

/// What the camera has been opened *for*.
///
/// A quest asks for a specific thing, and the camera should only be able to
/// produce that thing — a video quest answered with a photo is not answered.
/// Rather than let the capture happen and reject it afterwards, the modes that
/// cannot satisfy the quest are simply not offered: there is nothing to undo
/// and nothing to explain.
enum CaptureIntent {
  /// The nav-bar camera. Every mode available, nothing required.
  free,

  /// A photo quest. Filming is off; the mode strip is hidden.
  photo,

  /// A video quest. Tapping does not shoot, and a clip must reach
  /// [_kMinQuestClip] before it counts.
  video;

  bool get isQuest => this != CaptureIntent.free;
}

/// Long enough that a slow tap is not a one-frame video, short enough that
/// deliberately holding to film feels immediate.
const Duration _kHoldToFilmDelay = Duration(milliseconds: 260);

/// The floor for a clip that answers a video quest.
///
/// Three seconds is short enough not to be a chore and long enough to rule out
/// the thing it exists to rule out: a flick of the wrist that technically
/// produces a video file. A quest asking for a clip of a place should get a
/// clip of a place.
const Duration _kMinQuestClip = Duration(seconds: 3);

/// The floor for any other clip — long enough only to tell a deliberate hold
/// from a tap the gesture recogniser rounded the wrong way.
const Duration _kMinFreeClip = Duration(milliseconds: 700);

/// Hard stop on a single clip. Long videos are large files on a device that is
/// also holding un-uploaded captures, and nothing downstream streams them.
const Duration _kMaxClipDuration = Duration(seconds: 30);

/// The camera half of the mascot hunt, on ARCore/ARKit world tracking.
///
/// The session tracks the phone with six degrees of freedom, so the fennec is
/// anchored to a real point in the room: walk around it and you see its flank,
/// step closer and it grows.
///
/// The mascot appears on its own at a fixed spot — no tapping to place it —
/// because the real placement will come from the backend. [MascotSpot] is the
/// seam that will take it.
///
/// In [ArCameraMode.capture] the whole mascot half sits out and this is simply
/// the app's camera — same viewfinder and shutter, so a photo taken from the
/// nav bar lands in the folder exactly like one taken on a hunt.
class ArHuntScreen extends StatefulWidget {
  const ArHuntScreen({
    super.key,
    this.stopName,
    this.spot = const MascotSpot(),
    this.mode = ArCameraMode.hunt,
    this.intent = CaptureIntent.free,
    this.spawnLocation,
    this.spawnId,
    this.captureToken,
  });

  /// Name of the stop being explored, shown in the header.
  final String? stopName;

  /// Where the mascot is hiding when there is no real-world geometry to place
  /// it from — either [spawnLocation] is null, or the GPS fix / compass
  /// heading needed to resolve it never arrived in time.
  final MascotSpot spot;

  /// Whether to run the hunt or just take a photo.
  final ArCameraMode mode;

  /// What this camera has been opened for. See [CaptureIntent].
  final CaptureIntent intent;

  /// The mascot's real geographic spawn point, from the proximity hunt
  /// (`InlineMascotHunt`) that led here. When set, [spot] is replaced at
  /// session start by the true bearing to this point combined with the
  /// device's heading — §5.5's bearing-preserving placement — rather than the
  /// fixed default.
  final LatLng? spawnLocation;

  /// The backend spawn id, forwarded from the inline hunt when a real
  /// manifest was loaded. Used to submit the capture after the mascot is caught.
  final String? spawnId;

  /// A short-lived signed capture token, pre-fetched when the device entered
  /// the burning proximity band. May be null if proximity-gating was skipped
  /// (test mode, network error, etc.) — in that case the capture screen will
  /// skip the server submission gracefully.
  final String? captureToken;

  @override
  State<ArHuntScreen> createState() => _ArHuntScreenState();
}

enum _Stage {
  /// Waiting for the AR session to map enough of the room to find a surface.
  scanning,

  /// Working out the floor height and dropping the mascot onto it.
  placing,

  /// The mascot is out there.
  placed,

  /// They found it and tapped it.
  caught,
}

class _ArHuntScreenState extends State<ArHuntScreen> {
  /// The app's strings. A getter rather than a field so it re-resolves after a
  /// language change, and so the many non-`build` methods on this State — the
  /// camera and AR callbacks, which report through snackbars and `_error` —
  /// can reach them without each taking a context.
  AppLocalizations get _l10n => AppLocalizations.of(context);

  /// Asset the mascot is loaded from. Rendered natively by the AR engine.
  static const String _modelAsset = 'assets/3d/rigged_animated_fennec.glb';

  /// Size of the mascot along its longest axis, in metres. A real fennec is
  /// smaller, but it has to stay readable from across a room.
  static const double _mascotSize = 0.6;

  /// Give up waiting for a tracked plane after this and place the mascot at
  /// the estimated floor height, so a dim or featureless room still gets a
  /// hunt. Short, because the estimate below is good enough to start from —
  /// the real floor height is folded in later by [_startFloorRefinement].
  static const Duration _scanPatience = Duration(milliseconds: 1200);

  /// How long to keep looking for the real floor after the mascot is already
  /// out. Costs nothing visible, so it can afford to be patient.
  static const Duration _refineWindow = Duration(seconds: 20);

  /// Gap between background floor probes during that window.
  static const Duration _refineInterval = Duration(milliseconds: 1500);

  /// Fractions of the view height the floor probe fires at.
  ///
  /// The floor is below the horizon, so probing down the lower middle of the
  /// frame finds it while the phone is held normally — no need to point the
  /// camera at the ground. Kept clear of the header and footer chrome, which
  /// would swallow the synthetic tap before it reached the AR view.
  static const List<double> _probeHeights = [0.52, 0.62, 0.70];

  /// Moving the mascot for anything less than this isn't worth the visible
  /// jump once it is already standing there.
  static const double _refineThreshold = 0.08;

  /// How wide the frame is, give or take, used to decide whether the mascot is
  /// on screen. Phone rear cameras sit around 65°; the arrow only has to be
  /// right about "in view or not", so an approximation is enough.
  static const double _halfFovRadians = 30 * math.pi / 180;

  ArSession? _ar;
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;

  ARAnchor? _anchor;
  ARNode? _node;
  GlbBounds? _bounds;

  _Stage _stage = _Stage.scanning;

  /// Which shutter the plain camera is currently showing. Opens on [
  /// CaptureMode.media] for the same reason a phone's camera does: a photo is
  /// the shot you take without thinking about it, and scanning is a decision.
  CaptureMode _captureMode = CaptureMode.media;

  /// True while the camera is answering a specific quest, so the modes that
  /// cannot answer it are withheld rather than offered and then refused.
  bool get _questing => widget.intent.isQuest;

  /// Shortest clip this camera will accept. A quest sets a real floor; the
  /// free camera only guards against a mistimed tap.
  Duration get _minClip =>
      widget.intent == CaptureIntent.video ? _kMinQuestClip : _kMinFreeClip;

  /// The plain camera's viewfinder.
  ///
  /// Null while hunting: the hunt renders the AR session instead, and running
  /// both at once is not possible — ARCore/ARKit take the camera exclusively.
  /// That split is the whole reason this field exists rather than the screen
  /// simply using `session.snapshot()` for everything, as it used to.
  CameraController? _camera;

  /// True from the moment a hold starts filming until the clip is saved.
  bool _recording = false;

  /// Wall-clock start of the current clip, for the on-screen timer.
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;
  Timer? _clipLimit;

  bool _busy = false;
  bool _floorMeasured = false;
  String? _error;

  /// The frame that has been taken but not yet accepted, held over the
  /// viewfinder while it is looked at.
  ///
  /// Both plain-camera shots are worth a second before they are committed to —
  /// a photo goes in the folder, a scan spends a generation — and a frozen
  /// frame is the only way to tell a blurred or half-framed shot from a good
  /// one, because the live viewfinder has already moved on. The hunt has no
  /// review: the shot there is the end of a chase, and interrupting it to ask
  /// would be asking about the wrong thing.
  Uint8List? _pendingFrame;

  /// Which shutter took [_pendingFrame]. Captured at the shutter rather than
  /// read back at confirm time, so the frame and what happens to it can't come
  /// apart.
  bool _pendingScan = false;

  /// A clip that has been filmed but not yet kept, replayed on a loop over the
  /// viewfinder while it is decided on.
  ///
  /// A photo gets reviewed as a frozen frame; a clip has to be *watched*, and
  /// that is the whole reason this is a separate field rather than reusing
  /// [_pendingFrame]. Judging a video from a still of its opening frame is not
  /// a review — a pan starts pointed at whatever the traveller happened to be
  /// facing before they pressed.
  String? _pendingVideoPath;
  Duration _pendingVideoLength = Duration.zero;

  Timer? _scanTimeout;
  Timer? _poseTimer;
  Timer? _refineTimer;
  Completer<double?>? _floorProbe;
  int _probePointer = 0x51D0;

  /// Floor height the mascot currently stands on, in world metres.
  double? _floorY;

  /// Where the mascot ended up, in world metres. Null until it is placed.
  vm.Vector3? _mascotPosition;

  /// Live bearing to the mascot, for the on-screen hint.
  _MascotBearing? _bearing;

  /// Geographic offset to [ArHuntScreen.spawnLocation], resolved from an
  /// early GPS fix so it's usually ready by the time the AR session starts.
  GeoOffset? _geoOffset;
  Future<void>? _geoOffsetFuture;

  /// The real-geometry placement, once both the GPS fix and a compass heading
  /// have resolved. Falls back to [ArHuntScreen.spot] until then, or forever
  /// if either never arrives.
  MascotSpot? _resolvedSpot;

  /// True while placement is waiting on [_resolveHeadingAndSpot] — plane
  /// detection must not place the mascot on the placeholder spot underneath
  /// geo resolution's feet.
  bool _geoPending = false;

  MascotSpot get _effectiveSpot => _resolvedSpot ?? widget.spot;

  /// True while this screen is running the fennec hunt rather than acting as
  /// a plain camera.
  bool get _hunting => widget.mode == ArCameraMode.hunt;

  /// True when the shutter will send the shot off to be turned into a 3D
  /// model. The hunt has its own shutter and never scans.
  bool get _scanning => !_hunting && _captureMode == CaptureMode.scan;

  /// True when holding the shutter should film rather than do nothing. Only
  /// [CaptureMode.media] films — a held shutter in 3D Scan has no meaning,
  /// since a scan is built from one frame.
  bool get _canFilm =>
      !_hunting &&
      _captureMode == CaptureMode.media &&
      widget.intent != CaptureIntent.photo;

  /// How long the current clip has been running, for the on-screen timer.
  Duration get _recordingElapsed => _recordingStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_recordingStartedAt!);

  /// True while a taken frame or clip is waiting to be kept or discarded.
  bool get _reviewing => _pendingFrame != null || _pendingVideoPath != null;

  /// How far through the 30-second cap the current clip is, 0..1. Drives the
  /// ring around the shutter, which is the only thing telling the traveller
  /// how much of their hold is left.
  double get _recordingProgress {
    if (!_recording) return 0;
    final elapsed = _recordingElapsed.inMilliseconds;
    return (elapsed / _kMaxClipDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Whether the shutter is live. Plain capture waits on its own camera
  /// controller rather than an AR session; a hunt shoots only once the fennec
  /// has been caught.
  bool get _canShoot {
    if (_busy || _reviewing) return false;
    if (_hunting) return _session != null && _stage == _Stage.caught;
    return _camera?.value.isInitialized ?? false;
  }

  @override
  void initState() {
    super.initState();
    if (_hunting) _loadBounds();
    if (_hunting && widget.spawnLocation != null) {
      _geoOffsetFuture = _resolveGeoOffset();
    }
    if (!_hunting) unawaited(_openCamera());
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _poseTimer?.cancel();
    _refineTimer?.cancel();
    _recordingTicker?.cancel();
    _clipLimit?.cancel();
    _ar?.dispose();
    // Not awaited: dispose cannot be async, and a controller that is still
    // recording is stopped by disposal anyway — the clip is lost, which is the
    // right outcome for a screen the user walked away from mid-hold.
    unawaited(_camera?.dispose());
    super.dispose();
  }

  /// Opens the rear camera for the plain capture screen.
  ///
  /// `enableAudio` is on because a video of a place with the sound stripped out
  /// is a worse record of being there — but it is also why this screen triggers
  /// the microphone prompt, and only this screen: the hunt never constructs a
  /// controller at all.
  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', _l10n.arNoCamera);
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _cameraErrorText(e));
    }
  }

  String _cameraErrorText(Object error) {
    if (error is CameraException && error.code.toLowerCase().contains('permission')) {
      return _l10n.arCameraNeedsPermission;
    }
    return _l10n.arCameraDidNotOpen(
      error is CameraException ? error.description ?? error.code : '$error',
    );
  }

  /// Takes an early GPS fix so the geographic offset to the spawn point is
  /// usually already known by the time the AR session starts and asks for a
  /// compass heading — only the heading, which needs a live session, is left
  /// to resolve there.
  Future<void> _resolveGeoOffset() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() {
        _geoOffset =
            geoOffset(LatLng(position.latitude, position.longitude), widget.spawnLocation!);
      });
    } catch (_) {
      // No fix in time — placement falls back to widget.spot, same as any
      // other rung of the plan's degradation ladder.
    }
  }

  /// Combines [_geoOffset] with the heading at AR session start into a real
  /// [MascotSpot] (§5.5). Placement waits on this — see [_geoPending] — so the
  /// mascot never gets dropped at the placeholder spot while this is still
  /// resolving.
  Future<void> _resolveHeadingAndSpot() async {
    setState(() => _geoPending = true);
    // The GPS fix from initState is usually already in by now; give it a
    // little more time to land before giving up on it too.
    if (_geoOffset == null) await _geoOffsetFuture;
    final heading = await HeadingService.currentHeading();
    if (!mounted) return;

    final offset = _geoOffset;
    setState(() {
      _geoPending = false;
      if (offset != null && heading != null) {
        _resolvedSpot = MascotSpot.towardsBearing(
          trueBearingRadians: offset.bearingRadians,
          headingRadians: heading,
        );
      }
    });
  }

  Future<void> _loadBounds() async {
    try {
      final bounds = await readGlbBounds(_modelAsset);
      if (mounted) setState(() => _bounds = bounds);
    } catch (_) {
      if (mounted) setState(() => _error = _l10n.arCouldNotReadModel);
    }
  }

  void _onSessionCreated(ArSession session) {
    final sessionManager = session.sessionManager;
    final objectManager = session.objectManager;

    _ar = session;
    _session = sessionManager;
    _objects = objectManager;
    _anchors = session.anchorManager;

    sessionManager.onInitialize(
      // Planes are shown while the room is being mapped, then hidden once the
      // mascot is out — the glowing grid would give its position away. Plain
      // capture never shows them; they'd only end up in the photo.
      showPlanes: _hunting,
      showFeaturePoints: false,
      showWorldOrigin: false,
      // The plugin's hand-holding-a-phone sweep animation. It is drawn by the
      // native view on top of the camera feed, so it also lands in captured
      // photos — and in plain capture mode there is nothing to scan for in the
      // first place. Off in both modes.
      showAnimatedGuide: false,
      // Taps drive both the floor probe below and catching the mascot.
      handleTaps: true,
      handlePans: false,
      handleRotation: false,
    );
    objectManager.onInitialize();

    sessionManager.onPlaneDetected = _onPlaneDetected;
    sessionManager.onPlaneOrPointTap = _onHitTestResult;
    sessionManager.onError = (error) {
      if (mounted) setState(() => _error = error);
    };
    objectManager.onNodeTap = (_) => _onMascotTapped();

    // The shutter reads [_canShoot], which has just become true for plain
    // capture; nothing else would rebuild to show it.
    if (mounted) setState(() {});

    if (!_hunting) return;

    if (widget.spawnLocation != null) {
      // Placement waits on the real bearing when there's real geometry to
      // wait on — see [_geoPending] — then arms the usual scan timeout.
      _resolveHeadingAndSpot().whenComplete(_armScanTimeout);
    } else {
      _armScanTimeout();
    }
  }

  /// However the room turns out, the mascot gets placed.
  void _armScanTimeout() {
    _scanTimeout = Timer(_scanPatience, () {
      if (_stage == _Stage.scanning) _placeMascot();
    });
  }

  void _onPlaneDetected(int planeCount) {
    if (!mounted || !_hunting || planeCount <= 0 || _geoPending) return;
    if (_stage == _Stage.scanning) _placeMascot();
  }

  // ---------------------------------------------------------------------
  // Where is it?
  // ---------------------------------------------------------------------

  /// Follows the mascot from the camera's point of view so the hint can point
  /// at it. Ten times a second is plenty — the arrow is a nudge, not a
  /// reticle, and each read costs a round trip to the AR session.
  void _startTrackingBearing() {
    _poseTimer?.cancel();
    _poseTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _updateBearing(),
    );
  }

  Future<void> _updateBearing() async {
    final session = _ar;
    final mascot = _mascotPosition;
    if (session == null || mascot == null || !mounted) return;

    final pose = await session.cameraPose();
    if (pose == null || !mounted) return;

    // Camera axes: +X right, +Y up, -Z ahead.
    final local = pose.toCameraSpace(mascot);
    final depth = -local.z;
    final distance = local.length;

    final inFront = depth > 0.05;
    final onScreen = inFront &&
        math.atan2(local.x.abs(), depth) < _halfFovRadians &&
        math.atan2(local.y.abs(), depth) < _halfFovRadians;

    // Screen space has Y running downwards. Behind the camera there is no
    // meaningful direction to point, so send them turning the shorter way.
    final direction = inFront
        ? Offset(local.x, -local.y)
        : Offset(local.x >= 0 ? 1 : -1, 0);
    final length = direction.distance;

    final bearing = _MascotBearing(
      direction: length > 1e-6 ? direction / length : const Offset(1, 0),
      distance: distance,
      onScreen: onScreen,
    );

    final previous = _bearing;
    if (previous != null &&
        previous.onScreen == bearing.onScreen &&
        (previous.direction - bearing.direction).distance < 0.01 &&
        (previous.distance - bearing.distance).abs() < 0.05) {
      return;
    }
    if (bearing.onScreen && !(previous?.onScreen ?? false)) {
      HapticFeedback.selectionClick();
    }
    setState(() => _bearing = bearing);
  }

  // ---------------------------------------------------------------------
  // Placement
  // ---------------------------------------------------------------------

  Future<void> _placeMascot() async {
    if (_stage != _Stage.scanning || _busy) return;
    final bounds = _bounds;
    final anchors = _anchors;
    final objects = _objects;
    if (bounds == null || anchors == null || objects == null) return;

    _scanTimeout?.cancel();
    setState(() {
      _stage = _Stage.placing;
      _busy = true;
    });

    // One quick sweep, then place regardless. Anything the sweep misses is
    // picked up by [_startFloorRefinement] while the visitor is already
    // looking around, so nobody waits on it.
    final measured = await _probeFloor();
    if (!mounted) return;

    final floorY = measured ?? await _estimateFloorFromPose();
    if (!mounted) return;

    final anchor = ARPlaneAnchor(
      transformation: _effectiveSpot.anchorTransform(
        floorY: floorY,
        baseOffset: bounds.baseOffsetRatio * _mascotSize,
      ),
    );

    try {
      if (await anchors.addAnchor(anchor) != true) {
        throw StateError('anchor rejected');
      }
      final node = await _attachMascot(objects, anchor);
      if (node == null) throw StateError('model rejected');

      _session?.showPlanes(false);
      if (!mounted) return;
      setState(() {
        _anchor = anchor;
        _node = node;
        // Aim the hint at its body rather than its feet.
        _mascotPosition = _effectiveSpot.floorPosition(floorY) +
            vm.Vector3(0, bounds.heightRatio * _mascotSize / 2, 0);
        _floorY = floorY;
        _floorMeasured = measured != null;
        _stage = _Stage.placed;
        _busy = false;
      });
      _startTrackingBearing();
      if (measured == null) _startFloorRefinement();
      HapticFeedback.mediumImpact();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _Stage.scanning;
        _error = _l10n.arCouldNotPlaceFennec;
      });
    }
  }

  /// Where the floor is when nothing trackable has been found yet.
  ///
  /// Both runtimes put Y along gravity, so the floor is simply a person's
  /// phone-holding height below the camera. Sampling the live pose rather
  /// than the session origin means this still holds after the visitor has
  /// walked, crouched or raised the phone since the session started — and it
  /// needs the camera to be pointing nowhere in particular.
  Future<double> _estimateFloorFromPose() async {
    final pose = await _ar?.cameraPose();
    return (pose?.position.y ?? 0) - kAssumedPhoneHeight;
  }

  /// Looks for the real floor height by hit-testing down the lower half of
  /// the view.
  ///
  /// The plugin only surfaces hit tests through its tap callback, so the probe
  /// below drives that path with a synthetic tap rather than waiting for the
  /// visitor to press the floor themselves. Replace this with a direct call
  /// if the plugin ever exposes a hit test of its own.
  ///
  /// Returns null when none of the probed points land on a tracked plane.
  Future<double?> _probeFloor() async {
    for (final height in _probeHeights) {
      if (!mounted) return null;

      final probe = Completer<double?>();
      _floorProbe = probe;
      await _probeAt(height);

      // Android only confirms a single tap after the double-tap window has
      // passed, so the result comes back a couple of hundred ms later.
      final hit = await probe.future.timeout(
        const Duration(milliseconds: 320),
        onTimeout: () => null,
      );
      _floorProbe = null;
      if (hit != null) return hit;
    }
    return null;
  }

  /// Keeps hunting for the real floor after the mascot is already out, and
  /// settles it onto the floor the moment one is found.
  ///
  /// This is what makes the calibration automatic: the visitor never has to
  /// aim at the ground, they just have to walk around normally, and sooner or
  /// later a plane passes under one of the probe points.
  void _startFloorRefinement() {
    _refineTimer?.cancel();
    final deadline = DateTime.now().add(_refineWindow);

    _refineTimer = Timer.periodic(_refineInterval, (timer) async {
      if (!mounted || _stage != _Stage.placed || _floorMeasured) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        return;
      }
      final measured = await _probeFloor();
      if (measured != null && mounted) await _settleOnFloor(measured);
    });
  }

  /// Re-anchors the mascot at a newly measured [floorY].
  ///
  /// Skips imperceptible corrections, because re-anchoring means removing and
  /// re-adding the node — cheap, but visible as a blink if done for a
  /// centimetre.
  Future<void> _settleOnFloor(double floorY) async {
    final bounds = _bounds;
    final anchors = _anchors;
    final objects = _objects;
    final previous = _floorY;
    if (bounds == null || anchors == null || objects == null || _busy) return;
    if (_stage != _Stage.placed) return;
    if (previous != null && (previous - floorY).abs() < _refineThreshold) {
      setState(() => _floorMeasured = true);
      return;
    }

    final anchor = ARPlaneAnchor(
      transformation: _effectiveSpot.anchorTransform(
        floorY: floorY,
        baseOffset: bounds.baseOffsetRatio * _mascotSize,
      ),
    );
    if (await anchors.addAnchor(anchor) != true) return;

    final node = await _attachMascot(objects, anchor);
    if (node == null || !mounted) return;

    final oldNode = _node;
    final oldAnchor = _anchor;
    if (oldNode != null) objects.removeNode(oldNode);
    if (oldAnchor != null) anchors.removeAnchor(oldAnchor);

    setState(() {
      _anchor = anchor;
      _node = node;
      _mascotPosition = _effectiveSpot.floorPosition(floorY) +
          vm.Vector3(0, bounds.heightRatio * _mascotSize / 2, 0);
      _floorY = floorY;
      _floorMeasured = true;
    });
  }

  /// Sends a synthetic tap through the AR view at [heightFraction] down the
  /// screen, on the vertical centre line.
  ///
  /// Flutter forwards pointer events over a platform view down to the native
  /// view, so a tap injected here reaches the AR session's gesture detector
  /// exactly as a real one would.
  Future<void> _probeAt(double heightFraction) async {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    final point = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height * heightFraction),
    );
    final pointer = _probePointer++;
    final binding = GestureBinding.instance;

    binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: point,
      kind: PointerDeviceKind.touch,
    ));
    // A press and release in the same instant doesn't always survive the
    // gesture arena; a frame's gap makes it look like a real tap.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: point,
      kind: PointerDeviceKind.touch,
    ));
  }

  void _onHitTestResult(List<ARHitTestResult> hits) {
    final probe = _floorProbe;
    if (probe == null || probe.isCompleted) return;

    // Only a hit on a tracked plane pins down the floor — feature-point hits
    // are guesses at geometry the session hasn't mapped properly yet.
    for (final hit in hits) {
      if (hit.type == ARHitTestResultType.plane) {
        probe.complete(hit.worldTransform.getTranslation().y);
        return;
      }
    }
  }

  /// Attaches the mascot model to [anchor].
  ///
  /// The AR engine resolves a Flutter asset path through its own loader, which
  /// is the cheap route — no copying, no second copy of an 8MB model on disk.
  /// It isn't guaranteed to accept a `.glb` there though (the node type is
  /// named for glTF), so on failure the asset is unpacked to the app's
  /// documents folder and loaded from the filesystem instead.
  Future<ARNode?> _attachMascot(
    ARObjectManager objects,
    ARPlaneAnchor anchor,
  ) async {
    // Read as "scale the model so its longest side measures this many metres",
    // not as a multiplier.
    final scale = vm.Vector3.all(_mascotSize);

    ARNode? attachedNode;
    final assetNode = ARNode(
      type: NodeType.localGLTF2,
      uri: _modelAsset,
      scale: scale,
    );
    if (await objects.addNode(assetNode, planeAnchor: anchor) == true) {
      attachedNode = assetNode;
    }

    if (attachedNode == null) {
      try {
        final fileNode = ARNode(
          type: NodeType.fileSystemAppFolderGLB,
          uri: 'file://${await _unpackModel()}',
          scale: scale,
        );
        if (await objects.addNode(fileNode, planeAnchor: anchor) == true) {
          attachedNode = fileNode;
        }
      } catch (_) {
        // Fall through — the caller reports the failure to the visitor.
      }
    }

    if (attachedNode != null) {
      await objects.playAnimation(nodeName: attachedNode.name, animationName: 'Sit', loop: true);
    }
    
    return attachedNode;
  }

  /// Copies the bundled model out of the asset bundle, once per install.
  Future<String> _unpackModel() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_modelAsset.split('/').last}');
    if (!file.existsSync()) {
      final data = await rootBundle.load(_modelAsset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  void _onMascotTapped() {
    if (_stage != _Stage.placed || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _stage = _Stage.caught);
    
    if (_node != null && _objects != null) {
      _objects!.playAnimation(nodeName: _node!.name, animationName: 'Jump', loop: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  /// Takes the shot.
  ///
  /// On a hunt this is the whole of it — the frame goes straight on to be
  /// saved and the screen closes. In plain capture it stops at the frozen
  /// frame and waits for [_keepShot] or [_retakeShot].
  Future<void> _capture() async {
    if (_busy || _reviewing || _recording) return;

    // A video quest cannot be answered with a photo, so tapping says what to
    // do instead of quietly taking one and having it rejected later.
    if (widget.intent == CaptureIntent.video) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.arQuestNeedsClip(_kMinQuestClip.inSeconds)),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final scanning = _scanning;

    final Uint8List frame;
    try {
      frame = _hunting ? await _snapshotFromSession() : await _snapshotFromCamera();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(_l10n.arCouldNotTakeShot(e.toString()))),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    if (!mounted) return;

    if (_hunting) {
      _dispatch(frame, scanning: false);
      return;
    }

    setState(() {
      _pendingFrame = frame;
      _pendingScan = scanning;
      _busy = false;
    });
  }

  /// The hunt's still: a composited frame of the AR scene, fennec included.
  Future<Uint8List> _snapshotFromSession() async {
    final session = _session;
    if (session == null) throw StateError('no AR session');
    final image = await session.snapshot();
    if (image is! MemoryImage) throw StateError('unexpected snapshot format');
    return image.bytes;
  }

  /// The plain camera's still.
  Future<Uint8List> _snapshotFromCamera() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      throw StateError('camera not ready');
    }
    final file = await camera.takePicture();
    return file.readAsBytes();
  }

  // ---------------------------------------------------------------------
  // Filming
  //
  // Hold the shutter to record, release to keep it. The gesture is the one
  // every phone camera already uses, which is why it is not signposted beyond
  // the hint under the viewfinder — it is being confirmed, not taught.
  // ---------------------------------------------------------------------

  Future<void> _startRecording() async {
    final camera = _camera;
    if (!_canFilm || _recording || _busy || _reviewing) return;
    if (camera == null || !camera.value.isInitialized) return;

    try {
      await camera.startVideoRecording();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.arCouldNotStartFilming(_cameraErrorText(e)))),
      );
      return;
    }
    if (!mounted) {
      // The screen went away between the await and here; stop the recording
      // rather than leaving the camera running into a disposed controller.
      unawaited(camera.stopVideoRecording().catchError((_) => XFile('')));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recordingStartedAt = DateTime.now();
    });

    // Drives the timer readout and the ring around the shutter; the clip
    // itself is bounded by _clipLimit below, so a dropped tick cannot overrun
    // the cap. 50 ms because the ring is the part being watched — at the 200 ms
    // the readout alone needed, a thirty-second sweep visibly steps.
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() {});
    });
    _clipLimit = Timer(_kMaxClipDuration, () {
      // Stops itself at the cap rather than waiting for a release: someone
      // filming a long pan should get their clip, not a recording that keeps
      // growing until the disk complains.
      unawaited(_stopRecording(hitLimit: true));
    });
  }

  Future<void> _stopRecording({bool hitLimit = false}) async {
    final camera = _camera;
    if (!_recording || camera == null) return;

    _recordingTicker?.cancel();
    _clipLimit?.cancel();
    _recordingTicker = null;
    _clipLimit = null;

    final elapsed = DateTime.now().difference(_recordingStartedAt ?? DateTime.now());
    setState(() {
      _recording = false;
      _recordingStartedAt = null;
      _busy = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    XFile clip;
    try {
      clip = await camera.stopVideoRecording();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(_l10n.arClipDidNotSave(_cameraErrorText(e)))),
      );
      return;
    }

    // Too short to keep. For the free camera that means a tap the gesture
    // recogniser rounded the wrong way; for a video quest it means the clip
    // does not meet what the quest asked for. Either way the file goes, and
    // the message says which of the two it was — "hold for a moment" is not
    // useful advice to someone who held for two seconds.
    if (elapsed < _minClip) {
      unawaited(File(clip.path).delete().catchError((_) => File(clip.path)));
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.intent == CaptureIntent.video
                ? _l10n.arClipTooShort(
                    elapsed.inSeconds, _kMinQuestClip.inSeconds)
                : _l10n.arHoldToFilm,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (hitLimit) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(_l10n.arClipCapped(_kMaxClipDuration.inSeconds))),
      );
    }

    // Straight into review rather than the folder. A clip is the one capture
    // the traveller genuinely cannot judge at the moment of taking it — they
    // were watching the scene, not the frame — so it gets watched back before
    // it is committed to.
    setState(() {
      _pendingVideoPath = clip.path;
      _pendingVideoLength = elapsed;
      _busy = false;
    });
  }

  /// Throws the reviewed clip away and hands the viewfinder back.
  void _discardClip() {
    final path = _pendingVideoPath;
    if (path == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pendingVideoPath = null;
      _pendingVideoLength = Duration.zero;
    });
    // The file is in the camera plugin's cache directory and nothing else
    // refers to it, so this is the last chance to remove it — the OS would get
    // there eventually, but leaving discarded footage on the device in the
    // meantime is not what "discard" means to the person who pressed it.
    unawaited(File(path).delete().catchError((_) => File(path)));
  }

  /// Accepts the reviewed clip and files it.
  void _keepClip() {
    final path = _pendingVideoPath;
    if (path == null || _busy) return;
    HapticFeedback.mediumImpact();
    _dispatchVideo(path, _pendingVideoLength);
  }

  /// Throws the reviewed frame away and hands the viewfinder back.
  void _retakeShot() {
    if (!_reviewing) return;
    HapticFeedback.selectionClick();
    setState(() => _pendingFrame = null);
  }

  /// Accepts the reviewed frame and sends it on its way.
  void _keepShot() {
    final frame = _pendingFrame;
    if (frame == null || _busy) return;
    HapticFeedback.mediumImpact();
    _dispatch(frame, scanning: _pendingScan);
  }

  /// Closes the screen on a finished clip and files it behind the exit.
  ///
  /// No review step, unlike a photo. Reviewing a video means playing it back,
  /// which needs a player this app does not carry — and a still of the first
  /// frame would be a worse decision aid than no review at all, since what
  /// makes a clip good or bad is almost never its opening frame.
  void _dispatchVideo(String path, Duration length) {
    final messenger = ScaffoldMessenger.of(context);
    final bloc = context.read<AppBloc>();
    // Read while the context is still mounted: everything below runs after
    // this screen has popped.
    final l10n = _l10n;

    Navigator.of(context).pop();

    unawaited(_finishVideoCapture(
      sourcePath: path,
      length: length,
      bloc: bloc,
      messenger: messenger,
      l10n: l10n,
    ));
  }

  /// Closes the screen on [frame] and lets the rest finish behind it.
  ///
  /// Only the snapshot itself has to happen while the camera is still on
  /// screen. Everything after it — writing the file, compressing, object
  /// detection, the network — used to run before the screen closed, which is
  /// what made the shutter feel like the app had frozen: several seconds of a
  /// stuck viewfinder with nothing to show for it. Now the screen closes here
  /// and the rest finishes behind it, reporting to the folder and a snackbar
  /// the way any other background work does.
  void _dispatch(Uint8List frame, {required bool scanning}) {
    final messenger = ScaffoldMessenger.of(context);
    final bloc = context.read<AppBloc>();
    final l10n = _l10n;

    // Past this line the widget is on its way out, so the work below is
    // handed to functions that hold no reference to it — no setState, no
    // context, nothing that a disposed State would trip over.
    Navigator.of(context).pop();

    if (scanning) {
      unawaited(_finishScanCapture(
        frame: frame,
        bloc: bloc,
        messenger: messenger,
        l10n: l10n,
      ));
    } else {
      unawaited(_finishPhotoCapture(
        frame: frame,
        bloc: bloc,
        messenger: messenger,
        l10n: l10n,
        caught: _hunting,
        spawnId: widget.spawnId,
        captureToken: widget.captureToken,
        arTelemetry: {
          'stage': _stage.name,
          'floor_measured': _floorMeasured,
        },
      ));
    }
  }

  /// Clears the mascot and drops it again — handy while the spot is still
  /// hard-coded rather than coming from the backend.
  Future<void> _reset() async {
    final anchor = _anchor;
    final node = _node;
    if (node != null) _objects?.removeNode(node);
    if (anchor != null) _anchors?.removeAnchor(anchor);
    _poseTimer?.cancel();
    _refineTimer?.cancel();
    _session?.showPlanes(true);
    if (!mounted) return;
    setState(() {
      _anchor = null;
      _node = null;
      _mascotPosition = null;
      _bearing = null;
      _floorY = null;
      _floorMeasured = false;
      _stage = _Stage.scanning;
    });
    _placeMascot();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bearing = _bearing;
    final review = _pendingFrame;
    final hunting = _hunting &&
        (_stage == _Stage.placed || _stage == _Stage.caught);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The hunt needs world tracking to stand a fennec on the floor; the
          // plain camera needs a camera that can also record. They cannot be
          // the same surface — ARCore/ARKit take the camera exclusively — so
          // the screen picks one at mount and keeps it.
          if (_hunting)
            ArSessionHost(
              onSessionCreated: _onSessionCreated,
              // Horizontal only: the fennec stands on the floor, and tracking
              // walls as well only slows the search for a surface.
              planeDetectionConfig: PlaneDetectionConfig.horizontal,
              permissionDenied: _buildPermissionPrompt,
            )
          else
            _buildCameraViewfinder(),
          if (review != null)
            // The frame sits on top of the running session rather than
            // replacing it, so a retake is instant — the AR view underneath
            // never went away and has nothing to warm back up.
            Image.memory(
              review,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else if (_pendingVideoPath != null)
            // Same idea, and the same reason: the camera keeps running behind
            // the replay, so discarding is instant.
            _ClipReview(
              // Keyed on the path so filming a second clip after discarding
              // the first builds a fresh player rather than reusing one still
              // pointed at a file that has been deleted.
              key: ValueKey(_pendingVideoPath),
              path: _pendingVideoPath!,
            )
          else if (hunting && bearing != null && !bearing.onScreen)
            _EdgeArrow(direction: bearing.direction),
          _buildChrome(context),
        ],
      ),
    );
  }

  /// The plain camera's preview, filling the screen the way the AR view did.
  ///
  /// `CameraPreview` reports the sensor's aspect ratio, which is almost never
  /// the screen's. Letterboxing it would be the honest framing, but no phone
  /// camera app does that and a photo app with black bars reads as broken —
  /// so the preview is scaled to cover and the overflow is clipped, which is
  /// what the OS camera does too.
  Widget _buildCameraViewfinder() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
          ),
        ),
      );
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewRatio = camera.value.aspectRatio;
          final screenRatio = constraints.maxWidth / constraints.maxHeight;
          // `aspectRatio` is width/height in landscape terms; the preview is
          // shown portrait, hence the inversion.
          final scale = screenRatio < (1 / previewRatio)
              ? (1 / previewRatio) / screenRatio
              : screenRatio * previewRatio;
          return Transform.scale(
            scale: scale.isFinite && scale > 0 ? scale : 1.0,
            child: Center(child: CameraPreview(camera)),
          );
        },
      ),
    );
  }

  Widget _buildPermissionPrompt(BuildContext context, VoidCallback retry) {
    return ColoredBox(
      color: AppTheme.ink,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white54, size: 34),
              const SizedBox(height: 14),
              Text(
                _hunting
                    ? _l10n.arHuntNeedsCamera
                    : _l10n.arPhotoNeedsCamera,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: retry,
                child: Text(_l10n.arAllowCamera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChrome(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                PressableScale(
                  onTap: () => Navigator.of(context).pop(),
                  child: GlassSurface(
                    tint: GlassTint.dark,
                    borderRadius: AppTheme.brPill,
                    padding: const EdgeInsets.all(11),
                    child:
                        const Icon(Icons.close, size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassSurface(
                    tint: GlassTint.dark,
                    borderRadius: AppTheme.brPill,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _reviewing
                              ? (_pendingVideoPath != null
                                  ? _l10n.arKeepThisClip
                                  : _pendingScan
                                      ? _l10n.arScanThis
                                      : _l10n.arKeepThisPhoto)
                              : _hunting
                                  ? _l10n.arFindTheFennec
                                  : _scanning
                                      ? _l10n.arScanAnObject
                                      : _l10n.arPhotoOrVideo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _reviewing
                              ? (_pendingVideoPath != null
                                  ? _l10n.arClipLooping
                                  : _pendingScan
                                      ? _l10n.arCheckObjectSharp
                                      : _l10n.arCheckItCameOut)
                              : widget.stopName ??
                                  (_hunting
                                      ? _l10n.arSomewhereAroundYou
                                      : _scanning
                                          ? _l10n.arComesBackAs3d
                                          : _l10n.arGoesToYourFolder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_hunting &&
                    (_stage == _Stage.placed || _stage == _Stage.caught)) ...[
                  const SizedBox(width: 12),
                  PressableScale(
                    onTap: _reset,
                    child: GlassSurface(
                      tint: GlassTint.dark,
                      borderRadius: AppTheme.brPill,
                      padding: const EdgeInsets.all(11),
                      child: const Icon(Icons.refresh,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (_error != null)
            _buildError()
          else if (_reviewing)
            _buildReviewFooter()
          else
            _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final bearing = _bearing;
    // The strip under the card already names the mode in plain-camera mode, so
    // the card there carries the hint alone — the same word twice, forty
    // pixels apart, tells nobody anything.
    final (String? label, String hint) = !_hunting
        ? (
            null,
            _scanning
                ? _l10n.arFillTheFrame
                // The hold is the only part of this screen that is not
                // self-evident, so it is the part the hint spends its words on.
                : _l10n.arTapToShootHoldToFilm,
          )
        : switch (_stage) {
            _Stage.scanning => (
                _l10n.arStageReadingRoom,
                _l10n.arStageReadingRoomHint,
              ),
            _Stage.placing => (
                _l10n.arStageLettingOut,
                _l10n.arStageLettingOutHint,
              ),
            _Stage.placed => (
                bearing?.onScreen ?? false
                    ? _l10n.arStageThereItIs
                    : _l10n.arStageItIsOutThere,
                _l10n.arStageWalkAround,
              ),
            _Stage.caught => (
                _l10n.arStageFoundIt,
                _l10n.arStageFrameTheShot,
              ),
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassSurface(
            tint: GlassTint.dark,
            borderRadius: AppTheme.brLg,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null) ...[
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_hunting && bearing != null && _stage == _Stage.placed) ...[
                  const SizedBox(height: 4),
                  Text(
                    _l10n.arDistanceAway(bearing.distance.toStringAsFixed(1)),
                    style: const TextStyle(
                      color: AppTheme.accentSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_hunting && _stage == _Stage.placed && !_floorMeasured) ...[
                  const SizedBox(height: 4),
                  Text(
                    _l10n.arFloorEstimated,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.accentSoft,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_hunting) ...[
            const SizedBox(height: 12),
            // Hidden while filming: a mode strip that can still be swiped
            // under a running recording is a way to end up in 3D Scan with a
            // clip half-taken. Hidden for a quest too — there is only one mode
            // that can answer it, so a strip would offer choices that lead
            // nowhere.
            if (_recording)
              _RecordingPill(elapsed: _recordingElapsed)
            else if (_questing)
              _IntentPill(intent: widget.intent)
            else
              CameraModeSelector(
                labels: [
                  for (final mode in CaptureMode.values) mode.label(_l10n),
                ],
                index: _captureMode.index,
                enabled: !_busy,
                onChanged: (index) =>
                    setState(() => _captureMode = CaptureMode.values[index]),
              ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 20),
          _ShutterButton(
            enabled: _canShoot,
            onTap: _capture,
            onHoldStart: _canFilm ? _startRecording : null,
            onHoldEnd: _canFilm ? _stopRecording : null,
            recording: _recording,
            progress: _recordingProgress,
            icon: _scanning
                ? Icons.view_in_ar_rounded
                : Icons.camera_alt_rounded,
          ),
        ],
      ),
    );
  }

  /// Retake or keep, in place of the shutter.
  ///
  /// The two sit at the same height the shutter did, so the thumb is already
  /// where it needs to be. Keeping is the filled one because it is what
  /// almost every shot is for; retaking is a shade quieter but the same size,
  /// since it is the reason this step exists at all.
  Widget _buildReviewFooter() {
    // A clip and a photo are reviewed the same way and in the same place; only
    // the words differ. "Discard" rather than "Retake" because releasing the
    // shutter already ended the take — there is nothing to retake, only
    // something to throw away.
    final isClip = _pendingVideoPath != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 34),
      child: Row(
        children: [
          Expanded(
            child: _ReviewButton(
              label: isClip ? _l10n.actionDiscard : _l10n.actionRetake,
              icon: isClip ? Icons.delete_outline_rounded : Icons.refresh_rounded,
              onTap: isClip ? _discardClip : _retakeShot,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ReviewButton(
              label: isClip
                  ? _l10n.arKeepClip(_pendingVideoLength.inSeconds)
                  : _pendingScan
                      ? _l10n.arScanIt
                      : _l10n.arUsePhoto,
              icon: isClip
                  ? Icons.check_rounded
                  : _pendingScan
                      ? Icons.view_in_ar_rounded
                      : Icons.check_rounded,
              onTap: isClip ? _keepClip : _keepShot,
              filled: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: GlassSurface(
        tint: GlassTint.dark,
        borderRadius: AppTheme.brLg,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white70, size: 26),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _error = null),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              child: Text(_l10n.actionDismiss),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// After the shutter
// ---------------------------------------------------------------------------
//
// Both of these run after the camera screen has been popped, which is the
// whole point of them — the shutter is only as fast as the work it waits on.
// They are top-level rather than methods so there is no `this` to be tempted
// by: the State they came from is disposed by the time they get going, and its
// context, `mounted` and `setState` are all off limits. The bloc and the root
// [ScaffoldMessengerState] both outlive the screen, so results still land in
// the folder and on screen.

/// Moves a finished clip out of the camera plugin's temp directory and into
/// the folder.
///
/// The move matters: `stopVideoRecording` hands back a path under the app's
/// **cache** directory, which the OS may reclaim at any time. A capture the
/// traveller has not uploaded yet must live in documents, which is backed up
/// and never evicted — the same rule the plan applies to un-uploaded photos.
Future<void> _finishVideoCapture({
  required String sourcePath,
  required Duration length,
  required AppBloc bloc,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final destination =
        '${directory.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final source = File(sourcePath);
    try {
      await source.rename(destination);
    } on FileSystemException {
      // rename() cannot cross filesystems, and on some devices the cache and
      // documents directories are on different mounts. Copy, then drop the
      // original.
      await source.copy(destination);
      await source.delete().catchError((_) => source);
    }

    bloc.add(AddCapturedArtifactEvent(destination,
        kindLabel: l10n.artifactVideo, kind: 'video'));
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.arClipSaved(length.inSeconds)),
    ));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.arCouldNotSaveClip(e.toString()))),
    );
  }
}

/// Saves [frame] straight to the folder — the plain photo shutter, and the
/// shot that ends a fennec hunt.
///
/// [caught] marks the hunt case, which additionally reports the catch to the
/// backend when the hunt was a real (server-issued) one.
Future<void> _finishPhotoCapture({
  required Uint8List frame,
  required AppBloc bloc,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required bool caught,
  String? spawnId,
  String? captureToken,
  Map<String, dynamic> arTelemetry = const {},
}) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(frame, flush: true);

    if (caught) {
      // A caught fennec is not one of the traveller's own photographs, and
      // filing it among them was the wrong shelf: the folder is for what they
      // made, the collection album is for what they found. Only the fact of
      // the catch is reported, which is what finishes a mascot quest.
      bloc.add(const MascotCaughtEvent());
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.arFennecCaught)),
      );
      // Nothing refers to the snapshot any more — the server validates a catch
      // from the fix and the signed token, never the picture — so leaving it
      // in documents would be a file that accumulates and is never read.
      unawaited(File(path).delete().catchError((_) => File(path)));
    } else {
      bloc.add(AddCapturedArtifactEvent(path,
          kindLabel: l10n.artifactPhoto, kind: 'photo'));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.arPhotoSaved)),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.arCouldNotSaveShot(e.toString()))),
    );
    return;
  }

  // Best-effort: a network failure costs nothing, the photo is already saved.
  if (!caught || spawnId == null || captureToken == null) return;
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    ).timeout(const Duration(seconds: 3));
    await MascotRepository.submitCapture(
      spawnId: spawnId,
      captureToken: captureToken,
      fix: LatLng(position.latitude, position.longitude),
      accuracyMeters: position.accuracy,
      clientTs: DateTime.now().toUtc().toIso8601String(),
      nonce: uuidV4(),
      arTelemetry: arTelemetry,
    );
  } catch (_) {
    // Non-fatal — the photo is already saved locally.
  }
}

/// Runs [frame] through the 3D generation pipeline: compress, check there is
/// actually an object in it, then hand it to the bloc to upload and generate.
Future<void> _finishScanCapture({
  required Uint8List frame,
  required AppBloc bloc,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) async {
  try {
    // 1. Compress to JPEG + strip EXIF (privacy + bandwidth). Straight from
    // the frame in memory — the full-size original was only ever written to
    // disk so this step had something to read.
    final compressed = await FlutterImageCompress.compressWithList(
      frame,
      minWidth: 1536,
      minHeight: 1536,
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (compressed.isEmpty) throw StateError('image compression failed');

    final directory = await getApplicationDocumentsDirectory();
    final jpegPath =
        '${directory.path}/capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(jpegPath).writeAsBytes(compressed, flush: true);

    // 2. Object detection — say so rather than burning a generation on a
    // photo of a wall. The camera has already closed, so this reports back
    // over whatever screen they returned to.
    if (!await ObjectDetector.hasDetectableObject(jpegPath)) {
      try {
        await File(jpegPath).delete();
      } catch (_) {
        // Nothing to clean up, then.
      }
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.arNoClearObject),
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    // 3. SHA-256 for deduplication (server will skip GPU if identical image seen before)
    final sha256hex = sha256.convert(compressed).toString();
    // Must be a real UUID: it becomes artifacts.id and model_jobs.artifact_id,
    // both uuid columns. A readable id like "capture-<millis>" is rejected by
    // the column type, which failed every capture before the server even got
    // as far as the foreign key.
    final artifactId = uuidV4();
    final atStop = bloc.state.accepted.isNotEmpty &&
        bloc.state.currentStopIdx < bloc.state.accepted.length;
    final stop = atStop ? bloc.state.accepted[bloc.state.currentStopIdx] : null;

    // Name by area, numbered within it: algiers_the_casbah_1, _2, … The
    // region is the area proper; a stop whose region the catalogue left
    // blank falls back to its own name so the number still has something
    // meaningful to hang off.
    final area = stop == null
        ? kUnplacedArea
        : stop.region.isNotEmpty
            ? stop.region
            : stop.name.isNotEmpty
                ? stop.name
                : kUnplacedArea;
    // Counts against the whole folder, which by now includes everything
    // restored from Supabase — so numbering keeps climbing across restarts
    // instead of restarting at 1 each launch.
    final captureName = nextArtifactName(bloc.state.capturedArtifacts, area);

    // 4. Add optimistic artifact immediately so the user sees it in the folder
    final artifact = Artifact(
      id: artifactId,
      name: captureName,
      region: area,
      kindLabel: '3D Model',
      photoUrl: jpegPath,
      isLocalFile: true,
      modelStatus: ModelStatus.generating,
      jobId: null,
    );

    // Emit the optimistic state directly (bypassing AddCapturedArtifactEvent
    // because we need the full Artifact, not just the file path)
    bloc.add(OptimisticArtifactEvent(artifact));

    // 5. Dispatch the async upload+generation event
    bloc.add(RequestModelGenerationEvent(
      artifactId: artifactId,
      localImagePath: jpegPath,
      imageBytes: compressed,
      sha256: sha256hex,
      title: captureName,
    ));

    messenger.showSnackBar(SnackBar(
      content: Text(l10n.arGenerating3dModel),
      duration: const Duration(seconds: 4),
    ));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.arCouldNotScanShot(e.toString()))),
    );
  }
}

/// Where the mascot is relative to the camera, as the hint needs it.
class _MascotBearing {
  const _MascotBearing({
    required this.direction,
    required this.distance,
    required this.onScreen,
  });

  /// Unit vector towards the mascot in screen axes (Y down).
  final Offset direction;

  /// Straight-line distance from the camera, in metres.
  final double distance;

  /// Whether it is inside the frame, so the arrow can get out of the way.
  final bool onScreen;
}

/// Points the way to the mascot while it's out of frame.
///
/// Without it, something hidden across the room behind you is found by
/// accident or not at all.
class _EdgeArrow extends StatelessWidget {
  const _EdgeArrow({required this.direction});

  final Offset direction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final centre = Offset(size.width / 2, size.height / 2);
    final reach = math.min(size.width, size.height) * 0.34;
    final position = centre + direction * reach;

    return Positioned(
      left: position.dx - 27,
      top: position.dy - 27,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Transform.rotate(
            angle: math.atan2(direction.dy, direction.dx),
            child: GlassSurface(
              tint: GlassTint.dark,
              borderRadius: AppTheme.brPill,
              padding: const EdgeInsets.all(14),
              child: const Icon(Icons.arrow_forward,
                  color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the pair under a frozen frame: retake, or keep.
class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// True for the accepting half, which is filled to say it is the way on.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? AppTheme.onAccent : Colors.white;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: foreground),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    return PressableScale(
      onTap: onTap,
      child: filled
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: AppTheme.brPill,
                boxShadow: AppTheme.shadowLg,
              ),
              child: content,
            )
          : GlassSurface(
              tint: GlassTint.dark,
              borderRadius: AppTheme.brPill,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: content,
            ),
    );
  }
}

/// Replays a just-filmed clip, looping, while it is kept or discarded.
///
/// Owns its own controller so the capture screen does not have to thread one
/// through its lifecycle: building this widget starts playback and disposing
/// it releases the decoder, which is exactly the lifetime the review has.
///
/// Looping rather than playing once and stopping on a black frame — the
/// decision being made is "is this clip any good", and that is easier to answer
/// while it is running than from a still of wherever it happened to end.
class _ClipReview extends StatefulWidget {
  const _ClipReview({super.key, required this.path});

  final String path;

  @override
  State<_ClipReview> createState() => _ClipReviewState();
}

class _ClipReviewState extends State<_ClipReview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(File(widget.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      // The clip exists but will not decode. Saying so beats a black rectangle
      // the traveller would read as a broken app rather than a broken file.
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              AppLocalizations.of(context).arClipWontPlayBack,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
          ),
        ),
      );
    }

    // Cover, not contain — the replay should sit exactly where the viewfinder
    // was, and letterboxing it would make the clip look like it was framed
    // differently from the shot that was just taken.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

/// What the open quest is asking for, in the mode strip's place.
///
/// The strip is gone because there is nothing to switch between, so this fills
/// the same slot rather than leaving a gap and shifting the shutter up the
/// screen. It states the requirement plainly — including the minimum length,
/// which is the one rule a traveller could otherwise only discover by failing
/// it.
class _IntentPill extends StatelessWidget {
  const _IntentPill({required this.intent});

  final CaptureIntent intent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (IconData icon, String text) = switch (intent) {
      CaptureIntent.video => (
          Icons.videocam_rounded,
          l10n.arHoldToFilmMinimum(_kMinQuestClip.inSeconds),
        ),
      _ => (Icons.photo_camera_rounded, l10n.arTapToTakePhoto),
    };

    return SizedBox(
      height: 34,
      child: Center(
        child: GlassSurface(
          tint: GlassTint.dark,
          borderRadius: AppTheme.brPill,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppTheme.sand),
              const SizedBox(width: 7),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The elapsed-time readout, in the mode strip's place while filming.
///
/// It sits exactly where the mode names were rather than somewhere new, so
/// nothing under the thumb moves when recording starts — and the swap itself
/// is the clearest signal that the shutter has changed meaning.
class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.inSeconds;
    final remaining = _kMaxClipDuration.inSeconds - seconds;

    return SizedBox(
      height: 34,
      child: Center(
        child: GlassSurface(
          tint: GlassTint.dark,
          borderRadius: AppTheme.brPill,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '0:${seconds.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              // Only mentioned near the cap: a countdown running from the first
              // second would make a 30-second limit feel like a stopwatch.
              if (remaining <= 10) ...[
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).arSecondsLeft(remaining),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap to shoot, hold to film.
///
/// The hold is deliberately not a `GestureDetector.onLongPress`: that fires
/// once, after the delay, with no signal for the release — and a shutter needs
/// both ends of the press. `onTapDown`/`onTapUp` plus a timer gives the whole
/// gesture: press starts a clock, holding past [_kHoldToFilmDelay] begins
/// filming, and whichever way the finger leaves ends it. A press that lifts
/// before the delay was a tap and takes a photo.
///
/// While filming the button turns red and a white ring fills around its edge.
/// The ring is the clip's remaining length made visible: full means the
/// thirty-second cap has been reached and the take has ended itself. Without
/// it the cap arrives as a surprise mid-pan, which is the one thing a shutter
/// should never do.
class _ShutterButton extends StatefulWidget {
  const _ShutterButton({
    required this.enabled,
    required this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
    this.recording = false,
    this.progress = 0,
    this.icon = Icons.camera_alt_rounded,
  });

  final bool enabled;
  final VoidCallback onTap;

  /// Null when this shutter cannot film — the hunt, and 3D Scan mode.
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  final bool recording;

  /// How much of the clip's maximum length has been used, 0..1.
  final double progress;

  /// Says what kind of shot this is about to take — the mode strip above says
  /// it in words, this says it where the thumb already is.
  final IconData icon;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  Timer? _holdTimer;
  bool _pressed = false;
  bool _heldLongEnough = false;

  bool get _canFilm => widget.onHoldStart != null;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onDown() {
    if (!widget.enabled && !widget.recording) return;
    setState(() => _pressed = true);
    _heldLongEnough = false;
    if (!_canFilm) return;

    _holdTimer = Timer(_kHoldToFilmDelay, () {
      _heldLongEnough = true;
      widget.onHoldStart?.call();
    });
  }

  void _onUp({required bool cancelled}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_pressed) return;
    setState(() => _pressed = false);

    if (_heldLongEnough) {
      _heldLongEnough = false;
      widget.onHoldEnd?.call();
      return;
    }
    // A drag off the button cancels rather than shoots — the same escape hatch
    // every button has, and the only way out of an accidental press.
    if (!cancelled && widget.enabled) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.recording;
    final live = widget.enabled || recording;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _onDown(),
      onTapUp: (_) => _onUp(cancelled: false),
      onTapCancel: () => _onUp(cancelled: true),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recording
                      ? AppTheme.error
                      : live
                          ? AppTheme.accent
                          : Colors.white24,
                  // While filming the ring below is the border, so the static
                  // one steps aside rather than sitting under it at a slightly
                  // different radius.
                  border: recording
                      ? null
                      : Border.all(color: Colors.white70, width: 3),
                  boxShadow: live ? AppTheme.shadowLg : null,
                ),
              ),

              if (recording) ...[
                // The unfilled track, so the ring reads as a gauge with a
                // remainder rather than an arc that appeared from nowhere.
                SizedBox(
                  width: 74,
                  height: 74,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.28)),
                  ),
                ),
                SizedBox(
                  width: 74,
                  height: 74,
                  child: CircularProgressIndicator(
                    value: widget.progress.clamp(0.0, 1.0),
                    strokeWidth: 3.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                // A circle, not a square: the take ends when the finger lifts,
                // so this is a recording indicator rather than a stop button,
                // and a square would invite a press that does nothing.
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ] else
                Icon(
                  widget.icon,
                  color: live ? AppTheme.onAccent : Colors.white54,
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

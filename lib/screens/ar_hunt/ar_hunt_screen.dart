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
import '../../utils/artifact_naming.dart';
import '../../utils/uuid.dart';
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

  /// The mascot's real geographic spawn point, from the proximity hunt
  /// (`HuntRadarScreen`) that led here. When set, [spot] is replaced at
  /// session start by the true bearing to this point combined with the
  /// device's heading — §5.5's bearing-preserving placement — rather than the
  /// fixed default.
  final LatLng? spawnLocation;

  /// The backend spawn id, forwarded from [HuntRadarScreen] when a real
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
  bool _busy = false;
  bool _floorMeasured = false;
  String? _error;

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

  /// Whether the shutter is live. Plain capture can shoot as soon as there is
  /// a session to snapshot; a hunt only once the fennec has been caught.
  bool get _canShoot =>
      !_busy && _session != null && (!_hunting || _stage == _Stage.caught);

  @override
  void initState() {
    super.initState();
    if (_hunting) _loadBounds();
    if (_hunting && widget.spawnLocation != null) {
      _geoOffsetFuture = _resolveGeoOffset();
    }
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _poseTimer?.cancel();
    _refineTimer?.cancel();
    _ar?.dispose();
    super.dispose();
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
      if (mounted) setState(() => _error = 'Could not read the mascot model.');
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
        _error = 'Could not place the fennec. Try again in a moment.';
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

  Future<void> _capture() async {
    final session = _session;
    if (session == null || _busy) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final bloc = context.read<AppBloc>();
    final navigator = Navigator.of(context);

    try {
      final image = await session.snapshot();
      if (image is! MemoryImage) {
        throw StateError('unexpected snapshot format');
      }

      // Save raw PNG so the capture appears in the folder immediately
      final directory = await getApplicationDocumentsDirectory();
      final rawPath = '${directory.path}/capture_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(rawPath).writeAsBytes(image.bytes, flush: true);

      // In capture mode: run the full 3D generation pipeline
      if (!_hunting) {
        // 1. Compress to JPEG + strip EXIF (privacy + bandwidth)
        final compressed = await FlutterImageCompress.compressWithFile(
          rawPath,
          minWidth: 1536,
          minHeight: 1536,
          quality: 85,
          format: CompressFormat.jpeg,
          keepExif: false,
        );

        if (compressed == null || compressed.isEmpty) {
          throw StateError('image compression failed');
        }

        // 2. Object detection — tell user if no scan-worthy object found
        final jpegPath = rawPath.replaceAll('.png', '.jpg');
        await File(jpegPath).writeAsBytes(compressed, flush: true);

        final hasObject = await ObjectDetector.hasDetectableObject(jpegPath);
        if (!hasObject) {
          if (!mounted) return;
          setState(() => _busy = false);
          messenger.showSnackBar(const SnackBar(
            content: Text(
              'No clear object found — try filling more of the frame with the subject',
            ),
            duration: Duration(seconds: 3),
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

        navigator.pop();
        messenger.showSnackBar(const SnackBar(
          content: Text('Generating 3D model — check your folder in a moment'),
          duration: Duration(seconds: 4),
        ));
      } else {
        // Hunt mode: save photo locally first so the folder is updated
        // immediately regardless of network state.
        bloc.add(AddCapturedArtifactEvent(rawPath));

        // Submit the capture to the backend when we have a real spawn + token.
        // Best-effort: a network failure never blocks the folder or the pop.
        final spawnId = widget.spawnId;
        final captureToken = widget.captureToken;
        if (spawnId != null && captureToken != null) {
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.best),
            ).timeout(const Duration(seconds: 3));
            await MascotRepository.submitCapture(
              spawnId: spawnId,
              captureToken: captureToken,
              fix: LatLng(pos.latitude, pos.longitude),
              accuracyMeters: pos.accuracy,
              clientTs: DateTime.now().toUtc().toIso8601String(),
              nonce: uuidV4(),
              arTelemetry: {
                'stage': _stage.name,
                'floor_measured': _floorMeasured,
              },
            );
          } catch (_) {
            // Non-fatal — the photo is already saved locally.
          }
        }

        if (!mounted) return;
        
        if (_node != null && _objects != null) {
          _objects!.playAnimation(nodeName: _node!.name, animationName: 'Death', loop: false);
          // Let the user see the death animation before popping
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!mounted) return;
        }
        
        navigator.pop();
        messenger.showSnackBar(const SnackBar(
          content: Text('Fennec caught — saved to your folder'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't save that shot: ${e.toString()}")),
      );
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
    final hunting = _hunting &&
        (_stage == _Stage.placed || _stage == _Stage.caught);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ArSessionHost(
            onSessionCreated: _onSessionCreated,
            // Horizontal only: the fennec stands on the floor, and tracking
            // walls as well only slows the search for a surface.
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
            permissionDenied: _buildPermissionPrompt,
          ),
          if (hunting && bearing != null && !bearing.onScreen)
            _EdgeArrow(direction: bearing.direction),
          _buildChrome(context),
        ],
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
                    ? 'The hunt needs the camera to see the room around you.'
                    : 'Taking a photo needs the camera.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: retry,
                child: const Text('Allow camera'),
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
                          _hunting ? 'Find the fennec' : 'Take a photo',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.stopName ??
                              (_hunting
                                  ? 'Somewhere around you'
                                  : 'It goes straight to your folder'),
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
          if (_error != null) _buildError() else _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final bearing = _bearing;
    final (label, hint) = !_hunting
        ? ('Camera', 'Frame the shot and tap the shutter')
        : switch (_stage) {
            _Stage.scanning => (
                'Reading the room',
                'Hold the phone up and move it slowly',
              ),
            _Stage.placing => (
                'Letting the fennec out',
                'Hold steady for a second',
              ),
            _Stage.placed => (
                bearing?.onScreen ?? false
                    ? 'There it is — tap it'
                    : 'It is out there — follow the arrow',
                'Walk around it to see it from any side',
              ),
            _Stage.caught => (
                'Found it',
                'Frame the shot and take your photo',
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
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_hunting && bearing != null && _stage == _Stage.placed) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${bearing.distance.toStringAsFixed(1)} m away',
                    style: const TextStyle(
                      color: AppTheme.accentSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_hunting && _stage == _Stage.placed && !_floorMeasured) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Floor estimated — it settles itself as the room is mapped',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.accentSoft,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _ShutterButton(enabled: _canShoot, onTap: _capture),
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
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
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

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? AppTheme.accent : Colors.white24,
          border: Border.all(color: Colors.white70, width: 3),
          boxShadow: enabled ? AppTheme.shadowLg : null,
        ),
        child: Icon(
          Icons.camera_alt_rounded,
          color: enabled ? AppTheme.onAccent : Colors.white54,
          size: 28,
        ),
      ),
    );
  }
}

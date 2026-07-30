import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// Where the phone is and which way it is pointing, in AR world coordinates.
class ArCameraPose {
  ArCameraPose({required this.position, required this.rotation});

  /// Metres from the session origin.
  final vm.Vector3 position;

  /// Camera orientation. Columns are its right, up and backward axes, so the
  /// direction the lens faces is the negated third column.
  final vm.Matrix3 rotation;

  vm.Vector3 get forward => -rotation.transformed(vm.Vector3(0, 0, 1));
  vm.Vector3 get right => rotation.transformed(vm.Vector3(1, 0, 0));
  vm.Vector3 get up => rotation.transformed(vm.Vector3(0, 1, 0));

  /// [worldPoint] expressed in camera axes: +X right, +Y up, -Z ahead.
  vm.Vector3 toCameraSpace(vm.Vector3 worldPoint) {
    final offset = worldPoint - position;
    return vm.Vector3(
      offset.dot(right),
      offset.dot(up),
      -offset.dot(forward),
    );
  }
}

/// A live AR session: the plugin's managers, plus the pieces of the platform
/// channel the plugin gets wrong.
class ArSession {
  ArSession({
    required this.viewId,
    required this.sessionManager,
    required this.objectManager,
    required this.anchorManager,
  }) : _channel = MethodChannel('arsession_$viewId');

  final int viewId;
  final ARSessionManager sessionManager;
  final ARObjectManager objectManager;
  final ARAnchorManager anchorManager;

  final MethodChannel _channel;

  /// Reads the camera pose straight off the platform channel.
  ///
  /// [ARSessionManager.getCameraPose] can't be used: it asks for a `List`,
  /// which is what the iOS side sends, but the Android side sends a `Map` of
  /// position and rotation. The mismatch throws, the plugin swallows it, and
  /// every call returns null on Android. Parsing both shapes here fixes it
  /// without forking the plugin — the managers take a platform view id in
  /// their public constructors, so [ArSessionHost] hosts the view itself to
  /// learn that id and this channel can then address the same session.
  Future<ArCameraPose?> cameraPose() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('getCameraPose', {});
      return _decodePose(result);
    } catch (_) {
      return null;
    }
  }

  void dispose() => sessionManager.dispose();
}

/// Turns either serialisation the platforms use into a pose.
@visibleForTesting
ArCameraPose? decodeArCameraPose(dynamic payload) => _decodePose(payload);

ArCameraPose? _decodePose(dynamic payload) {
  if (payload is Map) {
    final position = payload['position'];
    final rotation = payload['rotation'];
    if (position is! Map || rotation is! Map) return null;
    return ArCameraPose(
      position: vm.Vector3(
        _toDouble(position['x']),
        _toDouble(position['y']),
        _toDouble(position['z']),
      ),
      rotation: _rotationFromQuaternion(
        _toDouble(rotation['x']),
        _toDouble(rotation['y']),
        _toDouble(rotation['z']),
        _toDouble(rotation['w']),
      ),
    );
  }

  // iOS sends the 4x4 camera transform, column-major.
  if (payload is List && payload.length >= 16) {
    final m = payload.map(_toDouble).toList();
    return ArCameraPose(
      position: vm.Vector3(m[12], m[13], m[14]),
      rotation: vm.Matrix3(
        m[0], m[1], m[2],
        m[4], m[5], m[6],
        m[8], m[9], m[10],
      ),
    );
  }
  return null;
}

double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

/// Builds a rotation matrix from a unit quaternion.
///
/// Written out rather than going through `Quaternion`, whose `rotate` applies
/// `conj(q)·v·q` — the transpose of the usual convention — which makes mixing
/// it with matrix code a reliable source of inverted rotations.
vm.Matrix3 _rotationFromQuaternion(double x, double y, double z, double w) {
  final length = math.sqrt(x * x + y * y + z * z + w * w);
  if (length < 1e-9) return vm.Matrix3.identity();
  x /= length;
  y /= length;
  z /= length;
  w /= length;

  final matrix = vm.Matrix3.identity();
  matrix.setEntry(0, 0, 1 - 2 * (y * y + z * z));
  matrix.setEntry(0, 1, 2 * (x * y - z * w));
  matrix.setEntry(0, 2, 2 * (x * z + y * w));
  matrix.setEntry(1, 0, 2 * (x * y + z * w));
  matrix.setEntry(1, 1, 1 - 2 * (x * x + z * z));
  matrix.setEntry(1, 2, 2 * (y * z - x * w));
  matrix.setEntry(2, 0, 2 * (x * z - y * w));
  matrix.setEntry(2, 1, 2 * (y * z + x * w));
  matrix.setEntry(2, 2, 1 - 2 * (x * x + y * y));
  return matrix;
}

/// Hosts the platform AR view directly rather than using the plugin's own
/// `ARView` widget.
///
/// Identical rendering — the same native view type, and the plugin's managers
/// built from their public constructors — but hosting it here means the
/// platform view id stays visible, which is the only way to reach the session
/// channel for the calls the plugin mis-parses. See [ArSession.cameraPose].
class ArSessionHost extends StatefulWidget {
  const ArSessionHost({
    super.key,
    required this.onSessionCreated,
    required this.permissionDenied,
    this.planeDetectionConfig = PlaneDetectionConfig.horizontal,
  });

  final void Function(ArSession session) onSessionCreated;

  /// Shown instead of the camera when permission isn't granted. [retry] asks
  /// again, or opens system settings once the refusal is permanent.
  final Widget Function(BuildContext context, VoidCallback retry)
      permissionDenied;

  final PlaneDetectionConfig planeDetectionConfig;

  @override
  State<ArSessionHost> createState() => _ArSessionHostState();
}

class _ArSessionHostState extends State<ArSessionHost> {
  static const String _viewType = 'ar_flutter_plugin_2';

  PermissionStatus? _cameraPermission;

  @override
  void initState() {
    super.initState();
    _requestCamera();
  }

  // The plugin's own ARView gates the platform view behind this; hosting the
  // view ourselves means owning the gate too, or the session starts against a
  // camera it isn't allowed to open.
  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (status == PermissionStatus.permanentlyDenied &&
        _cameraPermission != null) {
      await openAppSettings();
    }
    if (mounted) setState(() => _cameraPermission = status);
  }

  void _onPlatformViewCreated(int id) {
    widget.onSessionCreated(ArSession(
      viewId: id,
      sessionManager:
          ARSessionManager(id, context, widget.planeDetectionConfig),
      objectManager: ARObjectManager(id),
      anchorManager: ARAnchorManager(id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const creationParams = <String, dynamic>{};

    final permission = _cameraPermission;
    if (permission == null) {
      return const ColoredBox(color: Colors.black);
    }
    if (permission != PermissionStatus.granted &&
        permission != PermissionStatus.limited) {
      return widget.permissionDenied(context, _requestCamera);
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      TargetPlatform.iOS => UiKitView(
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      _ => const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text(
              'AR is only available on Android and iOS',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
    };
  }
}

import 'dart:typed_data';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

/// On-device object detection using Google ML Kit image labeling.
///
/// Runs inference before any upload to tell the user immediately if the frame
/// doesn't contain a clear, scan-worthy object (blank wall, sky, floor, etc.)
/// so they don't burn a 3D generation credit on an unusable photo.
class ObjectDetector {
  ObjectDetector._();

  static ImageLabeler? _labeler;

  static ImageLabeler _getLabeler() {
    return _labeler ??= ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.0),
    );
  }

  /// Returns true if the image contains a scan-worthy object with sufficient
  /// confidence. Returns false if the frame appears to be empty space,
  /// a featureless surface, or otherwise not worth 3D generation.
  static Future<bool> hasDetectableObject(String imagePath) async {
    try {
      final labeler = _getLabeler();
      final inputImage = InputImage.fromFilePath(imagePath);

      final labels = await labeler.processImage(inputImage);

      // The ML Kit base model returns general labels. We gate on:
      // 1. At least one label above 0.55 confidence
      // 2. The top label is not a "background" category
      const backgroundLabels = {
        'sky', 'wall', 'floor', 'ceiling', 'ground', 'road', 'pavement',
        'water', 'grass', 'vegetation', 'nature', 'landscape', 'outdoors',
      };

      for (final label in labels) {
        if (label.confidence >= 0.55) {
          final name = label.label.toLowerCase();
          if (!backgroundLabels.any((bg) => name.contains(bg))) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      // Fail open if the model fails to load or process the image
      return true;
    }
  }

  static Future<void> close() async {
    await _labeler?.close();
    _labeler = null;
  }
}

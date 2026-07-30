import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/icon/app-icon.png');
  final original = img.decodeImage(file.readAsBytesSync());
  if (original == null) return;
  
  // Create a perfectly square canvas to prevent stretching
  final maxDim = original.width > original.height ? original.width : original.height;
  final canvasSize = maxDim;
  
  final dstX = (canvasSize - original.width) ~/ 2;
  final dstY = (canvasSize - original.height) ~/ 2;
  
  // 1. Transparent foreground for adaptive icons
  final transparentSquare = img.Image(width: canvasSize, height: canvasSize, numChannels: 4, withPalette: false);
  img.fill(transparentSquare, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(transparentSquare, original, dstX: dstX, dstY: dstY);
  File('assets/icon/app-icon-transparent.png').writeAsBytesSync(img.encodePng(transparentSquare));
  
  // 2. Solid blue background for iOS and legacy Android
  final blueSquare = img.Image(width: canvasSize, height: canvasSize, numChannels: 4, withPalette: false);
  img.fill(blueSquare, color: img.ColorRgba8(0x14, 0x25, 0x4a, 0xff)); // Dark blue #14254A
  img.compositeImage(blueSquare, original, dstX: dstX, dstY: dstY);
  File('assets/icon/app-icon-blue.png').writeAsBytesSync(img.encodePng(blueSquare));
  
  print('Generated perfectly centered squares at ${canvasSize}x${canvasSize}.');
}

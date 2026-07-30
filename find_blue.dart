import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/icon/app-icon.png');
  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) return;
  final Map<String, int> colors = {};
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final a = pixel.a.toInt();
      if (a > 200 && b > r + 20 && b > g + 20) {
        final hex = '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
        colors[hex] = (colors[hex] ?? 0) + 1;
      }
    }
  }
  final sorted = colors.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print('Top blue colors:');
  for (var i = 0; i < 5 && i < sorted.length; i++) {
    print('${sorted[i].key}: ${sorted[i].value}');
  }
}

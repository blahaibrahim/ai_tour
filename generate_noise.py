import os
import base64
import random
from PIL import Image
import io

img = Image.new('RGBA', (256, 256))
pixels = img.load()
for x in range(256):
    for y in range(256):
        # We want transparent grain.
        # Grayscale noise with alpha
        val = random.randint(0, 255)
        # alpha can be 20 to make it very subtle black noise
        pixels[x, y] = (0, 0, 0, random.randint(0, 30))

buf = io.BytesIO()
img.save(buf, format='PNG')
b64 = base64.b64encode(buf.getvalue()).decode()

dart_code = f"""import 'dart:convert';
import 'dart:typed_data';

final Uint8List noiseTextureData = base64Decode(
  '{b64}',
);
"""
with open('lib/widgets/noise_texture.dart', 'w', encoding='utf-8') as f:
    f.write(dart_code)

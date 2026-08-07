"""Re-centre the app artwork on the fennec's *body circle*, then rebuild the
Android splash bitmaps from it.

Why this exists: the fennec is a round curled body with one ear sticking out to
the upper left. Centring the artwork on its bounding box — which is what any
"centre this image" tool does by default — pushes the round body down and to
the right, because the ear's overhang is counted as if it were part of the
mass. The eye reads the body circle, not the box, so the icon looks off-centre
inside a launcher's circular mask and off-centre on the splash.

So instead of the bounding box, a circle is fitted to the silhouette and *that*
is centred. The fit is a least-squares circle over the alpha boundary, run
repeatedly while discarding the worst 30% of points, so the ear and the compass
lug — which do not lie on the body circle — drop out and the circle converges
onto the fur outline. The ear is then free to poke out of frame's centre; it is
only required not to be cropped, which is asserted below.

Both masters are moved by a whole-pixel translation, so no artwork is
resampled. Run this after replacing the artwork, then regenerate the launcher
icons:

    python tool/center_icon_artwork.py
    flutter pub run flutter_launcher_icons

Needs: pillow, numpy, scipy.
"""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent

# The opaque master, source of the iOS icons and the legacy Android raster.
IOS_MASTER = ROOT / "assets/icon/app-icon-ios.png"
# The keyed-out master, source of the Android adaptive foreground and the
# splash bitmaps.
TRANSPARENT_MASTER = ROOT / "assets/icon/app-icon-transparent.png"

# The navy field baked into the opaque master. Same value as
# @color/splash_background and adaptive_icon_background.
NAVY = (0x19, 0x27, 0x4C)

RES = ROOT / "android/app/src/main/res"
# mdpi is the 1x baseline; the rest are the standard Android density buckets.
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
# Size of the pre-Android-12 splash logo, drawn at its intrinsic size by
# drawable/launch_background.xml.
SPLASH_LOGO_DP = 160
# Android 12+ hands the animated splash icon a 288dp canvas and only guarantees
# the inner two thirds (192dp) is shown. Reusing SPLASH_LOGO_DP for the artwork
# inside it keeps the two splashes the same apparent size and stays well within
# that safe area.
SPLASH_ICON_DP = 288


def body_circle(mask):
    """Fit a circle to the fennec's body, ignoring the ear and compass lug."""
    edge = mask & ~ndimage.binary_erosion(mask)
    ys, xs = np.where(edge)
    pts = np.stack([xs, ys], 1).astype(float)
    cx = cy = r = 0.0
    for _ in range(15):
        # Algebraic circle fit: x²+y² = 2cx·x + 2cy·y + (r²-cx²-cy²).
        a = np.c_[2 * pts[:, 0], 2 * pts[:, 1], np.ones(len(pts))]
        cx, cy, k = np.linalg.lstsq(a, (pts**2).sum(1), rcond=None)[0]
        r = np.sqrt(k + cx * cx + cy * cy)
        residual = np.abs(np.hypot(pts[:, 0] - cx, pts[:, 1] - cy) - r)
        # Keep the 70% of the outline closest to the current circle. The ear is
        # the bulk of what this throws away.
        pts = pts[residual < max(np.percentile(residual, 70), 6.0)]
    return cx, cy, r


def alpha_mask(image):
    return ndimage.binary_fill_holes(np.array(image.convert("RGBA"))[:, :, 3] > 32)


def navy_mask(image):
    rgb = np.array(image.convert("RGB")).astype(int)
    return ndimage.binary_fill_holes(np.abs(rgb - np.array(NAVY)).max(2) > 24)


def recentre(path, mask_of, fill):
    """Translate the artwork in `path` so its body circle sits at the centre."""
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    mask = mask_of(image)
    cx, cy, r = body_circle(mask)
    dx, dy = round(w / 2 - cx), round(h / 2 - cy)

    ys, xs = np.where(mask)
    left, right = xs.min() + dx, w - 1 - xs.max() - dx
    top, bottom = ys.min() + dy, h - 1 - ys.max() - dy
    # The ear may poke past the body circle; it may not poke past the canvas.
    assert min(left, right, top, bottom) >= 0, (
        f"{path.name}: centring would crop the artwork "
        f"(margins l={left} r={right} t={top} b={bottom})"
    )

    moved = Image.new("RGBA", (w, h), fill)
    moved.alpha_composite(image, dest=(max(dx, 0), max(dy, 0)),
                          source=(max(-dx, 0), max(-dy, 0)))
    moved.convert(Image.open(path).mode).save(path)
    print(f"{path.name}: circle ({cx:.0f},{cy:.0f}) r={r:.0f} -> shift ({dx:+d},{dy:+d}), "
          f"margins l={left} r={right} t={top} b={bottom}")
    return moved


def write_splash(master):
    """Rebuild the splash bitmaps at every density from the centred master.

    The master's canvas maps onto the splash canvas, so the body circle lands
    on the canvas centre and `android:gravity="center"` puts it on the screen
    centre.
    """
    for bucket, scale in DENSITIES.items():
        out = RES / f"drawable-{bucket}"
        logo_px = round(SPLASH_LOGO_DP * scale)
        logo = master.resize((logo_px, logo_px), Image.LANCZOS)
        logo.save(out / "splash_logo.png")

        icon_px = round(SPLASH_ICON_DP * scale)
        icon = Image.new("RGBA", (icon_px, icon_px), (0, 0, 0, 0))
        offset = (icon_px - logo_px) // 2
        icon.paste(logo, (offset, offset))
        icon.save(out / "splash_icon.png")
        print(f"drawable-{bucket}: splash_logo {logo_px}px, splash_icon {icon_px}px")


if __name__ == "__main__":
    recentre(IOS_MASTER, navy_mask, NAVY + (255,))
    transparent = recentre(TRANSPARENT_MASTER, alpha_mask, (0, 0, 0, 0))
    write_splash(transparent)

"""Generates KeepIt brand assets: app icons (Android/iOS/web), Play Store icon
and feature graphic. Run: python3 store_assets/generate_assets.py"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "flutter_app")
OUT = os.path.join(ROOT, "store_assets")
S = 1024  # master size

CORAL_TOP = (255, 138, 101)
CORAL = (255, 91, 55)
CORAL_DEEP = (224, 60, 28)


def gradient(size, c1, c2, c3=None):
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.45 + y / h * 0.55)
            if c3 is None:
                c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
            elif t < 0.5:
                k = t / 0.5
                c = tuple(int(c1[i] + (c2[i] - c1[i]) * k) for i in range(3))
            else:
                k = (t - 0.5) / 0.5
                c = tuple(int(c2[i] + (c3[i] - c2[i]) * k) for i in range(3))
            px[x, y] = c
    return img


def star(cx, cy, r_out, r_in, points=4):
    import math
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.pi / points * i - math.pi / 2
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def glyph(size, scale=1.0, color=(255, 255, 255, 255), shadow=True):
    """White bookmark with a notch + 4-point spark, on transparent bg."""
    ss = 4
    W = size * ss
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = W / 2
    bw, bh = W * 0.40 * scale, W * 0.52 * scale
    left, top = c - bw / 2, c - bh / 2 + W * 0.02 * scale
    right, bottom = left + bw, top + bh
    rad = bw * 0.16
    notch = bh * 0.22
    # bookmark body: rounded top corners, V notch cut into the bottom
    d.rounded_rectangle([left, top, right, top + rad * 3], radius=rad, fill=color)
    d.polygon([(left, top + rad), (right, top + rad), (right, bottom),
               (c, bottom - notch), (left, bottom)], fill=color)
    # spark cut-out (coral) inside bookmark
    spark = star(c, top + bh * 0.36, bw * 0.28, bw * 0.08)
    d.polygon(spark, fill=(0, 0, 0, 0))
    # small sparkle top-right
    d.polygon(star(right + bw * 0.02, top - bh * 0.02, bw * 0.16, bw * 0.045), fill=color)
    layer = layer.resize((size, size), Image.LANCZOS)
    if not shadow:
        return layer
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    alpha = layer.split()[3].point(lambda a: int(a * 0.28))
    sh.putalpha(alpha)
    sh = Image.merge("RGBA", (Image.new("L", layer.size, 120),) * 3 + (alpha,))
    sh = sh.filter(ImageFilter.GaussianBlur(size * 0.02))
    base = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    base.alpha_composite(sh, (0, int(size * 0.015)))
    base.alpha_composite(layer)
    return base


def spark_fill(img, size, scale):
    """Fill the spark cut-out with the gradient (so it reads as coral)."""
    return img


def master_icon(size=S, rounded=False, scale=1.0):
    bg = gradient((size, size), CORAL_TOP, CORAL, CORAL_DEEP).convert("RGBA")
    # soft highlight
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-size * 0.2, -size * 0.35, size * 0.9, size * 0.55], fill=(255, 255, 255, 38))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(size * 0.08)))
    bg.alpha_composite(glyph(size, scale))
    if rounded:
        m = Image.new("L", (size * 4, size * 4), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, size * 4, size * 4], radius=size * 4 * 0.22, fill=255)
        bg.putalpha(m.resize((size, size), Image.LANCZOS))
    return bg


def save(img, path, size, mode="RGBA"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = img.resize((size, size), Image.LANCZOS)
    if mode == "RGB":
        im = im.convert("RGB")
    im.save(path, optimize=True)


def main():
    full = master_icon(S)                 # square, full-bleed (iOS, Play)
    legacy = master_icon(S, rounded=True)  # rounded (Android legacy launcher)

    # --- Android legacy mipmaps ---
    dens = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    res = os.path.join(APP, "android/app/src/main/res")
    for d, px in dens.items():
        save(legacy, f"{res}/mipmap-{d}/ic_launcher.png", px)

    # --- Android adaptive icon (API 26+) ---
    fg_dens = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    fg = glyph(S, scale=0.66)  # inside 66% safe zone
    mono = glyph(S, scale=0.66, shadow=False)
    for d, px in fg_dens.items():
        save(fg, f"{res}/drawable-{d}/ic_launcher_foreground.png", px)
        save(mono, f"{res}/drawable-{d}/ic_launcher_monochrome.png", px)
    os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
    with open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w") as f:
        f.write("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
""")
    with open(f"{res}/drawable/ic_launcher_background.xml", "w") as f:
        f.write("""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#FF8A65"
        android:centerColor="#FF5B37"
        android:endColor="#E03C1C"
        android:type="linear"/>
</shape>
""")
    # Notification small icon: white silhouette on transparent.
    nd = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
    for d, px in nd.items():
        save(glyph(S, scale=1.25, shadow=False), f"{res}/drawable-{d}/ic_stat_keepit.png", px)

    # --- iOS (no alpha allowed) ---
    ios = os.path.join(APP, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for name in os.listdir(ios):
        if name.endswith(".png"):
            px = Image.open(os.path.join(ios, name)).size[0]
            save(full, os.path.join(ios, name), px, mode="RGB")

    # --- macOS ---
    mac = os.path.join(APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    if os.path.isdir(mac):
        for name in os.listdir(mac):
            if name.endswith(".png"):
                px = Image.open(os.path.join(mac, name)).size[0]
                save(legacy, os.path.join(mac, name), px)

    # --- Web ---
    web = os.path.join(APP, "web")
    save(legacy, f"{web}/favicon.png", 32)
    save(legacy, f"{web}/icons/Icon-192.png", 192)
    save(legacy, f"{web}/icons/Icon-512.png", 512)
    save(full, f"{web}/icons/Icon-maskable-192.png", 192)
    save(full, f"{web}/icons/Icon-maskable-512.png", 512)

    # --- Play Store listing ---
    save(full, f"{OUT}/play_store_icon_512.png", 512, mode="RGB")
    feature_graphic()
    print("Assets generated.")


def font(size, bold=True):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/Library/Fonts/Arial Bold.ttf", "C:/Windows/Fonts/arialbd.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def feature_graphic():
    W, H = 1024, 500
    img = gradient((W, H), CORAL_TOP, CORAL, CORAL_DEEP).convert("RGBA")
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse([-200, -300, 600, 350], fill=(255, 255, 255, 40))
    g.ellipse([700, 250, 1200, 700], fill=(120, 20, 0, 50))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))

    # icon tile
    tile = master_icon(300, rounded=True)
    sh = Image.new("RGBA", (360, 360), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([30, 40, 330, 340], radius=66, fill=(90, 20, 0, 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)), (54, 70))
    ring = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle([0, 0, 299, 299], radius=66, outline=(255, 255, 255, 110), width=4)
    tile.alpha_composite(ring)
    img.alpha_composite(tile, (84, 100))

    d = ImageDraw.Draw(img)
    d.text((440, 128), "KeepIt", font=font(96), fill=(255, 255, 255))
    d.text((444, 246), "Your visual second brain", font=font(38, bold=False), fill=(255, 255, 255, 235))
    d.text((444, 312), "Save reels, articles & ideas in 1 tap.", font=font(26, bold=False), fill=(255, 238, 230))
    d.text((444, 350), "Never forget what you save.", font=font(26, bold=False), fill=(255, 238, 230))
    img.convert("RGB").save(f"{OUT}/feature_graphic_1024x500.png", optimize=True)


if __name__ == "__main__":
    main()

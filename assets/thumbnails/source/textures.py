"""Procedural textures for the Get Funded! thumbnails: faces, charts, skyline, emblem."""
from PIL import Image, ImageDraw, ImageFilter
import math, random, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tex")
os.makedirs(OUT, exist_ok=True)

INK = (22, 16, 40, 255)
GREEN = (30, 232, 120)
RED = (255, 58, 96)
GOLD = (255, 214, 64)


# ---------------------------------------------------------------- faces
def face(name, expr, gaze=(0.0, 0.0)):
    S = 1024
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    gx, gy = gaze

    def eye(cx, cy, w, h, lid=0.0):
        # white
        d.ellipse([cx - w, cy - h, cx + w, cy + h], fill=(255, 255, 255, 255), outline=INK, width=16)
        # pupil
        pr = int(w * 0.62)
        px, py = cx + gx * w * 0.38, cy + gy * h * 0.30
        d.ellipse([px - pr, py - pr * 1.12, px + pr, py + pr * 1.12], fill=INK)
        # highlights
        d.ellipse([px - pr * 0.55, py - pr * 0.85, px - pr * 0.05, py - pr * 0.3], fill=(255, 255, 255, 255))
        d.ellipse([px + pr * 0.2, py + pr * 0.25, px + pr * 0.45, py + pr * 0.5], fill=(255, 255, 255, 230))
        if lid > 0:  # determined upper lid (flat cut)
            d.polygon([(cx - w - 12, cy - h - 12), (cx + w + 12, cy - h - 12),
                       (cx + w + 12, cy - h + lid * h * (1.4 if cx > S / 2 else 0.6)),
                       (cx - w - 12, cy - h + lid * h * (0.6 if cx > S / 2 else 1.4))],
                      fill=(0, 0, 0, 0))

    def brow(x0, y0, x1, y1, t=46):
        d.line([(x0, y0), (x1, y1)], fill=INK, width=t)
        for (x, y) in ((x0, y0), (x1, y1)):
            d.ellipse([x - t / 2, y - t / 2, x + t / 2, y + t / 2], fill=INK)


    def mouth(box, teeth=0.28, tongue=True, shape="D"):
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        m = Image.new("L", (S, S), 0)
        md = ImageDraw.Draw(m)
        if shape == "D":
            md.chord([x0, y0 - h, x1, y1], 0, 180, fill=255)
        else:
            md.ellipse([x0, y0, x1, y1], fill=255)
        inner = Image.new("RGBA", (S, S), (125, 22, 52, 255))
        idr = ImageDraw.Draw(inner)
        if tongue:
            idr.ellipse([x0 + w * 0.22, y1 - h * 0.42, x1 - w * 0.22, y1 + h * 0.25], fill=(255, 112, 140, 255))
        if teeth:
            idr.rectangle([0, 0, S, y0 + h * teeth], fill=(255, 255, 255, 255))
        # outline
        o = m.filter(ImageFilter.MaxFilter(33))
        im.paste(INK, (0, 0), o)
        im.paste(inner, (0, 0), m)

    cheek = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cheek)
    for cx in (230, 794):
        cd.ellipse([cx - 95, 610 - 50, cx + 95, 610 + 50], fill=(255, 110, 120, 120))
    cheek = cheek.filter(ImageFilter.GaussianBlur(22))

    if expr == "determined":
        eye(340, 430, 105, 125)
        eye(684, 430, 105, 125)
        # cut lids for a focused squint
        d.polygon([(220, 280), (470, 280), (470, 350), (220, 320)], fill=(0, 0, 0, 0))
        d.polygon([(554, 280), (804, 280), (804, 320), (554, 350)], fill=(0, 0, 0, 0))
        d.line([(228, 322), (462, 352)], fill=INK, width=18)
        d.line([(562, 352), (796, 322)], fill=INK, width=18)
        brow(230, 250, 450, 300)
        brow(574, 300, 794, 250)
        # confident grin with teeth
        mouth((340, 600, 700, 790), teeth=0.30)
    elif expr == "cheer":
        # happy closed ^ ^ eyes
        for cx in (340, 684):
            d.arc([cx - 115, 340, cx + 115, 540], 200, 340, fill=INK, width=44)
        brow(230, 260, 440, 215)
        brow(584, 215, 794, 260)
        # huge open D mouth
        mouth((280, 560, 744, 880), teeth=0.22)
    elif expr == "surprised":
        eye(340, 420, 118, 140)
        eye(684, 420, 118, 140)
        brow(230, 210, 450, 190)
        brow(574, 190, 794, 210)
                # open "whoa" mouth
        mouth((420, 620, 604, 850), teeth=0.18, shape="O")
    im = Image.alpha_composite(cheek, im)
    im.save(os.path.join(OUT, f"face_{name}.png"))


# ---------------------------------------------------------------- charts
def candles_series(kind, n, seed):
    rnd = random.Random(seed)
    closes = []
    p = 100.0
    for i in range(n):
        t = i / (n - 1)
        if kind == "focus":
            drift = 0.55 + 1.6 * math.sin(t * 5.2) * 0.4
            step = drift + rnd.gauss(0, 1.5)
        elif kind == "win":
            step = (0.4 if t < 0.35 else 2.4 + 2.2 * t) + rnd.gauss(0, 1.1)
            if 0.3 < t < 0.38:
                step -= 2.2
        elif kind == "challenge":
            if t < 0.28:
                step = 0.9 + rnd.gauss(0, 1.1)
            elif t < 0.58:
                step = -3.6 + rnd.gauss(0, 1.3)
            else:
                step = 3.9 + rnd.gauss(0, 1.5)
        else:
            step = rnd.gauss(0.2, 1.4)
        o = p
        p = p + step
        c = p
        hi = max(o, c) + abs(rnd.gauss(0, 1.3)) + 0.4
        lo = min(o, c) - abs(rnd.gauss(0, 1.3)) - 0.4
        closes.append((o, hi, lo, c))
    return closes


def chart(name, kind, W=1600, H=900, n=26, seed=3, highlight_last=True, glow_line=False):
    bg = Image.new("RGB", (W, H), (6, 18, 56))
    d = ImageDraw.Draw(bg)
    # vertical gradient
    for y in range(H):
        k = y / H
        d.line([(0, y), (W, y)], fill=(int(8 + 10 * k), int(22 + 8 * k), int(66 + 24 * k)))
    # grid
    for gx in range(0, W, W // 8):
        d.line([(gx, 0), (gx, H)], fill=(22, 50, 110), width=2)
    for gy in range(0, H, H // 6):
        d.line([(0, gy), (W, gy)], fill=(22, 50, 110), width=2)
    data = candles_series(kind, n, seed)
    lo = min(c[2] for c in data)
    hi = max(c[1] for c in data)
    pad_t, pad_b, pad_l, pad_r = H * 0.10, H * 0.14, W * 0.05, W * 0.08
    def Y(v):
        return pad_t + (hi - v) / (hi - lo) * (H - pad_t - pad_b)
    step = (W - pad_l - pad_r) / n
    bw = step * 0.62
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    pts = []
    for i, (o, h, l, c) in enumerate(data):
        x = pad_l + step * (i + 0.5)
        col = GREEN if c >= o else RED
        for dd, lw, bwk in ((gd, 16, 1.3), (d, 9, 1.0)):
            dd.line([(x, Y(h)), (x, Y(l))], fill=col, width=lw)
            y0, y1 = sorted((Y(o), Y(c)))
            if y1 - y0 < 8:
                y1 = y0 + 8
            b = bw * bwk / 2
            dd.rounded_rectangle([x - b, y0, x + b, y1], radius=6, fill=col)
        # shiny top highlight
        y0, y1 = sorted((Y(o), Y(c)))
        if y1 - y0 > 24:
            d.rounded_rectangle([x - bw / 2 + 7, y0 + 6, x - bw / 2 + 17, y1 - 6], radius=4,
                                fill=tuple(min(255, v + 90) for v in col))
        pts.append((x, Y(c)))
    if glow_line:
        for dd, lw, colr in ((gd, 26, GOLD), (d, 10, (255, 236, 150))):
            dd.line(pts, fill=colr, width=lw, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    out = Image.blend(bg, Image.eval(glow, lambda v: v), 0.0)
    out = Image.composite(out, out, Image.new("L", (W, H), 255))
    from PIL import ImageChops
    out = ImageChops.add(bg, glow.point(lambda v: int(v * 0.45)))
    d = ImageDraw.Draw(out)
    # current-price line
    lastc = data[-1][3]
    yl = Y(lastc)
    colr = GREEN if data[-1][3] >= data[-1][0] else RED
    for xx in range(0, W, 36):
        d.line([(xx, yl), (xx + 18, yl)], fill=(120, 220, 255), width=3)
    d.rounded_rectangle([W - pad_r + 10, yl - 26, W - 8, yl + 26], radius=12, fill=(4, 221, 255))
    # volume bars
    for i, (o, h, l, c) in enumerate(data):
        x = pad_l + step * (i + 0.5)
        vh = 20 + abs(c - o) * 9
        col = GREEN if c >= o else RED
        d.rectangle([x - bw / 2, H - 14 - vh, x + bw / 2, H - 14], fill=tuple(int(v * 0.55) for v in col))
    # bezel inner vignette
    vign = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vign)
    vd.rectangle([0, 0, W, H], outline=255, width=40)
    vign = vign.filter(ImageFilter.GaussianBlur(40))
    out = Image.composite(Image.new("RGB", (W, H), (2, 8, 30)), out, vign.point(lambda v: v // 2))
    out.save(os.path.join(OUT, f"chart_{name}.png"))


def skyline():
    W, H = 2048, 1024
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        k = y / H
        d.line([(0, y), (W, y)], fill=(int(40 + 60 * k), int(20 + 20 * k), int(110 + 60 * k)))
    rnd = random.Random(7)
    layers = [((46, 34, 120), 250, 560, 1.0), ((22, 18, 70), 160, 420, 1.2)]
    for col, hmin, hmax, wm in layers:
        x = -20
        while x < W:
            w = int(rnd.randint(90, 200) * wm)
            h = rnd.randint(hmin, hmax)
            d.rectangle([x, H - h, x + w, H], fill=col)
            for wy in range(H - h + 24, H - 20, 34):
                for wx in range(x + 14, x + w - 14, 30):
                    if rnd.random() < 0.35:
                        c = rnd.choice([(255, 214, 110), (120, 220, 255), (200, 150, 255)])
                        d.rectangle([wx, wy, wx + 12, wy + 16], fill=c)
            x += w + rnd.randint(4, 30)
    im.save(os.path.join(OUT, "skyline.png"))


def emblem():
    """Original Get Funded! badge: three rising candles over a gold arrow on a round badge."""
    S = 1024
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([40, 40, S - 40, S - 40], fill=(255, 205, 50, 255), outline=(150, 90, 10, 255), width=40)
    d.ellipse([110, 110, S - 110, S - 110], fill=(70, 30, 160, 255))
    for i, (x, y0, y1) in enumerate(((330, 560, 760), (512, 430, 680), (694, 290, 580))):
        d.line([(x, y0 - 70), (x, y1 + 60)], fill=(255, 255, 255, 255), width=26)
        d.rounded_rectangle([x - 60, y0, x + 60, y1], radius=20, fill=(46, 235, 140, 255),
                            outline=(255, 255, 255, 255), width=12)
    im.save(os.path.join(OUT, "emblem.png"))


if __name__ == "__main__":
    face("determined", "determined", gaze=(0.75, 0.05))
    face("cheer", "cheer")
    face("surprised", "surprised", gaze=(-0.5, 0.0))
    chart("focus", "focus", seed=11, n=18)
    chart("win", "win", seed=5, glow_line=True, n=18)
    chart("challenge", "challenge", seed=21, n=20)
    chart("side_a", "focus", W=900, H=1400, n=14, seed=2)
    chart("side_b", "other", W=900, H=1400, n=14, seed=9)
    skyline()
    emblem()
    print("ok")

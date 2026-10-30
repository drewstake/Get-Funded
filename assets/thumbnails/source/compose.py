"""Composite titles + grade onto renders.  usage: compose.py <scene> <render.png> <out.png>"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "LilitaOne-Regular.ttf")


def grade(im):
    im = ImageEnhance.Color(im).enhance(1.14)
    im = ImageEnhance.Contrast(im).enhance(1.06)
    W, H = im.size
    # soft vignette
    v = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(v)
    d.ellipse([-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
    v = v.filter(ImageFilter.GaussianBlur(W * 0.08))
    dark = ImageEnhance.Brightness(im).enhance(0.55)
    return Image.composite(im, dark, v)


def title_layer(text, size, W, H, tilt=-3, fill=("#FFF6A0", "#FFD21F", "#FF9500"),
                outline="#1E0B4F", depth_col="#3A138A", stroke=None, depth=None, tracking=0):
    font = ImageFont.truetype(FONT, size)
    stroke = stroke or max(6, size // 11)
    depth = depth or max(6, size // 13)
    pad = stroke * 2 + depth + 40
    # measure
    tmp = ImageDraw.Draw(Image.new("L", (10, 10)))
    bb = tmp.textbbox((0, 0), text, font=font, stroke_width=stroke)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    CW, CH = tw + pad * 2, th + pad * 2
    ox, oy = pad - bb[0], pad - bb[1]

    def mask(sw):
        m = Image.new("L", (CW, CH), 0)
        ImageDraw.Draw(m).text((ox, oy), text, font=font, fill=255, stroke_width=sw, stroke_fill=255)
        return m

    inner = mask(0)
    outer = mask(stroke)
    L = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    # drop shadow
    sh = outer.filter(ImageFilter.GaussianBlur(size // 10))
    L.paste(Image.new("RGBA", (CW, CH), (5, 0, 25, 200)), (0, depth + size // 14), sh)
    # extrusion
    for i in range(depth, 0, -1):
        L.paste(Image.new("RGBA", (CW, CH), depth_col), (0, i), outer)
    L.paste(Image.new("RGBA", (CW, CH), outline), (0, 0), outer)
    # gradient fill
    g = Image.new("RGBA", (CW, CH))
    gd = ImageDraw.Draw(g)
    from PIL import ImageColor
    c0, c1, c2 = [ImageColor.getrgb(c) for c in fill]
    top, bot = oy + bb[1] + stroke, oy + bb[3] - stroke
    for y in range(CH):
        t = min(1, max(0, (y - top) / max(1, bot - top)))
        if t < 0.5:
            k = t / 0.5; c = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
        else:
            k = (t - 0.5) / 0.5; c = tuple(int(c1[j] + (c2[j] - c1[j]) * k) for j in range(3))
        gd.line([(0, y), (CW, y)], fill=c + (255,))
    L.paste(g, (0, 0), inner)
    # glossy highlight band on upper part of letters
    hl = Image.new("L", (CW, CH), 0)
    hd = ImageDraw.Draw(hl)
    hd.rectangle([0, top, CW, top + (bot - top) * 0.36], fill=110)
    hl = ImageChops.multiply(hl, inner.filter(ImageFilter.MinFilter(max(3, (stroke // 3) | 1))))
    L.paste(Image.new("RGBA", (CW, CH), (255, 255, 255, 255)), (0, 0), hl)
    # small inner top-edge light line
    L = L.rotate(tilt, resample=Image.BICUBIC, expand=True)
    return L


def pill(text, size, fg="#FFFFFF", bg="#7B3CFF", border="#1E0B4F", tilt=-3):
    font = ImageFont.truetype(FONT, size)
    tmp = ImageDraw.Draw(Image.new("L", (10, 10)))
    bb = tmp.textbbox((0, 0), text, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    px, py = int(size * 0.7), int(size * 0.38)
    b = max(5, size // 9)
    CW, CH = tw + px * 2 + b * 2 + 30, th + py * 2 + b * 2 + 30
    L = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(L)
    r = (th + py * 2) // 2
    d.rounded_rectangle([15, 21, CW - 15, CH - 9], radius=r + b, fill=(10, 0, 40, 200))
    d.rounded_rectangle([15, 15, CW - 15, CH - 15], radius=r + b, fill=border)
    d.rounded_rectangle([15 + b, 15 + b, CW - 15 - b, CH - 15 - b], radius=r, fill=bg)
    d.rounded_rectangle([15 + b + 6, 15 + b + 4, CW - 15 - b - 6, 15 + b + (th + py * 2) * 0.42], radius=r, fill=(255, 255, 255, 50))
    d.text((15 + b + px - bb[0], 15 + b + py - bb[1]), text, font=font, fill=fg,
           stroke_width=max(2, size // 16), stroke_fill=border)
    return L.rotate(tilt, resample=Image.BICUBIC, expand=True)


def place(base, layer, cx, cy):
    base.alpha_composite(layer, (int(cx - layer.width / 2), int(cy - layer.height / 2)))


def compose(scene, src, out):
    im = Image.open(src).convert("RGB")
    if im.size != (1920, 1080):
        im = im.resize((1920, 1080), Image.LANCZOS)
    im = grade(im).convert("RGBA")
    W, H = im.size
    if scene == "focus":
        t = title_layer("GET FUNDED!", 230, W, H, tilt=-3)
        place(im, t, W * 0.52, H * 0.155)
    elif scene == "win":
        t = title_layer("GET FUNDED!", 236, W, H, tilt=-3)
        place(im, t, W * 0.5, H * 0.15)
        p = pill("BUILD YOUR ACCOUNT", 62, bg="#22C46A", tilt=-3)
        place(im, p, W * 0.5, H * 0.315)
    elif scene == "challenge":
        a = title_layer("CAN YOU", 140, W, H, tilt=-3, fill=("#FFFFFF", "#E8F6FF", "#9FD8FF"))
        b = title_layer("GET FUNDED?", 205, W, H, tilt=-3)
        place(im, a, W * 0.48, H * 0.095)
        place(im, b, W * 0.5, H * 0.25)
    im.convert("RGB").save(out, optimize=True)


if __name__ == "__main__":
    compose(sys.argv[1], sys.argv[2], sys.argv[3])

"""Ebru (marbling) zeminli, yandan görünen ince belli çay bardağı ikonu.

Ebru: Aubrey Jaffer'ın marbling matematiği — mürekkep damlaları mevcut deseni
dışa iter, tarak/dalga hareketleri deseni bükerek. Her piksel ters dönüşümle boyanır.
Renkler düz: #8B0000, #00A693 ve kağıt rengi (gradyan yok).
"""
import sys
import numpy as np
from PIL import Image, ImageDraw

OUT = sys.argv[1]
SIZE = 1024
SS = 2                      # süper örnekleme (kenar yumuşatma için)
N = SIZE * SS

RED = (139, 0, 0)
TEAL = (0, 166, 147)
PAPER = (244, 236, 220)

# ---- Ebru işlemleri (ileri sırada) ----
ops = []


def drop(cx, cy, r, color):
    ops.append(("drop", cx, cy, r, color))


def wave_x(amp, freq, phase):   # x, y'ye bağlı kayar (yatay dalga)
    ops.append(("wx", amp, freq, phase))


def wave_y(amp, freq, phase):
    ops.append(("wy", amp, freq, phase))


def swirl(cx, cy, strength, falloff):
    ops.append(("swirl", cx, cy, strength, falloff))


# Zemin: yatay renk şeritleri (gelgit ebrusunun başlangıcı)
BANDS = [TEAL, PAPER, RED, PAPER]
BAND_HEIGHT = 0.045

# Bardağın arkasında iç içe damlalar (küçük tutuldu ki şeritler kenarlara itilmesin)
drop(0.5, 0.56, 0.20, RED)
drop(0.5, 0.56, 0.19, PAPER)
drop(0.5, 0.56, 0.18, TEAL)
# Köşelerde ebru "lale" damlaları
for (x, y) in [(0.16, 0.18), (0.84, 0.20), (0.15, 0.86), (0.86, 0.84)]:
    drop(x, y, 0.06, RED)
    drop(x, y, 0.045, PAPER)
    drop(x, y, 0.035, TEAL)

# Tarak hareketleri: önce geniş dalga (gelgit), sonra ince tarak, en son hafif girdap
wave_y(0.040, 2.0, 0.0)
wave_x(0.025, 3.0, 0.8)
wave_y(0.010, 10.0, 0.4)
swirl(0.5, 0.56, 0.7, 0.18)

# ---- Ters dönüşümle boyama ----
ys, xs = np.mgrid[0:N, 0:N].astype(np.float64)
px = (xs + 0.5) / N
py = (ys + 0.5) / N
canvas = np.zeros((N, N, 3), dtype=np.uint8)
canvas[:] = PAPER
done = np.zeros((N, N), dtype=bool)

for op in reversed(ops):
    kind = op[0]
    if kind == "drop":
        _, cx, cy, r, color = op
        dx, dy = px - cx, py - cy
        d2 = dx * dx + dy * dy
        inside = (d2 < r * r) & ~done
        canvas[inside] = color
        done |= inside
        outside = ~done
        scale = np.sqrt(np.clip(1 - (r * r) / np.maximum(d2, 1e-12), 0, None))
        px = np.where(outside, cx + dx * scale, px)
        py = np.where(outside, cy + dy * scale, py)
    elif kind == "wx":
        _, a, f, ph = op
        px = px - a * np.sin(2 * np.pi * f * py + ph)
    elif kind == "wy":
        _, a, f, ph = op
        py = py - a * np.sin(2 * np.pi * f * px + ph)
    elif kind == "swirl":
        _, cx, cy, k, s = op
        dx, dy = px - cx, py - cy
        rr = np.sqrt(dx * dx + dy * dy)
        theta = -k * np.exp(-rr / s)          # ters dönüş
        c, sn = np.cos(theta), np.sin(theta)
        px = cx + dx * c - dy * sn
        py = cy + dx * sn + dy * c

# Damlaya denk gelmeyen pikseller, geri izlenen konumdaki şeridin rengini alır
band = (np.floor(py / BAND_HEIGHT).astype(int)) % len(BANDS)
for index, color in enumerate(BANDS):
    canvas[(~done) & (band == index)] = color

img = Image.fromarray(canvas, "RGB")
draw = ImageDraw.Draw(img)

# ---- İnce belli çay bardağı (yandan) ----
def S(v):  # 1024 ölçeğinden süper örneklemeye
    return v * SS

cx = 512
top, height = 265, 400
# Yükseklik boyunca yarı genişlik: geniş ağız → ince bel → dolgun göbek → dar taban
profile_t = np.array([0.00, 0.08, 0.28, 0.48, 0.58, 0.72, 0.84, 0.94, 1.00])
profile_w = np.array([0.320, 0.308, 0.235, 0.160, 0.178, 0.260, 0.272, 0.225, 0.175])
ts = np.linspace(0, 1, 240)
ws = np.interp(ts, profile_t, profile_w)
ws = np.convolve(np.pad(ws, 10, mode="edge"), np.ones(21) / 21, mode="valid")  # yumuşat
WIDTH = 255


def glass_polygon(grow):
    left = [(S(cx - w * WIDTH - grow), S(top + t * height - (grow if t == 0 else 0))) for t, w in zip(ts, ws)]
    right = [(S(cx + w * WIDTH + grow), S(top + t * height - (grow if t == 0 else 0))) for t, w in zip(ts, ws)]
    bottom_y = S(top + height + grow)
    return left + [(left[-1][0], bottom_y), (right[-1][0], bottom_y)] + right[::-1]


# Tabak
saucer_y = top + height + 18
for grow, color in [(10, RED), (0, PAPER)]:
    draw.ellipse([S(cx - 205 - grow), S(saucer_y - 38 - grow), S(cx + 205 + grow), S(saucer_y + 38 + grow)], fill=color)
draw.ellipse([S(cx - 185), S(saucer_y - 26), S(cx + 185), S(saucer_y + 26)], fill=TEAL)
draw.ellipse([S(cx - 120), S(saucer_y - 14), S(cx + 120), S(saucer_y + 14)], fill=PAPER)

# Bardak: dış kırmızı çizgi, kağıt renginde cam, içte çay
draw.polygon(glass_polygon(16), fill=RED)
draw.polygon(glass_polygon(8), fill=PAPER)

tea_top = top + 0.13 * height
tea_poly = [(x, y) for (x, y) in glass_polygon(-10) if y >= S(tea_top)]
inner = glass_polygon(-10)
# Çay seviyesinin üstünü kırp
clipped = []
for x, y in inner:
    clipped.append((x, max(y, S(tea_top))))
draw.polygon(clipped, fill=RED)

# Camın üst boş kısmı ile çay arasında ince bir köpük/ışık çizgisi
draw.line([(S(cx - 0.28 * WIDTH), S(tea_top)), (S(cx + 0.28 * WIDTH), S(tea_top))], fill=PAPER, width=S(6))

# Yansıma şeritleri (düz renk)
def stripe(x0, y0, x1, y1, w):
    draw.line([(S(x0), S(y0)), (S(x1), S(y1))], fill=PAPER, width=S(w))

stripe(cx - 56, top + 78, cx - 36, top + 165, 11)
stripe(cx - 48, top + 300, cx - 52, top + 345, 11)

# Taban kalınlığı
draw.rectangle([S(cx - 0.185 * WIDTH - 4), S(top + height - 16), S(cx + 0.185 * WIDTH + 4), S(top + height + 8)], fill=PAPER)

img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save(OUT)
print("saved", OUT)

#!/usr/bin/env python3
"""앱 아이콘(1024×1024)을 그린다.

디자인: 파란 배경 위 2줄 × 4칸으로 이어 붙인 파노라마 틀, 그 안의 건물 실루엣,
가운데 건물(본건)을 노란색 + 위치 핀으로 강조.

    python3 scripts/make_icon.py   # → App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

S = 4            # 4배로 그린 뒤 줄여서 가장자리를 부드럽게
N = 1024 * S


def px(v: float) -> int:
    return int(round(v * S))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# 배경: 위→아래 진한 파랑 그라데이션
bg = Image.new("RGB", (N, N))
top, bottom = (14, 52, 120), (26, 120, 210)
d = ImageDraw.Draw(bg)
for y in range(N):
    d.line([(0, y), (N, y)], fill=lerp(top, bottom, y / (N - 1)))

# 파노라마 틀 (가로로 긴 사각형)
fx0, fy0, fx1, fy1 = 112, 300, 912, 724
frame = Image.new("RGBA", (N, N), (0, 0, 0, 0))
fd = ImageDraw.Draw(frame)

# 틀 안: 하늘
sky = Image.new("RGB", (N, N))
sd = ImageDraw.Draw(sky)
for y in range(px(fy0), px(fy1)):
    t = (y - px(fy0)) / (px(fy1) - px(fy0))
    sd.line([(px(fx0), y), (px(fx1), y)], fill=lerp((190, 226, 255), (232, 244, 255), t))

# 건물 실루엣 (왼→오): (x0, x1, 위쪽 y)
buildings = [
    (130, 215, 520), (205, 280, 455), (275, 350, 560), (345, 430, 490),
    (560, 640, 470), (635, 720, 540), (712, 790, 430), (785, 895, 515),
]
ground = 690
inner = Image.new("RGBA", (N, N), (0, 0, 0, 0))
idraw = ImageDraw.Draw(inner)
for x0, x1, yt in buildings:
    idraw.rectangle([px(x0), px(yt), px(x1), px(ground)], fill=(40, 70, 115, 255))
    # 창문
    for wy in range(yt + 22, ground - 20, 34):
        for wx in range(x0 + 14, x1 - 16, 26):
            idraw.rectangle([px(wx), px(wy), px(wx + 12), px(wy + 16)], fill=(120, 160, 210, 255))

# 본건 (가운데, 노란색)
bx0, bx1, byt = 440, 560, 380
idraw.rectangle([px(bx0), px(byt), px(bx1), px(ground)], fill=(255, 196, 40, 255))
for wy in range(byt + 26, ground - 20, 36):
    for wx in range(bx0 + 18, bx1 - 18, 30):
        idraw.rectangle([px(wx), px(wy), px(wx + 14), px(wy + 18)], fill=(255, 238, 170, 255))

# 땅
idraw.rectangle([px(fx0), px(ground), px(fx1), px(fy1)], fill=(60, 90, 70, 255))

# 하늘 + 건물을 틀 모양(둥근 사각형)으로 잘라 붙이기
panel = sky.convert("RGBA")
panel.alpha_composite(inner)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([px(fx0), px(fy0), px(fx1), px(fy1)], radius=px(36), fill=255)

# 틀 그림자
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([px(fx0), px(fy0 + 18), px(fx1), px(fy1 + 18)],
                                         radius=px(36), fill=(0, 20, 60, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(px(18)))

icon = bg.convert("RGBA")
icon.alpha_composite(shadow)
icon.paste(panel, (0, 0), mask)

# 2줄 × 4칸 이음선 (흰 선)
ld = ImageDraw.Draw(icon)
lw = px(7)
for i in range(1, 4):
    x = fx0 + (fx1 - fx0) * i / 4
    ld.line([(px(x), px(fy0)), (px(x), px(fy1))], fill=(255, 255, 255, 235), width=lw)
ymid = (fy0 + fy1) / 2
ld.line([(px(fx0), px(ymid)), (px(fx1), px(ymid))], fill=(255, 255, 255, 235), width=lw)
ld.rounded_rectangle([px(fx0), px(fy0), px(fx1), px(fy1)], radius=px(36),
                     outline=(255, 255, 255, 255), width=px(12))

# 위치 핀 (본건 위)
cx, cy, r = 500, 250, 62
pin = ImageDraw.Draw(icon)
pin.polygon([(px(cx - r * 0.82), px(cy + r * 0.45)), (px(cx + r * 0.82), px(cy + r * 0.45)),
             (px(cx), px(cy + r * 2.0))], fill=(235, 60, 60, 255))
pin.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=(235, 60, 60, 255))
pin.ellipse([px(cx - r * 0.42), px(cy - r * 0.42), px(cx + r * 0.42), px(cy + r * 0.42)],
            fill=(255, 255, 255, 255))

final = icon.convert("RGB").resize((1024, 1024), Image.LANCZOS)  # 아이콘은 불투명이어야 함
OUT.parent.mkdir(parents=True, exist_ok=True)
final.save(OUT, "PNG")
print("wrote", OUT)

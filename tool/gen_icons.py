#!/usr/bin/env python3
"""生成 Android 启动图标（android/app/src/main/res/mipmap-*/ic_launcher.png）。需要 pillow。"""
import os
from PIL import Image, ImageDraw

SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
root = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
for k, v in SIZES.items():
    S = v * 4
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, S - 1, S - 1), radius=S // 5, fill=(46, 125, 107, 255))
    d.rounded_rectangle((S * 0.22, S * 0.18, S * 0.78, S * 0.82), radius=S // 14, fill=(255, 255, 255, 255))
    for i in range(3):
        y = S * (0.30 + i * 0.17)
        g = (46, 125, 107, 255)
        d.line((S * 0.30, y, S * 0.36, y + S * 0.04), fill=g, width=int(S * 0.025))
        d.line((S * 0.36, y + S * 0.04, S * 0.44, y - S * 0.04), fill=g, width=int(S * 0.025))
        d.line((S * 0.50, y, S * 0.70, y), fill=(160, 160, 160, 255), width=int(S * 0.025))
    out = os.path.join(root, f'mipmap-{k}')
    os.makedirs(out, exist_ok=True)
    im.resize((v, v), Image.LANCZOS).save(os.path.join(out, 'ic_launcher.png'))
print('icons generated')

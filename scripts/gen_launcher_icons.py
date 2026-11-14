"""Per-flavor launcher icons (Section 11) from the design tokens (Section 13.1).

Deep Ocean rounded square with a white snowflake (cold chain) and a band in the flavor accent with
the flavor letter (D = driver, O = operator, C = control tower), in the bundled Poppins SemiBold.
Writes client/android/app/src/<flavor>/res/mipmap-*/ic_launcher.png and a 512 px store icon.

    python scripts/gen_launcher_icons.py      (needs Pillow)
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'client'))
OCEAN = (0x0B, 0x4F, 0x6C)
FLAVORS = {'driver': ((0x12, 0xC2, 0xE9), 'D'), 'operator': ((0x2E, 0x9D, 0x5B), 'O'), 'manager': ((0x5B, 0x5B, 0xD6), 'C')}
SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
BIG = 768


def icon(accent, letter):
    img = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = int(BIG * 0.22)
    d.rounded_rectangle([0, 0, BIG - 1, BIG - 1], radius=radius, fill=OCEAN)
    band = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(band).rectangle([0, int(BIG * 0.72), BIG, BIG], fill=accent)
    mask = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, BIG - 1, BIG - 1], radius=radius, fill=255)
    img.paste(band, (0, 0), Image.composite(band, Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0)), mask).split()[3])
    cx, cy, arm = BIG * 0.5, BIG * 0.40, BIG * 0.24
    for k in range(6):
        a = math.pi / 3 * k
        d.line([cx, cy, cx + arm * math.cos(a), cy + arm * math.sin(a)], fill='white', width=int(BIG * 0.035))
        bx, by = cx + arm * 0.55 * math.cos(a), cy + arm * 0.55 * math.sin(a)
        for da in (-0.6, 0.6):
            d.line([bx, by, bx + arm * 0.3 * math.cos(a + da), by + arm * 0.3 * math.sin(a + da)], fill='white', width=int(BIG * 0.03))
    font = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'Poppins-SemiBold.ttf'), int(BIG * 0.2))
    d.text(((BIG - d.textlength(letter, font=font)) / 2, BIG * 0.73), letter, font=font, fill='white')
    return img


def main():
    for name, (accent, letter) in FLAVORS.items():
        img = icon(accent, letter)
        for density, px in SIZES.items():
            out = os.path.join(ROOT, 'android', 'app', 'src', name, 'res', f'mipmap-{density}')
            os.makedirs(out, exist_ok=True)
            img.resize((px, px), Image.LANCZOS).save(os.path.join(out, 'ic_launcher.png'))
        img.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, 'android', 'app', 'src', name, 'ic_launcher-playstore.png'))
        print(f'{name}: ok')
    return 0


if __name__ == '__main__':
    sys.exit(main())

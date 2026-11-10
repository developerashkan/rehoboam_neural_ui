"""Builds README tiles and the hero GIF from the capture test output.

Run from example/ after:
    flutter test test/screenshots_test.dart --dart-define=CAPTURE=true
"""
import glob
import json
import os

from PIL import Image

OUT = os.path.join('..', 'assets', 'screenshots')
SCALE = 1.5  # pixelRatio of the full-page captures


def tiles(theme):
    page = Image.open(os.path.join(OUT, f'gallery_{theme}.png')).convert('RGB')
    rects = json.load(open(os.path.join('build', f'cards_{theme}.json')))
    os.makedirs(os.path.join(OUT, 'tiles'), exist_ok=True)
    for name, (l, t, r, b) in rects.items():
        pad = 10
        box = [int((l - pad) * SCALE), int((t - pad) * SCALE),
               int((r + pad) * SCALE), int((b + pad) * SCALE)]
        tile = page.crop(box)
        w = 1000 if name == 'hero' else 520
        tile = tile.resize((w, round(tile.height * w / tile.width)), Image.LANCZOS)
        tile.save(os.path.join(OUT, 'tiles', f'{name}_{theme}.png'), optimize=True)


def gif():
    files = sorted(glob.glob(os.path.join('build', 'frames', 'f*.png')))
    frames = [Image.open(f).convert('RGB') for f in files]
    w = 800
    frames = [f.resize((w, round(f.height * w / f.width)), Image.LANCZOS) for f in frames]
    # One shared palette for every frame: no flicker between frames.
    strip = Image.new('RGB', (w, frames[0].height * 6))
    for i, k in enumerate(range(0, len(frames), max(1, len(frames) // 6))):
        if i < 6:
            strip.paste(frames[k], (0, i * frames[0].height))
    palette = strip.quantize(colors=255, method=Image.MEDIANCUT)
    q = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    path = os.path.join(OUT, 'hero.gif')
    q[0].save(path, save_all=True, append_images=q[1:], duration=83, loop=0,
              optimize=True, disposal=1)
    print('gif', len(q), 'frames', os.path.getsize(path) // 1024, 'KB')


if __name__ == '__main__':
    tiles('dark')
    tiles('light')
    gif()
    for f in sorted(glob.glob(os.path.join(OUT, '**', '*.*'), recursive=True)):
        print(f, os.path.getsize(f) // 1024, 'KB')

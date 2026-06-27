#!/usr/bin/env python3
"""从 iOS AppIcon 1024 生成 Android 自适应前景与 mipmap（按 Material 安全区留白）。"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image

# 108dp 画布上直径 66dp 安全圆的内接正方形边长 ≈ 47dp → 相对画布边长比例
_SAFE_SQUARE_RATIO = 47 / 108


def compose_centered(src: Image.Image, canvas_size: int, out_path: Path) -> None:
    max_side = max(1, round(canvas_size * _SAFE_SQUARE_RATIO))
    w, h = src.size
    scale = min(max_side / w, max_side / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 255))
    x = (canvas_size - nw) // 2
    y = (canvas_size - nh) // 2
    canvas.paste(resized, (x, y), resized)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, "PNG")


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    src_path = repo / "TreeletHub/Assets.xcassets/AppIcon.appiconset/11024.png"
    res = Path(__file__).resolve().parents[1] / "app/src/main/res"
    if len(sys.argv) > 1:
        src_path = Path(sys.argv[1])
    if not src_path.is_file():
        print("missing:", src_path, file=sys.stderr)
        sys.exit(1)
    img = Image.open(src_path).convert("RGBA")
    for folder, c in [
        ("drawable-mdpi", 108),
        ("drawable-hdpi", 162),
        ("drawable-xhdpi", 216),
        ("drawable-xxhdpi", 324),
        ("drawable-xxxhdpi", 432),
    ]:
        compose_centered(img, c, res / folder / "ic_launcher_foreground_src.png")
    for folder, s in [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]:
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            compose_centered(img, s, res / folder / name)
    print("OK ->", res)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compose TreeletHub App Store marketing assets for 1.3.2.

Outputs:
- screenshots/duo: iPhone Duo outer/inner marketing frames (large type)
- screenshots/iphone67: refreshed 6.7" marketing frames
- screenshots/mac: Mac App Store 2880x1800 frames
- creative: product page header + search results assets
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont  # noqa: F401

ROOT = Path(__file__).resolve().parents[1]
OUT_DUO = ROOT / "screenshots" / "duo"
OUT_67 = ROOT / "screenshots" / "iphone67"
OUT_MAC = ROOT / "screenshots" / "mac"
OUT_CREATIVE = ROOT / "creative"
ICON = Path("/tmp/th_asc_shots/icon.png")
RAW_SHOTS = [
    Path("/tmp/th_asc_shots/zh1.jpg"),
    Path("/tmp/th_asc_shots/zh2.jpg"),
    Path("/tmp/th_asc_shots/zh3.jpg"),
]
ISLAND = Path(
    "/Users/timshu/TreeletProjects/treelethub/TreeletHub/assets/screenshots/island-apps.jpg"
)
KEYBOARD = Path(
    "/Users/timshu/TreeletProjects/treelethub/TreeletHub/assets/screenshots/keyboard-launcher.jpg"
)
WALLPAPER = Path("/Users/timshu/Downloads/壁纸/treelethub.png")

# Brand: deep teal glass + mint accent + ivory ink
TEAL_TOP = (22, 48, 46)
TEAL_MID = (14, 32, 34)
TEAL_BOT = (8, 18, 22)
MINT = (120, 210, 170)
IVORY = (245, 250, 245)
IVORY_SOFT = (190, 220, 210)
INK = (8, 16, 18)

FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_BLACK = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_CN = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_CN_BOLD = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_CN_BOLD_INDEX = 1  # W6 when available

# Duo + classic sizes
SIZES = {
    "duo_outer": (1398, 2034),
    "duo_inner": (2007, 2853),
    "iphone67": (1290, 2796),
    "mac": (2880, 1800),
    "header": (3840, 1646),
    "search": (3840, 2560),
    "search_min": (1920, 1280),
    "universal": (5244, 2950),
}


def font(path: str, size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    try:
        if path.endswith(".ttc"):
            return ImageFont.truetype(path, size, index=index)
        return ImageFont.truetype(path, size)
    except OSError:
        try:
            return ImageFont.truetype(FONT_CN, size, index=0)
        except OSError:
            return ImageFont.truetype(FONT_BOLD, size)


def fit_font(text: str, max_w: int, start: int, path: str, index: int = 0) -> ImageFont.FreeTypeFont:
    size = start
    while size > 36:
        face = font(path, size, index)
        if face.getlength(text) <= max_w:
            return face
        size -= 6
    return font(path, size, index)


def gradient(size: tuple[int, int]) -> Image.Image:
    w, h = size
    xx = np.linspace(0, 1, w, dtype=np.float32)
    yy = np.linspace(0, 1, h, dtype=np.float32)
    x, y = np.meshgrid(xx, yy)
    top = np.array(TEAL_TOP, dtype=np.float32)
    mid = np.array(TEAL_MID, dtype=np.float32)
    bot = np.array(TEAL_BOT, dtype=np.float32)
    g = np.where(y[..., None] < 0.45, top + (mid - top) * (y[..., None] / 0.45), mid + (bot - mid) * ((y[..., None] - 0.45) / 0.55))
    glow = np.exp(-(((x - 0.5) ** 2) / 0.22 + ((y - 0.28) ** 2) / 0.18))
    g = g + glow[..., None] * np.array([28, 70, 55], dtype=np.float32)
    return Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGB")


def rounded(im: Image.Image, radius: int) -> Image.Image:
    im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, im.width, im.height), radius=radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0))
    out.putalpha(mask)
    return out


def phone_frame(shot: Image.Image, max_h: int, max_w: int) -> Image.Image:
    """Scale screenshot into a tall rounded phone card with border."""
    shot = shot.convert("RGB")
    # Crop center if needed for wider Duo canvas
    target_ratio = 0.48  # phone-like
    sw, sh = shot.size
    if sw / sh > target_ratio:
        nw = int(sh * target_ratio)
        left = (sw - nw) // 2
        shot = shot.crop((left, 0, left + nw, sh))
    shot.thumbnail((max_w, max_h), Image.Resampling.LANCZOS)
    card = rounded(shot, radius=max(28, shot.width // 18))
    # mint border
    border = Image.new("RGBA", (card.width + 18, card.height + 18), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border)
    bd.rounded_rectangle((0, 0, border.width - 1, border.height - 1), radius=max(34, card.width // 16), fill=(MINT[0], MINT[1], MINT[2], 55))
    border.paste(card, (9, 9), card)
    shadow = Image.new("RGBA", (border.width + 40, border.height + 40), (0, 0, 0, 0))
    shd = Image.new("RGBA", border.size, (0, 0, 0, 90))
    shadow.paste(shd, (20, 24), shd)
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    shadow.paste(border, (10, 8), border)
    return shadow


def draw_copy(
    canvas: Image.Image,
    keyword: str,
    title: str,
    *,
    cn: bool,
    top: int,
    max_w: int,
) -> int:
    d = ImageDraw.Draw(canvas)
    key_path = FONT_CN_BOLD if cn else FONT_BLACK
    title_path = FONT_CN if cn else FONT_BOLD
    key_index = FONT_CN_BOLD_INDEX if cn else 0
    key_face = fit_font(keyword, max_w, start=int(canvas.width * 0.11), path=key_path, index=key_index)
    # Ensure keyword is huge for thumbnail readability
    if key_face.size < int(canvas.width * 0.085):
        key_face = font(key_path, int(canvas.width * 0.085), key_index)
    d.text(((canvas.width - key_face.getlength(keyword)) / 2, top), keyword, font=key_face, fill=IVORY)
    y = top + key_face.size + int(canvas.height * 0.018)
    title_face = fit_font(title, max_w, start=int(canvas.width * 0.048), path=title_path, index=0)
    # wrap title into up to 2 lines
    words = list(title) if cn else title.split(" ")
    lines: list[str] = []
    cur = ""
    for w in words:
        trial = (cur + w) if cn else (cur + (" " if cur else "") + w)
        if title_face.getlength(trial) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    lines = lines[:2]
    for line in lines:
        d.text(((canvas.width - title_face.getlength(line)) / 2, y), line, font=title_face, fill=IVORY_SOFT)
        y += int(title_face.size * 1.22)
    return y


def compose_phone_shot(
    size: tuple[int, int],
    keyword: str,
    title: str,
    shot_path: Path,
    *,
    cn: bool,
    outfile: Path,
) -> None:
    w, h = size
    base = gradient(size).convert("RGBA")
    # optional soft wallpaper wash
    if WALLPAPER.exists():
        wp = Image.open(WALLPAPER).convert("RGB")
        wp = wp.resize((w, h), Image.Resampling.LANCZOS)
        base = Image.blend(base.convert("RGB"), wp, 0.18).convert("RGBA")

    max_copy_w = int(w * 0.86)
    y = int(h * 0.06)
    y = draw_copy(base, keyword, title, cn=cn, top=y, max_w=max_copy_w)

    # icon badge
    if ICON.exists():
        icon = Image.open(ICON).convert("RGBA")
        isz = max(96, int(w * 0.12))
        icon = rounded(icon.resize((isz, isz), Image.Resampling.LANCZOS), radius=isz // 5)
        base.paste(icon, ((w - isz) // 2, y + int(h * 0.015)), icon)
        y = y + isz + int(h * 0.03)
    else:
        y += int(h * 0.02)

    shot = Image.open(shot_path)
    phone = phone_frame(shot, max_h=int(h - y - h * 0.05), max_w=int(w * 0.78))
    px = (w - phone.width) // 2
    py = min(y, h - phone.height - int(h * 0.03))
    base.paste(phone, (px, py), phone)
    outfile.parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(outfile, "PNG", optimize=True)
    print("wrote", outfile, base.size)


def compose_mac_shot(
    keyword: str,
    title: str,
    shot_path: Path,
    *,
    cn: bool,
    outfile: Path,
) -> None:
    w, h = 2880, 1800
    base = gradient((w, h)).convert("RGBA")
    max_copy_w = int(w * 0.7)
    y = int(h * 0.08)
    y = draw_copy(base, keyword, title, cn=cn, top=y, max_w=max_copy_w)

    shot = Image.open(shot_path).convert("RGB")
    # Fit into lower area as wide window card
    max_w, max_h = int(w * 0.86), int(h * 0.58)
    shot.thumbnail((max_w, max_h), Image.Resampling.LANCZOS)
    card = rounded(shot, radius=28)
    pad = Image.new("RGBA", (card.width + 24, card.height + 24), (0, 0, 0, 0))
    ImageDraw.Draw(pad).rounded_rectangle((0, 0, pad.width - 1, pad.height - 1), radius=34, fill=(MINT[0], MINT[1], MINT[2], 50))
    pad.paste(card, (12, 12), card)
    px = (w - pad.width) // 2
    py = h - pad.height - int(h * 0.07)
    base.paste(pad, (px, py), pad)
    outfile.parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(outfile, "PNG", optimize=True)
    print("wrote", outfile, base.size)


def compose_creative(kind: str, size: tuple[int, int], slogan: str, sub: str, outfile: Path) -> None:
    w, h = size
    base = gradient(size).convert("RGBA")
    if WALLPAPER.exists():
        wp = Image.open(WALLPAPER).convert("RGB").resize((w, h), Image.Resampling.LANCZOS)
        base = Image.blend(base.convert("RGB"), wp, 0.22).convert("RGBA")

    d = ImageDraw.Draw(base)
    # Logo large — thumbnail must read icon first
    if ICON.exists():
        icon = Image.open(ICON).convert("RGBA")
        isz = int(min(w, h) * (0.42 if kind == "header" else 0.36))
        icon = rounded(icon.resize((isz, isz), Image.Resampling.LANCZOS), radius=isz // 5)
        # place left-center for header, center for search
        if kind == "header":
            ix, iy = int(w * 0.12), (h - isz) // 2
        else:
            ix, iy = (w - isz) // 2, int(h * 0.12)
        # soft glow
        glow = Image.new("RGBA", (isz + 80, isz + 80), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((0, 0, isz + 80, isz + 80), fill=(MINT[0], MINT[1], MINT[2], 40))
        glow = glow.filter(ImageFilter.GaussianBlur(28))
        base.paste(glow, (ix - 40, iy - 40), glow)
        base.paste(icon, (ix, iy), icon)
        text_left = ix + isz + int(w * 0.04) if kind == "header" else int(w * 0.08)
        text_top = iy + int(isz * 0.18) if kind == "header" else iy + isz + int(h * 0.04)
        text_max = w - text_left - int(w * 0.08) if kind == "header" else int(w * 0.84)
    else:
        text_left, text_top, text_max = int(w * 0.08), int(h * 0.3), int(w * 0.84)

    # Slogan: one short line, very large
    face = fit_font(slogan, text_max, start=int(h * 0.16 if kind == "header" else h * 0.11), path=FONT_BLACK)
    # Prefer CN font if CJK present
    if any("\u4e00" <= c <= "\u9fff" for c in slogan):
        face = fit_font(slogan, text_max, start=max(face.size, int(h * 0.12)), path=FONT_CN_BOLD, index=FONT_CN_BOLD_INDEX)
    d.text((text_left if kind == "header" else (w - face.getlength(slogan)) / 2, text_top), slogan, font=face, fill=IVORY)
    sub_face = fit_font(
        sub,
        text_max,
        start=int(face.size * 0.42),
        path=FONT_CN if any("\u4e00" <= c <= "\u9fff" for c in sub) else FONT_BOLD,
        index=0,
    )
    sy = text_top + face.size + int(h * 0.03)
    sx = text_left if kind == "header" else (w - sub_face.getlength(sub)) / 2
    d.text((sx, sy), sub, font=sub_face, fill=IVORY_SOFT)

    outfile.parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(outfile, "PNG", optimize=True)
    print("wrote", outfile, size)


def main() -> None:
    shots = [p for p in RAW_SHOTS if p.exists()]
    if len(shots) < 3:
        raise SystemExit("missing downloaded App Store screenshots in /tmp/th_asc_shots")

    # Chinese Duo set (outer + inners)
    duo_zh = [
        ("duo_outer", "01-outer-honeycomb.png", "蜂巢遥控", "点一下，启动电脑应用", shots[0]),
        ("duo_inner", "02-inner-honeycomb.png", "蜂巢遥控", "与电脑伴侣端同步布局", shots[0]),
        ("duo_inner", "03-inner-trackpad.png", "键鼠触控板", "手机当触控板与键盘", shots[1]),
        ("duo_inner", "04-inner-pair.png", "秒级配对", "同一 Wi‑Fi，六位码连接", shots[2]),
        ("duo_outer", "05-outer-widget.png", "小组件接力", "桌面小组件一键打开", shots[1]),
    ]
    for kind, name, kw, title, shot in duo_zh:
        compose_phone_shot(SIZES[kind], kw, title, shot, cn=True, outfile=OUT_DUO / "zh-Hans" / name)

    duo_en = [
        ("duo_outer", "01-outer-honeycomb.png", "Honeycomb", "Tap to launch desktop apps", shots[0]),
        ("duo_inner", "02-inner-honeycomb.png", "Honeycomb", "Synced with your companion", shots[0]),
        ("duo_inner", "03-inner-trackpad.png", "Trackpad", "Phone as mouse & keyboard", shots[1]),
        ("duo_inner", "04-inner-pair.png", "Pair Fast", "Same Wi‑Fi, 6-digit code", shots[2]),
        ("duo_outer", "05-outer-widget.png", "Widgets", "Home Screen handoff", shots[1]),
    ]
    for kind, name, kw, title, shot in duo_en:
        compose_phone_shot(SIZES[kind], kw, title, shot, cn=False, outfile=OUT_DUO / "en-US" / name)

    # Also refresh classic 6.7" set (required medium/large scaling source)
    for i, (kw, title, shot) in enumerate(
        [
            ("蜂巢遥控", "点一下，启动电脑应用", shots[0]),
            ("键鼠触控板", "手机当触控板与键盘", shots[1]),
            ("秒级配对", "同一 Wi‑Fi，六位码连接", shots[2]),
        ],
        start=1,
    ):
        compose_phone_shot(SIZES["iphone67"], kw, title, shot, cn=True, outfile=OUT_67 / "zh-Hans" / f"{i:02d}.png")
    for i, (kw, title, shot) in enumerate(
        [
            ("Honeycomb", "Tap to launch desktop apps", shots[0]),
            ("Trackpad", "Phone as mouse & keyboard", shots[1]),
            ("Pair Fast", "Same Wi‑Fi, 6-digit code", shots[2]),
        ],
        start=1,
    ):
        compose_phone_shot(SIZES["iphone67"], kw, title, shot, cn=False, outfile=OUT_67 / "en-US" / f"{i:02d}.png")

    # Mac MAS shots — island resize + honeycomb (no keyboard launcher claim)
    mac_src = ISLAND if ISLAND.exists() else shots[0]
    compose_mac_shot("悬浮岛", "拖边缘即可改宽高", mac_src, cn=True, outfile=OUT_MAC / "zh-Hans" / "01-island.png")
    compose_mac_shot("蜂巢墙", "桌面应用一站启动", mac_src, cn=True, outfile=OUT_MAC / "zh-Hans" / "02-honeycomb.png")
    compose_mac_shot("Island", "Drag edges to resize", mac_src, cn=False, outfile=OUT_MAC / "en-US" / "01-island.png")
    compose_mac_shot("Honeycomb", "Launch apps from one wall", mac_src, cn=False, outfile=OUT_MAC / "en-US" / "02-honeycomb.png")
    if KEYBOARD.exists():
        # Use as generic desktop UI only for visual richness; copy stays island/honeycomb compliant.
        compose_mac_shot("桌面中控", "配对后手机即可遥控", KEYBOARD, cn=True, outfile=OUT_MAC / "zh-Hans" / "03-desktop.png")
        compose_mac_shot("Desktop Hub", "Pair once, remote anytime", KEYBOARD, cn=False, outfile=OUT_MAC / "en-US" / "03-desktop.png")

    # Creative assets (search + header) — bilingual pair; ASC per-locale upload later
    compose_creative("header", SIZES["header"], "蜂巢一点即启", "局域网遥控电脑应用", OUT_CREATIVE / "zh-header-3840x1646.png")
    compose_creative("search", SIZES["search"], "蜂巢一点即启", "点一下，启动电脑应用", OUT_CREATIVE / "zh-search-3840x2560.png")
    compose_creative("search", SIZES["search_min"], "蜂巢一点即启", "点一下，启动电脑应用", OUT_CREATIVE / "zh-search-1920x1280.png")
    compose_creative("header", SIZES["universal"], "蜂巢一点即启", "局域网遥控电脑应用", OUT_CREATIVE / "zh-universal-5244x2950.png")

    compose_creative("header", SIZES["header"], "Tap. Launch.", "Wi‑Fi remote for desktop apps", OUT_CREATIVE / "en-header-3840x1646.png")
    compose_creative("search", SIZES["search"], "Tap. Launch.", "Honeycomb remote for desktop apps", OUT_CREATIVE / "en-search-3840x2560.png")
    compose_creative("search", SIZES["search_min"], "Tap. Launch.", "Honeycomb remote for desktop apps", OUT_CREATIVE / "en-search-1920x1280.png")
    compose_creative("header", SIZES["universal"], "Tap. Launch.", "Wi‑Fi remote for desktop apps", OUT_CREATIVE / "en-universal-5244x2950.png")


if __name__ == "__main__":
    main()

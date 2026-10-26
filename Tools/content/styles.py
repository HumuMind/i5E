from __future__ import annotations

import os
import posixpath
import re
from urllib.parse import unquote

NAMED_COLORS = {
    "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
    "blue": "#0000ff", "yellow": "#ffff00", "gray": "#808080", "grey": "#808080",
    "silver": "#c0c0c0", "maroon": "#800000", "navy": "#000080", "purple": "#800080",
    "teal": "#008080", "olive": "#808000", "lime": "#00ff00", "aqua": "#00ffff",
    "fuchsia": "#ff00ff", "windowtext": "#000000",
}
# <font size=1..7> 的近似磅值
FONT_SIZES = {1: 7.5, 2: 10.0, 3: 12.0, 4: 13.5, 5: 18.0, 6: 24.0, 7: 36.0}
# 只保留"衬线 / 无衬线 / 等宽 / 楷体"这几类，够还原观感，不必记住几十种字体名
FAMILY_MAP = {
    "宋体": "song", "simsun": "song", "新宋体": "song", "仿宋": "fang", "fangsong": "fang",
    "楷体": "kai", "kaiti": "kai", "楷体_gb2312": "kai",
    "黑体": "hei", "simhei": "hei", "微软雅黑": "sans", "microsoft yahei": "sans",
    "arial": "sans", "helvetica": "sans", "tahoma": "sans", "verdana": "sans",
    "calibri": "sans", "segoe ui": "sans",
    "times new roman": "times", "georgia": "times", "cambria": "times", "garamond": "times",
    "consolas": "mono", "courier new": "mono", "courier": "mono",
}


def _color(v: str):
    v = v.strip().lower()
    if not v or v in ("transparent", "inherit", "initial", "none"):
        return None
    if v.startswith("#"):
        h = v[1:]
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return "#" + h if re.fullmatch(r"[0-9a-f]{6}", h) else None
    m = re.match(r"rgba?\(([^)]*)\)", v)
    if m:
        parts = [x for x in re.split(r"[,\s]+", m.group(1)) if x]
        try:
            r, g, b = (int(float(x)) for x in parts[:3])
        except (ValueError, TypeError):
            return None
        if all(0 <= x <= 255 for x in (r, g, b)):
            return f"#{r:02x}{g:02x}{b:02x}"
        return None
    return NAMED_COLORS.get(v)


def _size(v: str):
    m = re.match(r"([\d.]+)\s*(pt|px|em|%|in|cm)?", v.strip().lower())
    if not m:
        return None
    try:
        n = float(m.group(1))
    except ValueError:
        return None
    unit = m.group(2) or "pt"
    if unit == "pt":
        return round(n, 1)
    if unit == "px":
        return round(n * 0.75, 1)
    if unit == "em":
        return round(n * 12, 1)
    if unit == "%":
        return round(n / 100 * 12, 1)
    return None


def _family(v: str):
    first = v.split(",")[0].strip().strip("'\"").lower()
    return FAMILY_MAP.get(first)


def _length(v: str):
    """把 text-indent / margin-left 归一成 em。"""
    m = re.match(r"(-?[\d.]+)\s*(pt|px|em)?", v.strip().lower())
    if not m:
        return None
    try:
        n = float(m.group(1))
    except ValueError:
        return None
    unit = m.group(2) or "pt"
    return round(n / 12, 2) if unit in ("pt", "px") else round(n, 2)


def _style_of(el) -> dict:
    """抽取可还原的样式：颜色、字号、字体族、粗斜下划。数值型字段统一归一。"""
    flags: dict = {}
    st = el.get("style") or ""
    if st:
        for decl in st.split(";"):
            if ":" not in decl:
                continue
            k, _, v = decl.partition(":")
            k, v = k.strip().lower(), v.strip()
            if k == "color":
                c = _color(v)
                if c:
                    flags["c"] = c
            elif k == "font-size":
                sz = _size(v)
                if sz:
                    flags["sz"] = sz
            elif k == "font-family":
                fa = _family(v)
                if fa:
                    flags["fa"] = fa
            elif k == "font-weight":
                if v.lower() in ("bold", "700", "800", "900"):
                    flags["b"] = 1
            elif k == "font-style" and v.lower() in ("italic", "oblique"):
                flags["i"] = 1
            elif k == "text-decoration" and "underline" in v.lower():
                flags["u"] = 1
    tag = el.tag.lower()
    if tag == "font":
        _c = _color(el.get("color") or "")
        if _c:
            flags["c"] = _c
        _f = _family(el.get("face") or "")
        if _f:
            flags["fa"] = _f
        sz = el.get("size")
        if sz and sz.strip().isdigit():
            n = int(sz.strip())
            if n in FONT_SIZES:
                flags["sz"] = FONT_SIZES[n]
    return flags


# 只过滤确定无意义的 Word/BBCode 残留。注意 c1–c4 不是垃圾：
# stat-block.css 里 td.c1…td.c4 带底色。
JUNK_CLASSES = {"msonormal", "grame", "spelle", "mso", "bbcsize", "bbccolor"}


def _cls(el) -> list[str]:
    raw = (el.get("class") or "").split()
    keep = []
    for c in raw:
        low = c.lower()
        if low in JUNK_CLASSES or c.isdigit() or low.startswith("mso") or low in ("wordsection1", "section0"):
            continue
        if c not in keep:
            keep.append(c)
    return keep[:4]


def _align_indent(el) -> dict:
    out: dict = {}
    al = (el.get("align") or "").strip().lower()
    ind = None
    st = el.get("style") or ""
    if st:
        for decl in st.split(";"):
            if ":" not in decl:
                continue
            k, _, v = decl.partition(":")
            k, v = k.strip().lower(), v.strip()
            if k == "text-align":
                al = v.lower()
            elif k in ("text-indent", "margin-left"):
                n = _length(v)
                if n:
                    ind = n
    if al in ("center", "right", "justify", "left") and al != "left":
        out["al"] = al[0]
    if ind:
        out["ind"] = ind
    return out

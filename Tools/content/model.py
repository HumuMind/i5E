"""HTML → block 序列。

对应 Docs/decisions/0001-content-model.md 的"文档流打底，实体做标注层"。

block 是内容库的最小单位，必须满足两条不变式：
1. 文本守恒：原文可见文本（去空白后）与 block 内文本逐字符相等。
2. 幂等：render(parse(x)) 再 parse 一次，结果不变。

约定：block 里的 runs 按文档顺序拼接即为该页全文，表格按行优先顺序展开。
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter

import os
import posixpath
from urllib.parse import unquote

from lxml import html as LH

# 空白与不可见字符：比较文本时整体剔除，避免 <BR>、缩进、全角空格造成误报。
# 行分隔符只由 <BR> 产生，用来区分"结构换行"与源码里的普通换行。
SEP = "\u2028"
WS = set("\t\n\r\f\v \u00a0\u3000\u200b\u200c\u200d\u2060\ufeff" + SEP)

# 整棵子树都不产出内容。
IGNORED_TAGS = {
    "script", "style", "noscript", "iframe", "object", "embed", "applet",
    "meta", "link", "title", "head", "base",
    "o:p", "w:sdt", "v:shape", "v:line", "v:rect", "u1:p",  # Word / VML 残留
    "input", "select", "option", "optgroup", "button", "textarea",  # 速查页的筛选控件
}

# 有专门规则的块级标签。
BLOCK_TAGS = {
    "p", "div", "section", "article", "header", "footer", "main", "aside",
    "center", "address", "form", "fieldset", "figure", "figcaption",
    "dl", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6",
    "ul", "ol", "li", "menu", "dir",
    "table", "thead", "tbody", "tfoot", "tr", "td", "th", "caption",
    "blockquote", "pre", "hr",
}

# 透明容器：只是包了一层，递归后按内容决定形状。
TRANSPARENT_TAGS = {
    "span", "font", "b", "i", "u", "s", "strong", "em", "small", "big",
    "sub", "sup", "a", "label", "nobr",
}

# 已知可以透明处理的标签白名单。出现白名单外的标签会记入 report，视为"新类型"，
# 需要人工确认是否需要专门规则（对应 C2 节点覆盖）。
KNOWN_TAGS = IGNORED_TAGS | BLOCK_TAGS | TRANSPARENT_TAGS | {
    "html", "body", "br", "img", "map", "area", "abbr", "cite", "q", "code",
    "kbd", "samp", "var", "tt", "strike", "del", "ins", "mark", "rp", "rt",
    "ruby", "bdi", "bdo", "wbr", "time", "data", "output", "progress",
}


# 图片解析：只认语料内、非模板目录的文件；其余（外链、缺失、CHM 模板按钮）一律丢弃。
IMAGE_ROOT = None
TEMPLATE_PREFIXES = ("template/", "template2/", "空白页模板/")


def configure_images(root) -> None:
    """多进程 worker 的初始化钩子。"""
    global IMAGE_ROOT
    IMAGE_ROOT = root


def resolve_image(page_path: str, src: str) -> str | None:
    """把页面里的相对图片路径解析成语料内路径；解析不到返回 None。"""
    if not src or IMAGE_ROOT is None:
        return None
    cleaned = unquote(src).strip()
    if not cleaned or cleaned.lower().startswith(("http:", "https:", "file:", "data:")):
        return None
    candidates = (
        posixpath.normpath(posixpath.join(posixpath.dirname(page_path), cleaned)),
        posixpath.normpath(cleaned.lstrip("/")),
    )
    for candidate in candidates:
        if candidate.startswith(TEMPLATE_PREFIXES):
            continue
        if os.path.exists(os.path.join(IMAGE_ROOT, candidate)):
            return candidate
    return None


def resolve_link(page_path: str, href: str) -> str | None:
    """把链接解析成"语料内路径#锚点"。

    - 外部链接原样返回；
    - 本页锚点返回 "#锚点"；
    - 内部链接按"相对文件目录 → 相对语料根 → 扩展名互换 → 大小写"依次尝试；
    - 解析不到返回 None（调用方会去掉 href，文字保留）。
    """
    if not href:
        return None
    cleaned = unquote(href).strip().replace("\\", "/")
    if cleaned.lower().startswith(("http:", "https:", "mailto:")):
        return cleaned
    if cleaned.startswith("#"):
        return cleaned
    if IMAGE_ROOT is None:
        return None

    target, _, fragment = cleaned.partition("#")
    candidates = (
        posixpath.normpath(posixpath.join(posixpath.dirname(page_path), target)),
        posixpath.normpath(target.lstrip("/")),
    )
    for candidate in candidates:
        if not candidate.lower().endswith((".htm", ".html")):
            continue
        for probe in (
            candidate,
            candidate[:-5] + (".htm" if candidate.lower().endswith(".html") else ".html"),
        ):
            if os.path.exists(os.path.join(IMAGE_ROOT, probe)):
                return probe + (("#" + fragment) if fragment else "")
    return None


def decode(data: bytes) -> tuple[str, str]:
    """按 BOM → UTF-8 → GB18030 的顺序解码。GB18030 是 GBK/GB2312 的超集。"""
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", "replace"), "utf-8-bom"
    for enc in ("utf-8", "gb18030"):
        try:
            return data.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return data.decode("gb18030", "replace"), "gb18030-replace"


def norm_text(s: str) -> str:
    return "".join(ch for ch in s if ch not in WS)


def _merge(runs: list[dict]) -> list[dict]:
    out: list[dict] = []
    for r in runs:
        if r.get("t") == "":
            continue
        # 样式必须逐项相等才能合并；只比键集合会把不同颜色的相邻段并成一段
        if out and "t" in r and "t" in out[-1]:
            if {k: v for k, v in out[-1].items() if k != "t"} == \
               {k: v for k, v in r.items() if k != "t"}:
                out[-1]["t"] += r["t"]
                continue
        out.append(r)
    return out


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


class Builder:
    def __init__(self, page_path: str = "") -> None:
        self.page_path = page_path
        self._ids: list[str] = []
        self.tag_seen: Counter = Counter()
        self.tag_handled: Counter = Counter()
        self.tag_ignored: Counter = Counter()
        self.tag_transparent: Counter = Counter()
        self.unknown_tags: Counter = Counter()
        self.malformed_tags: Counter = Counter()
        self.degraded: Counter = Counter()
        self.images_used: Counter = Counter()
        self.images_dropped = 0
        self.links_dropped = 0
        self.ids: set[str] = set()
        self.color_runs = 0
        self.drop_color = 0

    # ---------- 文本 ----------

    def source_text(self, body) -> str:
        parts: list[str] = []

        def walk(el):
            if isinstance(el.tag, str):
                if el.tag.lower() in IGNORED_TAGS:
                    return
                if el.text:
                    parts.append(el.text)
            # 注释里的文字不是正文，只取 tail
            for ch in el:
                walk(ch)
                if ch.tail:
                    parts.append(ch.tail)

        walk(body)
        return "".join(parts)

    # ---------- 行内 ----------

    def inline(self, el, ctx: dict | None = None) -> list[dict]:
        ctx = dict(ctx or {})
        out: list[dict] = []
        self._ids = []
        self._inline_into(el, ctx, out)
        return _merge(out)

    def _inline_into(self, el, ctx: dict, out: list[dict]) -> None:
        if isinstance(el.tag, str):
            tag = el.tag.lower()
            self.tag_seen[tag] += 1
            if tag in IGNORED_TAGS:
                self.tag_ignored[tag] += 1
                return
            if re.search(r'[="\'<>]', tag):
                # Word 导出的畸形标签，如 pstyle="margin:0pt"：属性被吞进标签名
                self.malformed_tags[tag[:40]] += 1
            elif tag not in KNOWN_TAGS:
                self.unknown_tags[tag] += 1
            nxt = ctx
            if tag in ("b", "strong"):
                nxt = {**ctx, "b": 1}
            elif tag in ("i", "em"):
                nxt = {**ctx, "i": 1}
            elif tag in ("u", "ins"):
                nxt = {**ctx, "u": 1}
            elif tag in ("s", "strike", "del"):
                nxt = {**ctx, "s": 1}
            elif tag == "sup":
                nxt = {**ctx, "sup": 1}
            elif tag == "sub":
                nxt = {**ctx, "sub": 1}
            elif tag in ("code", "kbd", "samp", "tt"):
                nxt = {**ctx, "code": 1}
            elif tag == "a":
                resolved = resolve_link(self.page_path, el.get("href") or "")
                if resolved:
                    nxt = {**ctx, "href": resolved}
                elif el.get("href"):
                    self.links_dropped += 1
            elif tag == "br":
                out.append({**ctx, "t": SEP})
                return
            elif tag == "img":
                src = el.get("src") or el.get("data-src") or ""
                resolved = resolve_image(self.page_path, src)
                if resolved:
                    self.images_used[resolved] = self.images_used.get(resolved, 0) + 1
                    out.append({"img": resolved, "alt": el.get("alt") or ""})
                else:
                    self.images_dropped += 1
                return
            elif tag not in ("body", "html"):
                if el.get("style") or tag == "font":
                    flags = _style_of(el)
                    if flags:
                        if flags.get("c") and flags["c"] != "#000000":
                            self.color_runs += 1
                        nxt = {**ctx, **flags}
            if el.get("id"):
                self.ids.add(el.get("id"))
                self._ids.append(el.get("id"))
            if tag == "a" and el.get("name"):
                self.ids.add(el.get("name"))
                self._ids.append(el.get("name"))
            if el.text:
                out.append({**nxt, "t": el.text})
            for ch in el:
                self._inline_into(ch, nxt, out)
                if ch.tail:
                    out.append({**nxt, "t": ch.tail})
        else:
            # 注释 / 处理指令：tail 由父级循环负责，这里什么都不做
            return

    # ---------- 块 ----------

    def blocks(self, root) -> list[dict]:
        blocks: list[dict] = []
        self._container(root, blocks)
        return blocks

    def _container(self, el, out: list[dict]) -> None:
        """子节点混排：连续行内内容攒成一个 p，遇到块级元素就落盘。"""
        pending: list = []

        def flush():
            if not pending:
                return
            self._ids = []
            runs = []
            for node in pending:
                self._inline_into(node, {}, runs)
            self._ids = []
            runs = _merge(runs)
            pending.clear()
            if norm_text(_runs_text(runs)) or any(r.get("img") for r in runs):
                block = {"type": "p", "runs": runs}
                if self._ids:
                    block["anchors"] = sorted(set(self._ids))
                out.append(block)

        if el.text:
            pending.append(_TextHolder(el.text))
        for ch in el:
            if isinstance(ch.tag, str):
                tag = ch.tag.lower()
                if tag in BLOCK_TAGS:
                    flush()
                    self._block(ch, out)
                else:
                    pending.append(ch)
            elif ch.text and ch.text.strip():
                # 注释里的文字不算正文
                pass
            if ch.tail:
                pending.append(_TextHolder(ch.tail))
        flush()

    def _block(self, el, out: list[dict]) -> None:
        start = len(out)
        self._block_body(el, out)
        if len(out) == start:
            eltag = el.tag.lower()
            if norm_text("".join(el.itertext())):
                self.degraded[eltag] += 1
                self._container(el, out)
        if el.get("id") and len(out) > start:
            first = out[start]
            if "id" not in first:
                anchors = first.setdefault("anchors", [])
                if el.get("id") not in anchors:
                    anchors.append(el.get("id"))

    def _block_body(self, el, out: list[dict]) -> None:
        tag = el.tag.lower()
        self.tag_seen[tag] += 1
        self.tag_handled[tag] += 1
        if el.get("id"):
            self.ids.add(el.get("id"))

        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            runs = self.inline(el)
            block = {"type": "h", "level": int(tag[1]), "runs": runs}
            if el.get("id"):
                block["id"] = el.get("id")
            block.update(_align_indent(el))
            if _cls(el):
                block["cls"] = _cls(el)
            out.append(block)

        elif tag == "p":
            runs = self.inline(el)
            # 无可见内容的段落（表格占位单元格常见）不保留，否则渲染回去就消失了
            if (not self._ids and not any(r.get("img") for r in runs)
                    and not norm_text(_runs_text(runs))):
                return
            block = {"type": "p", "runs": runs}
            if self._ids:
                block["anchors"] = sorted(set(self._ids))
            block.update(_align_indent(el))
            if _cls(el):
                block["cls"] = _cls(el)
            out.append(block)

        elif tag in ("ul", "ol", "menu", "dir"):
            items: list[dict] = []
            self._collect_list(el, items)
            lb = {"type": "list", "ordered": tag == "ol", "items": items}
            if _cls(el):
                lb["cls"] = _cls(el)
            out.append(lb)

        elif tag == "table":
            out.append(self._table(el))

        elif tag in ("blockquote",):
            inner: list[dict] = []
            self._container(el, inner)
            qb = {"type": "quote", "blocks": inner}
            if _cls(el):
                qb["cls"] = _cls(el)
            out.append(qb)

        elif tag == "pre":
            out.append({"type": "pre", "text": "".join(el.itertext())})

        elif tag == "hr":
            out.append({"type": "hr"})

        elif tag in ("dt", "dd"):
            runs = self.inline(el)
            block = {"type": tag, "runs": runs}
            if self._ids:
                block["anchors"] = sorted(set(self._ids))
            out.append(block)

        elif tag == "img":
            out.append({"type": "img", "src": el.get("src") or "", "alt": el.get("alt") or ""})

        elif tag == "div" and _cls(el):
            inner: list[dict] = []
            self._container(el, inner)
            block = {"type": "div", "cls": _cls(el), "blocks": inner}
            if self._ids:
                block["anchors"] = sorted(set(self._ids))
            out.append(block)

        elif tag in ("thead", "tbody", "tfoot", "tr", "td", "th", "caption"):
            # 游离的表格零件（Word 常产出），当容器处理
            self.tag_transparent[tag] += 1
            self._container(el, out)

        else:
            self._container(el, out)

    def _collect_list(self, el, items: list[dict]) -> None:
        """上游有 <UL><UL><LI>… 这种畸形嵌套，非 li 子节点不能直接跳过。"""
        for ch in el.iterchildren():
            if not isinstance(ch.tag, str):
                continue
            t = ch.tag.lower()
            if t in ("ul", "ol", "menu", "dir", "dl"):
                self._collect_list(ch, items)
                continue
            sub: list[dict] = []
            self._container(ch, sub)
            runs, blocks = [], []
            for b in sub:
                if b["type"] == "p" and not blocks:
                    runs.extend(b["runs"])
                else:
                    blocks.append(b)
            if runs or blocks:
                items.append({"runs": _merge(runs), "blocks": blocks})

    @staticmethod
    def _near_table(el):
        a = el.getparent()
        while a is not None:
            if isinstance(a.tag, str) and a.tag.lower() == "table":
                return a
            a = a.getparent()
        return None

    @staticmethod
    def _bg(el):
        c = _color(el.get("bgcolor") or "")
        if c:
            return c
        st = el.get("style") or ""
        for decl in st.split(";"):
            if ":" not in decl:
                continue
            k, _, v = decl.partition(":")
            k = k.strip().lower()
            if k in ("background-color", "background"):
                c = _color(v.split()[0] if v.split() else "")
                if c:
                    return c
        return None

    def _table(self, el) -> dict:
        # 按文档顺序取"最近表格祖先就是本表"的行：既排除嵌套表格的行，
        # 也不会漏掉被畸形标签挤出 tbody 的孤儿行。
        rows = []
        for tr in el.iter("tr"):
            if self._near_table(tr) is not el:
                continue
            cells = []
            row_bg = self._bg(tr)
            for td in tr.iterchildren():
                if not isinstance(td.tag, str) or td.tag.lower() not in ("td", "th"):
                    continue
                inner: list[dict] = []
                self._container(td, inner)
                cell = {
                    "blocks": inner,
                    "colspan": int(td.get("colspan") or 1),
                    "rowspan": int(td.get("rowspan") or 1),
                    "header": td.tag.lower() == "th",
                }
                cbg = self._bg(td)
                if cbg:
                    cell["bg"] = cbg
                ccls = _cls(td)
                if ccls:
                    cell["cls"] = ccls
                cells.append(cell)
            row = {"cells": cells}
            if row_bg:
                row["bg"] = row_bg
            rows.append(row)
        caption = ""
        cap = el.find("caption")
        if cap is not None:
            caption = "".join(cap.itertext()).strip()
        tb = {"type": "table", "rows": rows, "caption": caption}
        if _cls(el):
            tb["cls"] = _cls(el)
        return tb


class _TextHolder:
    """把裸文本包成可递归的最小节点。"""

    __slots__ = ("text", "tag", "attrib")

    def __init__(self, text: str) -> None:
        self.text = text
        self.tag = "span"
        self.attrib: dict = {}

    def get(self, key, default=None):
        return self.attrib.get(key, default)

    def __iter__(self):
        return iter(())


def blocks_text(blocks: list[dict]) -> str:
    """按文档顺序取 block 内全部文本。表格行优先展开。"""
    parts: list[str] = []

    def runs(rs):
        for r in rs:
            if "t" in r:
                parts.append(r["t"])
            if r.get("img"):
                pass

    def walk(bs):
        for b in bs:
            t = b["type"]
            if t in ("h", "p", "dt", "dd"):
                runs(b["runs"])
            elif t == "list":
                for it in b["items"]:
                    runs(it["runs"])
                    walk(it["blocks"])
            elif t == "table":
                parts.append(b.get("caption", ""))
                for row in b["rows"]:
                    for c in row["cells"]:
                        walk(c["blocks"])
            elif t in ("quote", "div"):
                walk(b["blocks"])
            elif t == "pre":
                parts.append(b["text"])

    walk(blocks)
    return "".join(parts)


def _empty(path: str, enc: str, err: str) -> dict:
    return {
        "path": path, "encoding": enc, "title": "", "blocks": [], "hash": "empty",
        "_check": {
            "src_text": "", "block_text": "", "ids_src": set(), "ids_block": set(),
            "unknown_tags": {}, "malformed_tags": {}, "transparent": {}, "ignored": {},
            "color_runs": 0, "links": [], "imgs": [], "parse_error": err, "empty": True,
        },
    }


def _walk_runs(blocks, fn) -> None:
    for b in blocks:
        t = b["type"]
        if t in ("h", "p", "dt", "dd"):
            fn(b["runs"])
        elif t == "list":
            for it in b["items"]:
                fn(it["runs"])
                _walk_runs(it["blocks"], fn)
        elif t == "table":
            for row in b["rows"]:
                for c in row["cells"]:
                    _walk_runs(c["blocks"], fn)
        elif t in ("quote", "div"):
            _walk_runs(b["blocks"], fn)


def _strip_defaults(blocks) -> dict:
    """页面里占多数的样式提到页级存一份，run 上只留与默认不同的部分。"""
    counts: dict[str, Counter] = {k: Counter() for k in ("c", "sz", "fa")}
    total = 0

    def count(runs):
        nonlocal total
        for r in runs:
            if "t" not in r:
                continue
            total += 1
            for k in counts:
                if k in r:
                    counts[k][r[k]] += 1

    _walk_runs(blocks, count)
    defaults: dict = {}
    for k, ctr in counts.items():
        if not ctr:
            continue
        val, n = ctr.most_common(1)[0]
        if total and n / total >= 0.6:
            defaults[k] = val

    def strip(runs):
        for r in runs:
            for k, val in defaults.items():
                if r.get(k) == val:
                    r.pop(k, None)

    if defaults:
        _walk_runs(blocks, strip)
    return defaults


def parse_page(path: str, data: bytes) -> dict:
    text, enc = decode(data)
    if not text.strip():
        return _empty(path, enc, "file is empty")
    try:
        doc = LH.document_fromstring(text)
    except Exception as e:  # noqa: BLE001
        return _empty(path, enc, f"{type(e).__name__}: {e}")
    body = doc.find("body")
    if body is None:
        body = doc
    b = Builder(path)
    blocks = b.blocks(body)
    src = b.source_text(body)
    links = [el.get("href") for el in body.iter("a") if el.get("href")]
    # 页面依赖的外部样式表：还原观感需要它，丢掉就没法复现
    css = [el.get("href") for el in doc.iter("link")
           if "stylesheet" in (el.get("rel") or "").lower() and el.get("href")]
    dropped = {
        el.get("id") for el in body.iter()
        if isinstance(el.tag, str) and el.tag.lower() in IGNORED_TAGS and el.get("id")
    }
    imgs = [el.get("src") for el in body.iter("img") if el.get("src")]
    style = _strip_defaults(blocks)
    # 哈希要覆盖整页，包括页级样式与样式表依赖，否则改了这些 C6 看不见
    digest = hashlib.sha256(
        json.dumps({"blocks": blocks, "style": style, "css": css},
                   ensure_ascii=False, sort_keys=True).encode()
    ).hexdigest()[:16]
    return {
        "path": path,
        "encoding": enc,
        "title": _title(doc),
        "style": style,
        "css": css,
        "blocks": blocks,
        "hash": digest,
        "_check": {
            "src_text": norm_text(src),
            "block_text": norm_text(blocks_text(blocks)),
            "ids_src": b.ids,
            "ids_block": _collect_ids(blocks),
            "ids_dropped": dropped,
            "unknown_tags": dict(b.unknown_tags),
            "malformed_tags": dict(b.malformed_tags),
            "degraded": dict(b.degraded),
            "images_used": dict(b.images_used),
            "images_dropped": b.images_dropped,
            "links_dropped": b.links_dropped,
            "transparent": dict(b.tag_transparent),
            "ignored": dict(b.tag_ignored),
            "color_runs": b.color_runs,
            "links": links,
            "imgs": imgs,
        },
    }


def _title(doc) -> str:
    t = doc.find(".//title")
    return (t.text or "").strip() if t is not None else ""


def _collect_ids(blocks: list[dict]) -> set[str]:
    ids: set[str] = set()

    def walk(bs):
        for b in bs:
            if b.get("id"):
                ids.add(b["id"])
            for a in b.get("anchors", ()):
                ids.add(a)
            if b["type"] == "list":
                for it in b["items"]:
                    walk(it["blocks"])
            elif b["type"] == "table":
                for row in b["rows"]:
                    for c in row["cells"]:
                        walk(c["blocks"])
            elif b["type"] in ("quote", "div"):
                walk(b["blocks"])

    walk(blocks)
    return ids


# ---------------- 实体标注：法术 ----------------

CN_NUM = {"零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6,
          "七": 7, "八": 8, "九": 9, "十": 10}


def _runs_text(runs: list[dict]) -> str:
    return "".join(r.get("t", "") for r in runs)


FIELD_LABELS = ("施法时间", "施法距离", "法术成分", "持续时间")
FIELD_KEYS = {
    "施法时间": "casting_time", "施法距离": "range",
    "法术成分": "components", "持续时间": "duration",
}


def _fields(rest: str) -> dict:
    """按字段标签切分。最后一个字段（持续时间）之后紧接正文，以换行为界。"""
    pat = re.compile("(" + "|".join(re.escape(l) + "[：:]" for l in FIELD_LABELS) + ")")
    chunks = pat.split(rest)
    out: dict = {}
    for i in range(1, len(chunks), 2):
        label = chunks[i].rstrip("：:")
        val = chunks[i + 1] if i + 1 < len(chunks) else ""
        if label == "持续时间":
            val = val.split(SEP)[0]
        key = FIELD_KEYS.get(label)
        if key:
            out[key] = re.sub(r"\s+", " ", val).strip()
    return out


def extract_spells(blocks: list[dict]) -> list[dict]:
    """从 block 序列里抽法术条目。

    形态（2014 与 2024 同构）：<H4 id="En_Name">中文｜English</H4>
    紧跟一个 P，首段是 <EM>环阶 学派（职业）</EM>，其后是 <STRONG>字段：</STRONG>。
    """
    out: list[dict] = []
    i = 0
    n = len(blocks)
    while i < n:
        b = blocks[i]
        if b["type"] != "h" or b["level"] != 4 or not b.get("id"):
            i += 1
            continue
        raw = _runs_text(b["runs"]).strip()
        if "｜" not in raw:
            i += 1
            continue
        name_zh, _, name_en = raw.partition("｜")
        entry = {
            "id": b["id"],
            "name_zh": name_zh.strip(),
            "name_en": name_en.strip(),
            "level": None, "school": None, "ritual": False, "classes": [],
            "casting_time": None, "range": None, "components": None, "duration": None,
            "text": "",
        }
        body: list[dict] = []
        j = i + 1
        while j < n and not (blocks[j]["type"] == "h" and blocks[j]["level"] <= 4 and blocks[j].get("id")):
            body.append(blocks[j])
            j += 1

        if body and body[0]["type"] == "p":
            runs = body[0]["runs"]
            head = _runs_text(runs).split(SEP)[0]
            pos = 0
            if head:
                # 两版顺序不同：2014 是「一环 防护（…）」，2024 是「塑能 戏法（…）」，
                # 所以不按位置取值，按词形识别环阶。
                core, sep, tail = head.partition("（")
                if not sep:
                    core, sep, tail = head.partition("(")
                tail = tail.strip().rstrip("）)")
                for tok in (t for t in re.split(r"[\s　]+", core.strip()) if t):
                    if tok == "戏法" or re.fullmatch(r"[零一二三四五六七八九十]环", tok):
                        entry["level"] = 0 if tok == "戏法" else CN_NUM.get(tok[0])
                    elif entry["school"] is None:
                        entry["school"] = tok
                entry["ritual"] = "仪式" in tail
                entry["classes"] = [
                    c.strip() for c in re.split(r"[、,，；;]", tail.replace("仪式", ""))
                    if c.strip()
                ]
                rest = "".join(
                    r.get("t", "") for k, r in enumerate(runs) if k >= pos
                )
                entry.update(_fields(rest))
        entry["text"] = _runs_text(
            [r for bb in body for r in (bb.get("runs") or [])]
        ).strip()
        out.append(entry)
        i = j
    return out

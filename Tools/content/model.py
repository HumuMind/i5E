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

from inline_css import heading_styles, table_has_border

# 空白与不可见字符：比较文本时整体剔除，避免 <BR>、缩进、全角空格造成误报。
# 行分隔符只由 <BR> 产生，用来区分"结构换行"与源码里的普通换行。
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


# 拆分出去的模块；这里按原名导入，调用处不需要改动
from paths import IMAGE_ROOT, configure_images, resolve_image, resolve_link
from spells import extract_spells
from styles import _align_indent, _cls, _color, _style_of
from text_utils import SEP, WS, _merge, _runs_text, clean_text, decode, norm_text

class Builder:
    def __init__(self, page_path: str = "") -> None:
        self.page_path = page_path
        # 页面内联 <style> 里对标题的颜色/字重覆盖（见 inline_css.py）
        self.heading_styles: dict[int, dict] = {}
        # 页面 CSS 是否统一给 table 加了边框（没有的话表格默认无边框）
        self.table_border = False
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
                    run = {"img": resolved, "alt": el.get("alt") or ""}
                    for key in ("width", "height"):
                        value = (el.get(key) or "").strip().rstrip("px")
                        if value.isdigit():
                            run["w" if key == "width" else "h"] = int(value)
                    align = (el.get("align") or "").strip().lower()
                    if align in ("left", "right"):
                        run["align"] = align
                    out.append(run)
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
                out.append({**nxt, "t": clean_text(el.text)})
            for ch in el:
                self._inline_into(ch, nxt, out)
                if ch.tail:
                    out.append({**nxt, "t": clean_text(ch.tail)})
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
            level_style = self.heading_styles.get(int(tag[1]))
            if level_style:
                block["style"] = level_style
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
                calign = _cell_align(td)
                if calign:
                    cell["al"] = calign
                cells.append(cell)
            row = {"cells": cells}
            if row_bg:
                row["bg"] = row_bg
            rows.append(row)
        width_px, width_pct = _table_width(el)
        caption = ""
        cap = el.find("caption")
        if cap is not None:
            # 源页 caption 里常有换行，折叠成单空格，否则渲染时会被当硬换行
            caption = clean_text("".join(cap.itertext())).strip()
        tb = {"type": "table", "rows": rows, "caption": caption}
        # 源页只有写了 border 属性（或页面 CSS 统一加边框）才画格子
        if self.table_border or _has_border_attr(el):
            tb["bd"] = 1
        if width_px:
            tb["w"] = width_px
        if width_pct:
            tb["wp"] = width_pct
        talign = _table_align(el)
        if talign:
            tb["al"] = talign
        if _cls(el):
            tb["cls"] = _cls(el)
        return tb

_WIDTH_PX = re.compile(r"WIDTH\s*:\s*(\d+)\s*(?:px)?", re.I)
_WIDTH_PCT = re.compile(r"WIDTH\s*:\s*(\d+)\s*%", re.I)


def _cell_align(el) -> str | None:
    """单元格对齐：`align` 属性或内联 `text-align`。"""
    value = (el.get("align") or "").strip().lower()
    if not value:
        m = re.search(r"text-align\s*:\s*(\w+)", el.get("style") or "", re.I)
        value = m.group(1).lower() if m else ""
    return {"center": "c", "right": "r", "justify": "j"}.get(value)


def _table_align(el) -> str | None:
    """整张表格的水平居中。"""
    if (el.get("align") or "").strip().lower() == "center":
        return "c"
    style = (el.get("style") or "").lower()
    return "c" if "auto" in style and "margin" in style else None


def _has_border_attr(el) -> bool:
    """`border` 属性或内联 `border:` 声明。"""
    value = (el.get("border") or "").strip()
    if value.isdigit() and int(value) > 0:
        return True
    style = (el.get("style") or "").lower()
    return "border" in style and "none" not in style


def _table_width(el) -> tuple[int | None, int | None]:
    """表格的显式宽度：`(px, 百分比)`。源页里 1,365 张表写了 px、709 张写了百分比。"""
    style = el.get("style") or ""
    pct = _WIDTH_PCT.search(style)
    if pct:
        return None, int(pct.group(1))
    px = _WIDTH_PX.search(style)
    if px:
        return int(px.group(1)), None
    return None, None


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
    b.heading_styles = heading_styles(text)
    b.table_border = table_has_border(text)
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
        "title": _title(doc, blocks),
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


def _title(doc, blocks: list[dict] | None = None) -> str:
    """页面标题：优先用正文里的一级标题。

    109 个页面的 `<title>` 是「08 命运」这种简写，h1 才是「第八章：命运 Fates」，
    搜索结果里显示后者更清楚。
    """
    for block in blocks or []:
        if block.get("type") == "h" and block.get("level") == 1:
            text = "".join(run.get("t") or "" for run in block.get("runs") or []).strip()
            if text:
                return text
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

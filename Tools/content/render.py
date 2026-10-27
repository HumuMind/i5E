"""block → HTML。两个用途：C5 往返校验、黄金样本预览。"""

from __future__ import annotations

import html
import re

from model import SEP

INLINE_ORDER = ("code", "b", "i", "u", "s", "sup", "sub")

FAMILY_CSS = {
    "song": "'Songti SC','SimSun',serif",
    "hei": "'Heiti SC','SimHei',sans-serif",
    "kai": "'Kaiti SC','KaiTi',serif",
    "fang": "'FangSong','STFangsong',serif",
    "sans": "'Helvetica Neue',Arial,sans-serif",
    "times": "'Times New Roman',serif",
    "mono": "'Menlo','Courier New',monospace",
}


def _decl(style: dict | None) -> str:
    if not style:
        return ""
    p = []
    if style.get("c"):
        p.append(f"color:{style['c']}")
    if style.get("sz"):
        p.append(f"font-size:{style['sz']}pt")
    if style.get("fa"):
        p.append(f"font-family:{FAMILY_CSS.get(style['fa'], 'inherit')}")
    return ";".join(p)


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def render_runs(runs: list[dict], defaults: dict | None = None, faithful: bool = False) -> str:
    out = []
    for r in runs:
        if r.get("img"):
            out.append(
                f'<img class="inline-img" src="{html.escape(r["img"])}" '
                f'alt="{html.escape(r.get("alt", ""))}">'
            )
            continue
        t = esc(r.get("t", "")).replace("\n", " ").replace(SEP, "<br>")
        if faithful:
            st = {k: r.get(k, (defaults or {}).get(k)) for k in ("c", "sz", "fa")}
            decl = _decl(st)
            if decl:
                t = f'<span style="{decl}">{t}</span>'
        for flag in INLINE_ORDER:
            if r.get(flag):
                t = f"<{flag}>{t}</{flag}>"
        if r.get("href"):
            mark = f' data-mention="{r["m"]}"' if r.get("m") else ""
            t = f'<a href="{html.escape(r["href"])}"{mark}>{t}</a>'
        out.append(t)
    return "".join(out)


def _clsattr(b: dict) -> str:
    return f' class="{html.escape(" ".join(b["cls"]))}"' if b.get("cls") else ""


def render_blocks(blocks: list[dict], raw_href: bool = True,
                  defaults: dict | None = None, faithful: bool = False) -> str:
    out: list[str] = []
    for b in blocks:
        t = b["type"]
        blk = ""
        if faithful and b.get("al"):
            blk += f"text-align:${{'center' if b['al']=='c' else 'right' if b['al']=='r' else 'justify'}};"
        if faithful and b.get("ind"):
            blk += f"text-indent:{b['ind']}em;"
        battr = f' style="{blk}"' if blk else ""
        battr = _clsattr(b) + battr
        if t == "h":
            lv = b["level"]
            idattr = f' id="{html.escape(b["id"])}"' if b.get("id") else ""
            out.append(f"<h{lv}{idattr}{battr}>{render_runs(b['runs'], defaults, faithful)}</h{lv}>")
        elif t == "p":
            out.append(f"<p{battr}>{render_runs(b['runs'], defaults, faithful)}</p>")
        elif t == "list":
            tag = "ol" if b["ordered"] else "ul"
            items = []
            for it in b["items"]:
                items.append(
                    f"<li>{render_runs(it['runs'], defaults, faithful)}"
                    f"{render_blocks(it['blocks'], defaults=defaults, faithful=faithful)}</li>"
                )
            out.append(f"<{tag}>{''.join(items)}</{tag}>")
        elif t == "table":
            out.append(render_table(b, defaults, faithful))
        elif t == "quote":
            out.append(f"<blockquote{_clsattr(b)}>"
                       f"{render_blocks(b['blocks'], defaults=defaults, faithful=faithful)}</blockquote>")
        elif t == "div":
            out.append(f"<div{_clsattr(b)}>"
                       f"{render_blocks(b['blocks'], defaults=defaults, faithful=faithful)}</div>")
        elif t == "pre":
            out.append(f"<pre>{esc(b['text'])}</pre>")
        elif t == "hr":
            out.append("<hr>")
        elif t in ("dt", "dd"):
            out.append(f"<{t}{battr}>{render_runs(b['runs'], defaults, faithful)}</{t}>")
    return "".join(out)


def render_table(b: dict, defaults=None, faithful: bool = False) -> str:
    parts = [f"<table{_clsattr(b)}>"]
    if b.get("caption"):
        parts.append(f"<caption>{esc(b['caption'])}</caption>")
    for row in b["rows"]:
        rbg = f' style="background:{row["bg"]}"' if b.get("cls") is not None and row.get("bg") else ""
        parts.append(f"<tr{rbg}>")
        for c in row["cells"]:
            tag = "th" if c.get("header") else "td"
            attrs = f' class="{html.escape(" ".join(c["cls"]))}"' if c.get("cls") else ""
            if c.get("bg"):
                attrs += f' style="background:{c["bg"]}"'
            if c.get("colspan", 1) > 1:
                attrs += f' colspan="{c["colspan"]}"'
            if c.get("rowspan", 1) > 1:
                attrs += f' rowspan="{c["rowspan"]}"'
            inner = c["blocks"]
            # 单元格里只有一个普通段落时不要外套 <p>：源页也没有，
            # 多一层会带进默认段距，把表格撑得比原页高一大截
            if len(inner) == 1 and inner[0]["type"] == "p" and not any(
                    k in inner[0] for k in ("al", "ind", "cls", "anchors")):
                body = render_runs(inner[0]["runs"], defaults, faithful)
            else:
                body = render_blocks(inner, defaults=defaults, faithful=faithful)
            parts.append(f"<{tag}{attrs}>{body}</{tag}>")
        parts.append("</tr>")
    parts.append("</table>")
    return "".join(parts)


def canon(blocks: list[dict]) -> list:
    """用于比较的规范化视图：折平空白、丢掉空 run、只留结构。"""
    out = []
    for b in blocks:
        t = b["type"]
        item: dict = {"t": t}
        if t == "h":
            item["l"] = b["level"]
            if b.get("id"):
                item["id"] = b["id"]
            item["r"] = canon_runs(b["runs"])
        elif t == "p":
            item["r"] = canon_runs(b["runs"])
        elif t == "list":
            item["o"] = 1 if b["ordered"] else 0
            item["i"] = [
                {"r": canon_runs(it["runs"]), "b": canon(it["blocks"])} for it in b["items"]
            ]
        elif t == "table":
            item["c"] = b.get("caption", "")
            item["rows"] = [
                {
                    "cells": [
                        {
                            "s": c.get("colspan", 1),
                            "r": c.get("rowspan", 1),
                            "h": 1 if c.get("header") else 0,
                            "b": canon(c["blocks"]),
                        }
                        for c in row["cells"]
                    ]
                }
                for row in b["rows"]
            ]
        elif t in ("quote", "div"):
            item["b"] = canon(b["blocks"])
            if b.get("cls"):
                item["cls"] = b["cls"]
        elif t in ("p", "h", "table", "list") and b.get("cls"):
            item["cls"] = b["cls"]
        elif t == "pre":
            item["x"] = re.sub(r"\s+", " ", b["text"]).strip()
        elif t in ("dt", "dd"):
            item["r"] = canon_runs(b["runs"])
        out.append(item)
    return out


def canon_runs(runs: list[dict]) -> list:
    out = []
    for r in runs:
        if r.get("img"):
            out.append({"img": r["img"], "alt": r.get("alt", "")})
            continue
        txt = re.sub(r"[\s" + SEP + r"]+", " ", r.get("t", ""))
        if not txt:
            continue
        d = {k: v for k, v in r.items()
             if k != "t" and v and k not in ("c", "sz", "fa")}
        flags = dict(d)
        d["t"] = txt
        # 相邻且样式相同的 run 合并：run 怎么切分是表示细节，不该影响比对
        if out and {k: v for k, v in out[-1].items() if k != "t"} == flags:
            # 合并后要重新折平空白，否则两段各带一个空格会拼成两个
            out[-1]["t"] = re.sub(r"[\s" + SEP + r"]+", " ", out[-1]["t"] + txt)
            continue
        out.append(d)
    return out

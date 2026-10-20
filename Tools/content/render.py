"""block → HTML。两个用途：C5 往返校验、黄金样本预览。"""

from __future__ import annotations

import html
import re

from model import SEP

INLINE_ORDER = ("code", "b", "i", "u", "s", "sup", "sub")


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def render_runs(runs: list[dict]) -> str:
    out = []
    for r in runs:
        if r.get("img"):
            out.append(
                f'<img class="inline-img" src="{html.escape(r["img"])}" '
                f'alt="{html.escape(r.get("alt", ""))}">'
            )
            continue
        t = esc(r.get("t", "")).replace("\n", " ").replace(SEP, "<br>")
        for flag in INLINE_ORDER:
            if r.get(flag):
                t = f"<{flag}>{t}</{flag}>"
        if r.get("href"):
            t = f'<a href="{html.escape(r["href"])}">{t}</a>'
        out.append(t)
    return "".join(out)


def render_blocks(blocks: list[dict], raw_href: bool = True) -> str:
    out: list[str] = []
    for b in blocks:
        t = b["type"]
        if t == "h":
            lv = b["level"]
            idattr = f' id="{html.escape(b["id"])}"' if b.get("id") else ""
            out.append(f"<h{lv}{idattr}>{render_runs(b['runs'])}</h{lv}>")
        elif t == "p":
            out.append(f"<p>{render_runs(b['runs'])}</p>")
        elif t == "list":
            tag = "ol" if b["ordered"] else "ul"
            items = []
            for it in b["items"]:
                items.append(
                    f"<li>{render_runs(it['runs'])}{render_blocks(it['blocks'])}</li>"
                )
            out.append(f"<{tag}>{''.join(items)}</{tag}>")
        elif t == "table":
            out.append(render_table(b))
        elif t == "quote":
            out.append(f"<blockquote>{render_blocks(b['blocks'])}</blockquote>")
        elif t == "pre":
            out.append(f"<pre>{esc(b['text'])}</pre>")
        elif t == "hr":
            out.append("<hr>")
        elif t in ("dt", "dd"):
            out.append(f"<{t}>{render_runs(b['runs'])}</{t}>")
    return "".join(out)


def render_table(b: dict) -> str:
    parts = ["<table>"]
    if b.get("caption"):
        parts.append(f"<caption>{esc(b['caption'])}</caption>")
    for row in b["rows"]:
        parts.append("<tr>")
        for c in row["cells"]:
            tag = "th" if c.get("header") else "td"
            attrs = ""
            if c.get("colspan", 1) > 1:
                attrs += f' colspan="{c["colspan"]}"'
            if c.get("rowspan", 1) > 1:
                attrs += f' rowspan="{c["rowspan"]}"'
            parts.append(f"<{tag}{attrs}>{render_blocks(c['blocks'])}</{tag}>")
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
        elif t == "quote":
            item["b"] = canon(b["blocks"])
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
        d = {k: v for k, v in r.items() if k != "t" and v}
        d["t"] = txt
        out.append(d)
    return out

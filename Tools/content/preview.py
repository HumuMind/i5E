"""黄金样本预览：左边渲染结果，右边 block 结构。"""

from __future__ import annotations

import os
import posixpath
import re
from pathlib import Path
from urllib.parse import quote

from model import SEP
from render import esc, render_blocks, render_runs

CSS = """
:root { --ink:#1c1a17; --dim:#6b645c; --line:#e2ddd4; --bg:#fbf9f5; --accent:#8a4b2a; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink);
  font-family:"Songti SC","Source Han Serif SC",Georgia,serif; line-height:1.85; }
.wrap { display:grid; grid-template-columns:minmax(0,1fr) 340px; gap:0; min-height:100vh; }
.main { padding:48px 56px 120px; max-width:820px; }
.rail { border-left:1px solid var(--line); background:#fff; padding:28px 20px; overflow:auto;
  max-height:100vh; position:sticky; top:0;
  font-family:-apple-system,"PingFang SC",sans-serif; font-size:12px; line-height:1.5; }
.rail h2 { font-size:12px; letter-spacing:.12em; color:var(--dim); text-transform:uppercase;
  margin:0 0 12px; font-weight:600; }
.meta { color:var(--dim); margin-bottom:18px; }
.meta div { margin:2px 0; }
ol.outline { list-style:none; margin:0; padding:0; }
ol.outline li { display:grid; grid-template-columns:58px 1fr; gap:8px; padding:3px 0;
  border-bottom:1px dotted #eee; }
ol.outline .tag { color:var(--accent); font-family:ui-monospace,Menlo,monospace; font-size:11px; }
ol.outline .txt { color:#333; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
h1,h2,h3,h4,h5 { line-height:1.4; margin:1.6em 0 .7em; font-weight:600; }
h1 { font-size:2em; } h2 { font-size:1.5em; } h3 { font-size:1.25em; }
h4 { font-size:1.05em; color:var(--accent); }
p { margin:0 0 1em; text-align:justify; }
strong { font-weight:700; }
a { color:#704cd9; text-decoration:none; border-bottom:1px solid #d9cff7; }
table { border-collapse:collapse; width:100%; margin:1.2em 0; font-size:.94em; }
td,th { border:1px solid var(--line); padding:7px 9px; vertical-align:top; }
th { background:#f3efe7; font-weight:600; }
td p, th p { margin:0 0 .4em; } td p:last-child, th p:last-child { margin:0; }
blockquote { margin:1.2em 0; padding:.4em 1.1em; border-left:3px solid var(--accent);
  background:#fff; color:#413a33; }
pre { background:#fff; border:1px solid var(--line); padding:12px; overflow:auto; font-size:.86em; }
img { max-width:100%; height:auto; }
img.inline-img { vertical-align:middle; }
hr { border:none; border-top:1px solid var(--line); margin:2em 0; }
ul,ol { padding-left:1.4em; }
li { margin:.3em 0; }
.topbar { font-family:-apple-system,"PingFang SC",sans-serif; font-size:12px; color:var(--dim);
  padding:14px 56px; border-bottom:1px solid var(--line); background:#fff; position:sticky; top:0; }
.topbar a { margin-right:14px; }
.idx { max-width:900px; margin:0 auto; padding:56px 32px 120px; }
.idx h1 { font-size:2.2em; }
.idx .sub { color:var(--dim); margin-bottom:36px; }
.card { border:1px solid var(--line); background:#fff; border-radius:6px; padding:16px 20px;
  margin:0 0 12px; display:grid; grid-template-columns:36px 1fr; gap:14px; }
.card .n { color:var(--accent); font-family:ui-monospace,Menlo,monospace; }
.card .p { font-family:ui-monospace,Menlo,monospace; font-size:12.5px; color:#333; word-break:break-all; }
.card .f { font-size:12px; color:var(--dim); margin-top:6px;
  font-family:-apple-system,"PingFang SC",sans-serif; }
.card a { border:none; }
@media (max-width: 900px) { .wrap { grid-template-columns:1fr; } .rail { display:none; } .main { padding:28px 22px 80px; } }
"""


def _brief(b: dict) -> str:
    t = b["type"]
    if t in ("h", "p", "dt", "dd"):
        txt = re.sub(r"\s+", " ", render_runs(b.get("runs", [])).replace(SEP, " "))
        txt = re.sub(r"<[^>]+>", "", txt)
        return txt[:46]
    if t == "table":
        rows = len(b["rows"])
        cols = max((len(r["cells"]) for r in b["rows"]), default=0)
        return f"{rows}×{cols}" + (" 含合并" if any(c.get("colspan", 1) > 1 or c.get("rowspan", 1) > 1
                                                for r in b["rows"] for c in r["cells"]) else "")
    if t == "list":
        kind = "ol" if b["ordered"] else "ul"
        return f"{kind} {len(b['items'])} 项"
    if t == "quote":
        return f"{len(b['blocks'])} 块"
    if t == "pre":
        return f"{len(b['text'])} 字符"
    return ""


def _tag(b: dict) -> str:
    return b["type"] + (str(b.get("level", "")) if b["type"] == "h" else "")


def _fix_src(page_path: str, src: str, root: Path) -> str:
    """图片同样有"相对文件目录"和"相对语料根"两种写法，都要试。"""
    if re.match(r"^[a-z]+:", src or "", re.I):
        return src
    for cand in (posixpath.join(posixpath.dirname(page_path), src), src.lstrip("/")):
        target = root / posixpath.normpath(cand)
        if target.exists():
            return target.resolve().as_uri()
    return src


def _rewrite_imgs(blocks, page_path: str, root: Path):
    for b in blocks:
        if b["type"] == "p":
            for r in b.get("runs", []):
                if r.get("img"):
                    r["img"] = _fix_src(page_path, r["img"], root)
        elif b["type"] in ("quote",):
            _rewrite_imgs(b["blocks"], page_path, root)
        elif b["type"] == "list":
            for it in b["items"]:
                _rewrite_imgs(it["blocks"], page_path, root)
        elif b["type"] == "table":
            for row in b["rows"]:
                for c in row["cells"]:
                    _rewrite_imgs(c["blocks"], page_path, root)


def write_preview(out: Path, records: list[dict], samples: list[dict], root: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    cards = []
    for i, rec in enumerate(records, 1):
        meta = samples[i - 1]
        _rewrite_imgs(rec["blocks"], rec["path"], root)
        body = render_blocks(rec["blocks"])
        outline = "".join(
            f'<li><span class="tag">{esc(_tag(b))}</span>'
            f'<span class="txt">{esc(_brief(b))}</span></li>'
            for b in rec["blocks"]
        )
        c = rec["_check"]
        page = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<title>{esc(rec['title'] or rec['path'])}</title><style>{CSS}</style></head><body>
<div class="topbar"><a href="index.html">← 样本列表</a>
<span>{i}/{len(records)} · {esc(rec['path'])}</span></div>
<div class="wrap"><div class="main">{body or '<p>（空页）</p>'}</div>
<aside class="rail"><h2>block 结构</h2>
<div class="meta"><div>来源 {esc(c['family'])} · 编码 {esc(rec['encoding'])}</div>
<div>{len(c['block_text']):,} 字符 · {len(rec['blocks'])} 块</div>
<div>{len(c['imgs'])} 图 · {len(c['links'])} 链 · {c['color_runs']} 彩色 run</div></div>
<ol class="outline">{outline}</ol></aside></div></body></html>"""
        (out / f"page-{i:02d}.html").write_text(page, encoding="utf-8")
        cards.append(f"""<div class="card"><div class="n">{i:02d}</div><div>
<a class="p" href="page-{i:02d}.html">{esc(rec['path'])}</a>
<div class="f">{len(rec['blocks'])} 块 · {meta['bytes']:,} 字节 · {esc(', '.join(meta['why']))}</div>
</div></div>""")

    index = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<title>i5E 解析预览</title><style>{CSS}</style></head><body>
<div class="idx"><h1>解析预览</h1>
<div class="sub">黄金样本 {len(records)} 页。左侧为 block 重新渲染的结果，页内右侧栏是解析出的结构。
点开任一页，对照原文与结构，检查有没有塌掉的地方。</div>
{''.join(cards)}
</div></body></html>"""
    (out / "index.html").write_text(index, encoding="utf-8")

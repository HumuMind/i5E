"""C1–C6 检查。对应 Docs/decisions/0003-translation-verification.md。"""

from __future__ import annotations

import json
import posixpath
import re
from collections import Counter
from urllib.parse import unquote

from model import parse_page
from render import canon, render_blocks

HTML_EXT = (".htm", ".html")
SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*:", re.I)


def _first_diff(a: str, b: str, width: int = 40):
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return {
                "at": i,
                "src": a[max(0, i - width): i + width],
                "out": b[max(0, i - width): i + width],
            }
    if len(a) != len(b):
        longer, side = (a, "src") if len(a) > len(b) else (b, "out")
        return {"at": min(len(a), len(b)), "side": side, "extra": longer[min(len(a), len(b)):][:120]}
    return None


# ---------------- C1 文本守恒 ----------------

def c1(rec) -> dict:
    c = rec["_check"]
    ok = c["src_text"] == c["block_text"]
    return {"pass": ok, "diff": None if ok else _first_diff(c["src_text"], c["block_text"])}


# ---------------- C2 节点覆盖 ----------------

def c2(records, known_tags) -> dict:
    unknown: Counter = Counter()
    where: dict[str, list[str]] = {}
    ignored: Counter = Counter()
    transparent: Counter = Counter()
    malformed: Counter = Counter()
    for r in records:
        c = r["_check"]
        for tag, n in c["unknown_tags"].items():
            unknown[tag] += n
            if tag not in where:
                where[tag] = []
            if len(where[tag]) < 3:
                where[tag].append(r["path"])
        for tag, n in c.get("malformed_tags", {}).items():
            malformed[tag] += n
        for tag, n in c["ignored"].items():
            ignored[tag] += n
        for tag, n in c["transparent"].items():
            transparent[tag] += n
    return {
        "unknown_tags": dict(unknown.most_common(30)),
        "unknown_examples": where,
        "ignored": dict(ignored.most_common(20)),
        "transparent": dict(transparent.most_common(20)),
        "malformed": dict(malformed.most_common(10)),
        "pass": not unknown,
    }


# ---------------- C3 锚点与链接 ----------------

def _split(href: str):
    href = unquote(href.strip()).replace("\\", "/")
    if not href:
        return None
    if SCHEME.match(href) and not href.lower().startswith("file:"):
        return ("external", href)
    if href.startswith("#"):
        return ("frag", "", href[1:])
    path, _, frag = href.partition("#")
    return ("path", path, frag)


def _resolve(raw: str, base: str, paths: set[str], lower: dict[str, str]):
    """CHM 里的内部链接大多相对**语料根**，而不是相对文件所在目录。
    实测 6390 条只有按根解析才命中，352 条按目录解析。所以两条都试。
    """
    d = posixpath.dirname(base)
    for mode, cand in (("ok_rel", posixpath.normpath(posixpath.join(d, raw))),
                       ("ok_root", posixpath.normpath(raw))):
        if cand in paths:
            return mode, cand
        sw = cand[:-5] + (".htm" if cand.lower().endswith(".html") else ".html")
        if sw in paths:
            return "ext_mismatch", sw
        if cand.lower() in lower:
            return "case_mismatch", lower[cand.lower()]
    return None


def c3(records) -> dict:
    paths = {r["path"]: r for r in records}
    lower = {}
    for p in paths:
        lower.setdefault(p.lower(), p)
    ids = {r["path"]: set(r["_check"]["ids_block"]) for r in records}
    dropped_ids = {r["path"]: set(r["_check"].get("ids_dropped") or ()) for r in records}

    stats = Counter()
    broken_file: dict[str, list[str]] = {}
    broken_frag: dict[str, list[str]] = {}
    case_mismatch: dict[str, list[str]] = {}

    for r in records:
        base = r["path"]
        for href in r["_check"]["links"]:
            sp = _split(href)
            if not sp:
                continue
            if sp[0] == "external":
                stats["external"] += 1
                continue
            if sp[0] == "frag":
                target, frag = base, sp[2]
                stats["self_frag"] += 1
            else:
                raw = sp[1].lstrip("/")
                frag = sp[2]
                if not raw.lower().endswith(HTML_EXT):
                    stats["non_html"] += 1
                    continue
                stats["internal"] += 1
                target = _resolve(raw, base, paths, lower)
                if target is None:
                    stats["broken_file"] += 1
                    rel = posixpath.normpath(posixpath.join(posixpath.dirname(base), raw))
                    broken_file.setdefault(rel, []).append(f"{base} → {href}")
                    continue
                mode, target = target
                stats[mode] += 1
                if mode == "case_mismatch":
                    case_mismatch.setdefault(target, []).append(f"{base} → {href}")
            if frag:
                if frag in ids.get(target, set()):
                    stats["frag_ok"] += 1
                elif frag in dropped_ids.get(target, set()):
                    stats["dropped_frag"] += 1
                else:
                    stats["broken_frag"] += 1
                    broken_frag.setdefault(f"{target}#{frag}", []).append(base)

    # 源文件里声明了 id 但 block 里丢了（等于把锚点弄断）
    lost_ids = []
    for r in records:
        lost = r["_check"]["ids_src"] - r["_check"]["ids_block"]
        if lost:
            lost_ids.append({"path": r["path"], "ids": sorted(lost)[:5]})
            stats["lost_ids"] += len(lost)

    return {
        "stats": dict(stats),
        "broken_file": {k: v[:3] for k, v in list(broken_file.items())[:40]},
        "broken_frag": {k: v[:3] for k, v in list(broken_frag.items())[:40]},
        "case_mismatch": {k: v[:3] for k, v in list(case_mismatch.items())[:40]},
        "lost_ids": lost_ids[:40],
        "pass": stats["broken_file"] == 0 and stats["broken_frag"] == 0 and stats["lost_ids"] == 0,
    }


# ---------------- C4 schema ----------------

BLOCK_TYPES = {"h", "p", "list", "table", "quote", "pre", "hr", "dt", "dd"}
RUN_KEYS = {"t", "img", "alt", "b", "i", "u", "s", "sup", "sub", "code", "href"}


def _schema(blocks) -> list[str]:
    errs: list[str] = []
    for b in blocks:
        if not isinstance(b, dict) or b.get("type") not in BLOCK_TYPES:
            errs.append(f"bad block: {str(b)[:80]}")
            continue
        t = b["type"]
        if t == "h":
            if not isinstance(b.get("level"), int) or not 1 <= b["level"] <= 6:
                errs.append(f"bad level: {b.get('level')}")
            errs += _runs_err(b.get("runs"))
        elif t in ("p", "dt", "dd"):
            errs += _runs_err(b.get("runs"))
        elif t == "list":
            for it in b.get("items", []):
                errs += _runs_err(it.get("runs"))
                errs += _schema(it.get("blocks", []))
        elif t == "table":
            for row in b.get("rows", []):
                for c in row.get("cells", []):
                    if c.get("colspan", 1) < 1 or c.get("rowspan", 1) < 1:
                        errs.append("bad span")
                    errs += _schema(c.get("blocks", []))
        elif t == "quote":
            errs += _schema(b.get("blocks", []))
        elif t == "pre":
            if not isinstance(b.get("text"), str):
                errs.append("pre without text")
    return errs


def _runs_err(runs) -> list[str]:
    if not isinstance(runs, list):
        return ["runs not list"]
    errs = []
    for r in runs:
        if not isinstance(r, dict):
            errs.append("run not dict")
            continue
        if not ({"t"} & set(r) or "img" in r):
            errs.append(f"run without text: {r}")
        if set(r) - RUN_KEYS:
            errs.append(f"unknown run keys: {set(r) - RUN_KEYS}")
    return errs[:5]


def c4(records) -> dict:
    bad = []
    for r in records:
        errs = _schema(r["blocks"])
        if errs:
            bad.append({"path": r["path"], "errs": errs[:5]})
    return {"bad_count": len(bad), "examples": bad[:30], "pass": not bad}


# ---------------- C5 往返保真 ----------------

def _reparse(blocks, path):
    html = "<html><body>" + render_blocks(blocks) + "</body></html>"
    return parse_page(path, html.encode("utf-8"))


def c5(records, limit=None) -> dict:
    bad = []
    checked = 0
    for r in records:
        if limit and checked >= limit:
            break
        checked += 1
        try:
            again = _reparse(r["blocks"], r["path"])
        except Exception as e:  # noqa: BLE001
            bad.append({"path": r["path"], "err": f"reparse raised: {e}"})
            continue
        a, b = canon(r["blocks"]), canon(again["blocks"])
        if a != b:
            diff = _first_block_diff(a, b)
            bad.append({"path": r["path"], "diff": diff})
    return {"checked": checked, "bad_count": len(bad), "examples": bad[:30], "pass": not bad}


def _first_block_diff(a, b):
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return {"index": i, "before": json.dumps(a[i], ensure_ascii=False)[:300],
                    "after": json.dumps(b[i], ensure_ascii=False)[:300]}
    if len(a) != len(b):
        return {"len_before": len(a), "len_after": len(b),
                "tail": json.dumps((a if len(a) > len(b) else b)[min(len(a), len(b)):][:2],
                                   ensure_ascii=False)[:300]}
    return {"equal": True}


# ---------------- C6 回归哈希 ----------------

def c6(records, baseline: dict | None) -> dict:
    cur = {r["path"]: r["hash"] for r in records}
    if baseline is None:
        return {"baseline": False, "pages": len(cur), "pass": True}
    changed = [p for p in cur if p in baseline and baseline[p] != cur[p]]
    added = [p for p in cur if p not in baseline]
    removed = [p for p in baseline if p not in cur]
    return {
        "baseline": True,
        "changed": len(changed),
        "added": len(added),
        "removed": len(removed),
        "changed_sample": changed[:30],
        "pass": not changed and not removed,
    }

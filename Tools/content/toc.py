"""解析上游 CHM 工程文件（.wcp）里的目录树。

.wcp 是 UTF-16LE 的 INI：
    [TOPICS]
    TitleList=8544
    TitleList.Title.0=写在前面
    TitleList.Level.0=0
    TitleList.Url.0=写在前面.html
    ...

Level 是深度（0 起），父节点是前面最近的、层级更小的那条；层级连续不跳档。
Url 用反斜杠、相对语料根；文件夹型节点没有 Url。
"""

from __future__ import annotations

import re
from pathlib import Path

_FIELD = re.compile(r"TitleList\.(\w+)\.(\d+)=(.*)")


def _decode(data: bytes) -> str:
    # Windows 上 .wcp 一般是 UTF-16LE；个别旧的可能是本地编码
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return data.decode("utf-16", "replace")
    try:
        text = data.decode("utf-16-le")
        if "[TOPICS]" in text:
            return text
    except UnicodeDecodeError:
        pass
    for enc in ("gb18030", "utf-8"):
        try:
            text = data.decode(enc)
            if "[TOPICS]" in text:
                return text
        except UnicodeDecodeError:
            continue
    return data.decode("gb18030", "replace")


def parse_wcp(path: str | Path) -> dict:
    text = _decode(Path(path).read_bytes())
    titles: dict[int, str] = {}
    levels: dict[int, str] = {}
    urls: dict[int, str] = {}
    target = {"Title": titles, "Level": levels, "Url": urls}
    for m in _FIELD.finditer(text):
        bucket = target.get(m.group(1))
        if bucket is not None:
            bucket[int(m.group(2))] = m.group(3).strip()

    if not titles:
        return {"title": "", "nodes": [], "entries": 0}

    n = max(titles) + 1
    roots: list[dict] = []
    stack: list[tuple[int, dict]] = []
    for i in range(n):
        if i not in titles:
            continue
        node = {"t": titles[i], "u": (urls.get(i) or "").replace("\\", "/") or None, "c": []}
        lvl = int(levels.get(i) or 0)
        while stack and stack[-1][0] >= lvl:
            stack.pop()
        (stack[-1][1]["c"] if stack else roots).append(node)
        stack.append((lvl, node))

    head = re.search(r"^Title=(.*)$", text, re.M)
    return {
        "title": head.group(1).strip() if head else "",
        "nodes": roots,
        "entries": n,
    }


def walk(nodes):
    for node in nodes:
        yield node
        yield from walk(node["c"])


def stats(toc: dict) -> dict:
    nodes = list(walk(toc["nodes"]))
    internal = [n for n in nodes if n.get("u")]
    depth = 0

    def maxdepth(ns, d=1):
        nonlocal depth
        for n in ns:
            depth = max(depth, d)
            maxdepth(n["c"], d + 1)

    maxdepth(toc["nodes"])
    return {
        "entries": len(nodes),
        "roots": len(toc["nodes"]),
        "with_url": len(internal),
        "folders": len(nodes) - len(internal),
        "depth": depth,
    }


def prune(nodes: list[dict], covered: set[str]) -> list[dict]:
    """只保留"子树里还有未覆盖页面"的节点；已覆盖的链接降级为纯文件夹。"""
    out = []
    for n in nodes:
        kids = prune(n["c"], covered)
        url = n.get("u")
        keep_url = bool(url) and url.split("#")[0] not in covered
        if keep_url or kids:
            out.append({"t": n["t"], "u": url if keep_url else None, "c": kids})
    return out


def _segments(node: dict) -> str | None:
    """子树里出现最多的首段目录名。

    不能用"任意一个"：某个顶层节点下面可能挂着别的书的链接（比如速查节点里
    链到玩家手册），按"任意"认领会把不相干的书归错。
    """
    import collections

    c = collections.Counter()
    for n in walk([node]):
        u = n.get("u")
        if u:
            c[u.split("/")[0]] += 1
    return c.most_common(1)[0][0] if c else None


def merge(main: dict, others: list[dict], taken: set[str]) -> dict:
    """把子书目录接到主目录对应的书节点下面。

    子书目录（艾伯伦.wcp 之类）本身不带书名，只能按路径首段认领；
    认领不到的书节点挂到顶层"补遗"。
    """
    by_book: dict[str, dict] = {}
    for root in main["nodes"]:
        seg = _segments(root)
        if seg:
            by_book.setdefault(seg, root)

    groups: list[tuple[dict, list[dict]]] = []
    orphans: list[dict] = []
    for extra in others:
        for root in prune(extra["nodes"], taken):
            seg = _segments(root)
            target = by_book.get(seg) if seg else None
            if target is None:
                orphans.append(root)
                continue
            for owner, acc in groups:
                if owner is target:
                    acc.append(root)
                    break
            else:
                groups.append((target, [root]))

    for owner, roots in groups:
        owner["c"].append({"t": "补遗", "u": None, "c": roots})
    if orphans:
        main["nodes"].append({"t": "补遗（未归类）", "u": None, "c": orphans})
    return main


def leftovers(pages: set[str], titles: dict[str, str]) -> dict:
    """合并后仍无处安放的页面，按书分组挂到顶层，保证没有页面失去入口。"""
    import collections

    by_book = collections.defaultdict(list)
    for p in sorted(pages):
        by_book[p.split("/")[0]].append(p)
    return {
        "t": "未收录于目录",
        "u": None,
        "c": [
            {"t": book, "u": None,
             "c": [{"t": titles.get(p) or p.split("/")[-1], "u": p, "c": []} for p in ps]}
            for book, ps in by_book.items()
        ],
    }


def drop_dead_links(nodes: list[dict], pages: set[str]) -> tuple[list[dict], int]:
    """子书目录里有指向已删除页面的条目：去掉链接保留标题，没子节点的整条丢弃。"""
    out: list[dict] = []
    dead = 0
    for n in nodes:
        kids, sub = drop_dead_links(n["c"], pages)
        dead += sub
        url = n.get("u")
        if url and url.split("#")[0] not in pages:
            url = None
            dead += 1
            if not kids:
                continue
        out.append({"t": n["t"], "u": url, "c": kids})
    return out, dead

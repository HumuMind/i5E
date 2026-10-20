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

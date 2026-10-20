"""把内容库打成 App 可直接读的单文件 SQLite。

设计见 Docs/decisions/0007-storage.md：

- 一页一行，block 结构 zlib 压缩后存 blob；
- FTS5 只做**候选召回**，用单字 + 双字预分词、detail=none、contentless；
- 查询侧拿到候选页后做子串校验，再按命中次数排序。

detail=none 丢掉位置信息，索引比 trigram 小一半多，代价是不能用短语查询——
而我们本来就要做子串校验，短语能力用不上。
"""

from __future__ import annotations

import json
import sqlite3
import zlib
from pathlib import Path

FORMAT_VERSION = 1


def tokens(text: str) -> str:
    """单字 + 双字。中文两字词占多数，三字以上的词由双字 AND 覆盖。"""
    out: list[str] = []
    for seg in text.split("\n"):
        seg = seg.strip()
        if not seg:
            continue
        low = seg.lower()
        out.extend(low)
        out.extend(low[i:i + 2] for i in range(len(low) - 1))
    return " ".join(out)


def _block_text(b: dict) -> str:
    if b["type"] in ("h", "p", "dt", "dd"):
        return "".join(r.get("t", "") for r in b["runs"])
    if b["type"] == "pre":
        return b["text"]
    return ""


def page_text(blocks: list[dict]) -> str:
    """按文档顺序拼出整页可搜索文本。"""
    parts: list[str] = []

    def walk(bs):
        for b in bs:
            t = b["type"]
            if t in ("h", "p", "dt", "dd", "pre"):
                parts.append(_block_text(b))
            elif t in ("div", "quote"):
                walk(b["blocks"])
            elif t == "list":
                for it in b["items"]:
                    parts.append("".join(r.get("t", "") for r in it["runs"]))
                    walk(it["blocks"])
            elif t == "table":
                for row in b["rows"]:
                    for c in row["cells"]:
                        walk(c["blocks"])

    walk(blocks)
    return "\n".join(p for p in parts if p.strip())


def build(records: list[dict], toc: dict, info: dict, out_path: Path) -> dict:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    con = sqlite3.connect(out_path)
    con.execute("PRAGMA journal_mode=OFF")
    con.execute("PRAGMA synchronous=OFF")
    con.execute("PRAGMA page_size=8192")
    con.execute("CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    con.execute(
        "CREATE TABLE pages(id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,"
        " title TEXT, style TEXT, css TEXT, blocks BLOB NOT NULL)"
    )
    con.execute(
        "CREATE VIRTUAL TABLE search USING fts5(body, content='', detail=none,"
        " tokenize='unicode61')"
    )

    pages, fts = [], []
    for i, r in enumerate(records, 1):
        blob = zlib.compress(
            json.dumps(r["blocks"], ensure_ascii=False, separators=(",", ":")).encode(), 9)
        text = page_text(r["blocks"])
        pages.append((i, r["path"], r.get("title") or "",
                      json.dumps(r.get("style") or {}, ensure_ascii=False),
                      json.dumps(r.get("css") or [], ensure_ascii=False), blob))
        fts.append((i, tokens(text)))

    con.executemany(
        "INSERT INTO pages(id,path,title,style,css,blocks) VALUES(?,?,?,?,?,?)", pages)
    con.executemany("INSERT INTO search(rowid, body) VALUES(?,?)", fts)
    con.execute("INSERT INTO search(search) VALUES('optimize')")

    meta = {
        "format": FORMAT_VERSION,
        "pages": len(records),
        "toc": toc,
        "build": info,
        "tokenizer": "unigram+bigram/detail=none",
    }
    con.executemany("INSERT INTO meta(key,value) VALUES(?,?)",
                    [(k, json.dumps(v, ensure_ascii=False)) for k, v in meta.items()])
    con.commit()
    con.execute("VACUUM")
    con.commit()
    size = out_path.stat().st_size
    con.close()
    return {"bytes": size, "pages": len(records),
            "indexed_chars": sum(len(t) for _, t in fts)}


def open_db(path: Path) -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    return con


def search(con: sqlite3.Connection, query: str, limit: int = 200) -> list[dict]:
    """候选召回 + 子串校验 + 按命中次数排序。客户端要用同一套逻辑。"""
    q = query.strip().lower()
    if not q:
        return []
    if len(q) == 1:
        match = f'"{q}"'
    else:
        match = " AND ".join(f'"{q[i:i + 2]}"' for i in range(len(q) - 1))

    ids = [row[0] for row in con.execute("SELECT rowid FROM search WHERE search MATCH ?", (match,))]
    found = []
    # 逐个候选校验，够 limit 条就停：宽泛查询（如"的"）不必把三千个候选全解一遍
    for pid in ids:
        row = con.execute("SELECT path,title,blocks FROM pages WHERE id=?", (pid,)).fetchone()
        if not row:
            continue
        text = page_text(json.loads(zlib.decompress(row[2]))).lower()
        n = text.count(q)
        if n:
            found.append({"id": pid, "path": row[0], "title": row[1], "hits": n})
            if len(found) >= limit:
                break
    return found


def verify(con: sqlite3.Connection, queries: list[str], records: list[dict]) -> dict:
    """拿内容库本身当标准答案，逐查询比对召回是否完全一致。"""
    truth = {r["path"]: page_text(r["blocks"]).lower() for r in records}
    bad = []
    for q in queries:
        ql = q.lower()
        want = {p for p, t in truth.items() if ql in t}
        got = {m["path"] for m in search(con, q, limit=10 ** 6)}
        if want != got:
            bad.append({
                "query": q,
                "missing": len(want - got),
                "extra": len(got - want),
                "example": sorted(want - got)[:2] + sorted(got - want)[:2],
            })
    return {"queries": len(queries), "mismatch": len(bad), "examples": bad[:5], "pass": not bad}

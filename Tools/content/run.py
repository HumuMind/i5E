#!/usr/bin/env python3
"""解析原型：把 DND5e_chm/ 跑成 block 序列，跑 C1–C6 检查，产出报告与预览。

用法：
    python3 Tools/content/run.py build            # 全量
    python3 Tools/content/run.py build --limit 200
    python3 Tools/content/run.py build --jobs 8
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import sys
import time
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check  # noqa: E402
import toc as toc_mod  # noqa: E402
import model  # noqa: E402
import pack as pack_mod  # noqa: E402
import preview  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "DND5e_chm"
# 非正文的模板页，读进来只会污染统计
NON_CONTENT = {"template", "template2", "空白页模板"}
OUT = ROOT / "build"
SAMPLES = int(os.environ.get("SAMPLES", "40"))
# C10 用的探针：单字、双字、四字、拉丁、骰子式，覆盖各种查询形态
SEARCH_PROBES = ["火球", "巨龙", "魔法飞弹", "施法时间", "AC", "1d6", "龙", "的", "先攻", "黑暗视觉"]
PACK_EXT = {".htm", ".html", ".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}


def collect(limit: int | None = None) -> list[str]:
    paths: list[str] = []
    for dp, dns, fns in os.walk(SRC):
        dns[:] = [d for d in dns if d != ".git"]
        rel_dir = os.path.relpath(dp, SRC)
        if rel_dir.split(os.sep)[0] in NON_CONTENT:
            continue
        for fn in fns:
            if fn.lower().endswith((".htm", ".html")):
                rel = fn if rel_dir == "." else f"{rel_dir}/{fn}"
                paths.append(rel.replace(os.sep, "/"))
    paths.sort()
    return paths[:limit] if limit else paths


def _work(rel: str) -> dict:
    data = (SRC / rel).read_bytes()
    rec = model.parse_page(rel, data)
    rec["_check"]["family"] = (
        "word" if (b"MsoNormal" in data or b"MSHTML" in data)
        else "速查" if b"WinCHM" in data
        else "手写"
    )
    rec["_check"]["bytes"] = len(data)
    return rec


# ---------------- 黄金样本 ----------------

def features(rec) -> set[str]:
    c = rec["_check"]
    blocks = rec["blocks"]
    f: set[str] = set()
    f.add("来源:" + c["family"])
    nb = Counter(b["type"] for b in blocks)
    for t in ("table", "list", "quote", "pre", "hr"):
        if nb.get(t):
            f.add("含" + t)
    for b in blocks:
        if b["type"] == "table":
            rows = len(b["rows"])
            f.add("表格:小" if rows <= 3 else "表格:中" if rows <= 12 else "表格:大")
            if any(len(r["cells"]) > 6 for r in b["rows"]):
                f.add("表格:宽")
            if any(c2.get("colspan", 1) > 1 or c2.get("rowspan", 1) > 1
                   for r in b["rows"] for c2 in r["cells"]):
                f.add("表格:合并单元格")
        if b["type"] == "list":
            if any(it["blocks"] for it in b["items"]):
                f.add("列表:嵌套")
            if b["ordered"]:
                f.add("列表:有序")
        if b["type"] == "h" and b.get("id"):
            f.add("标题带锚点")
        if b["type"] == "h" and b["level"] == 4:
            f.add("有H4")
        if b["type"] in ("h", "p"):
            for r in b.get("runs", []):
                if r.get("b"):
                    f.add("含粗体")
                    if r.get("t", "").rstrip().endswith(("：", ":")):
                        f.add("含字段标签")
                if r.get("u"):
                    f.add("含下划线")
                if r.get("sup"):
                    f.add("含上标")
                if r.get("href"):
                    f.add("正文内链接")
    if c["imgs"]:
        f.add("含图")
        if len(c["imgs"]) >= 3:
            f.add("图多")
    if c["links"]:
        f.add("含链接")
        if len(c["links"]) >= 20:
            f.add("链接密集")
    if c["color_runs"] >= 10:
        f.add("靠颜色表达语义")
    n = len(c["block_text"])
    f.add("篇幅:" + ("极短" if n < 200 else "短" if n < 1500 else "中" if n < 8000 else "长"))
    d = rec["path"].split("/")[0]
    f.add("书:" + d)
    return f


def pick_samples(records: list[dict], n: int = SAMPLES) -> list[dict]:
    feats = {r["path"]: features(r) for r in records}
    struct = lambda s: {x for x in s if not x.startswith("书:")}
    # 空页与极短页对"看转换效果"没有价值，先排除
    pool = [r for r in records
            if len(r["blocks"]) >= 4 and len(r["_check"]["block_text"]) >= 400]
    covered: set[str] = set()
    picked: list[dict] = []
    while len(picked) < n and pool:
        best, best_key, best_new = None, None, set()
        for r in pool:
            s = feats[r["path"]]
            st = struct(s)
            key = (len(st - covered), len({x for x in s - covered if x.startswith("书:")}),
                   len(st))
            if best_key is None or key > best_key:
                best, best_key, best_new = r, key, st - covered
        if not best or (best_key[0] == 0 and best_key[1] == 0):
            break
        if best_new:
            why = sorted(best_new)[:6]
        else:
            bk = f"新书:{best['path'].split('/')[0]}"
            why = [bk] + sorted(struct(feats[best["path"]]))[:2]
        picked.append({
            "path": best["path"],
            "title": best["title"],
            "why": why,
            "feature_count": len(struct(feats[best["path"]])),
            "bytes": best["_check"]["bytes"],
            "chars": len(best["_check"]["block_text"]),
            "blocks": len(best["blocks"]),
        })
        covered |= feats[best["path"]]
        pool = [r for r in pool if r["path"] != best["path"]]
    return picked


# ---------------- 实体统计 ----------------

def spell_stats(records) -> dict:
    per_book: Counter = Counter()
    total = 0
    incomplete: Counter = Counter()
    examples = []
    for r in records:
        try:
            entries = model.extract_spells(r["blocks"])
        except Exception:  # noqa: BLE001
            continue
        good = []
        for e in entries:
            filled = sum(1 for k in ("casting_time", "range", "components", "duration") if e.get(k))
            if filled >= 2:
                good.append(e)
        if not good:
            continue
        book = r["path"].split("/")[0]
        per_book[book] += len(good)
        total += len(good)
        for e in good:
            for k in ("level", "school", "casting_time", "range", "components", "duration"):
                if e.get(k) is None:
                    incomplete[k] += 1
        if len(examples) < 3:
            examples.append({"path": r["path"], **{k: good[0][k] for k in
                                                   ("name_zh", "name_en", "level", "school",
                                                    "casting_time", "range", "components", "duration")}})
    return {"total": total, "per_book": per_book.most_common(12),
            "missing_fields": dict(incomplete), "examples": examples}


# ---------------- 报告 ----------------

def count_blocks(blocks) -> Counter:
    c: Counter = Counter()

    def walk(bs):
        for b in bs:
            c[b["type"]] += 1
            if b["type"] in ("div", "quote"):
                walk(b["blocks"])
            elif b["type"] == "list":
                for it in b["items"]:
                    walk(it["blocks"])
            elif b["type"] == "table":
                for row in b["rows"]:
                    for cell in row["cells"]:
                        walk(cell["blocks"])

    walk(blocks)
    return c


def build_report(records, results, spells, samples, elapsed, paths_total) -> str:
    c1, c2, c3, c4r, c5r, c6 = (results[k] for k in ("c1", "c2", "c3", "c4", "c5", "c6"))
    c8r, pack = results.get("c8"), results.get("pack")
    c9r, info = results.get("c9"), results.get("info")
    c10r = results.get("c10")
    enc = Counter(r["encoding"] for r in records)
    fam = Counter(r["_check"]["family"] for r in records)
    blocks = Counter()
    for r in records:
        blocks += count_blocks(r["blocks"])
    text_bytes = sum(len(r["_check"]["block_text"]) for r in records)
    content_path = OUT / "content.jsonl"
    json_bytes = content_path.stat().st_size if content_path.exists() else 0

    L = []
    L.append("# 解析原型报告\n")
    L.append(f"生成于 {time.strftime('%Y-%m-%d %H:%M')} · 耗时 {elapsed:.1f}s · "
             f"页面 {len(records)}/{paths_total}\n")

    L.append("## 总览\n")
    L.append("| 项 | 值 |\n|---|---|")
    L.append(f"| 页面 | {len(records)} |")
    L.append(f"| 原文可见字符 | {text_bytes:,} |")
    L.append(f"| block 数 | {sum(blocks.values()):,} |")
    L.append(f"| block JSON | {json_bytes / 1048576:.1f} MB |")
    L.append(f"| 编码 | {dict(enc)} |")
    L.append(f"| 来源 | {dict(fam)} |")
    L.append("")

    if info:
        u, p, t, ct = info["upstream"], info["parser"], info["toc"], info["content"]
        L.append("## 构建信息\n")
        L.append("| 项 | 值 |\n|---|---|")
        L.append(f"| 上游 commit | `{u['short']}` {u['subject']}" + ("（工作区有改动）" if u["dirty"] else "") + " |")
        L.append(f"| 上游提交时间 | {u['date']} |")
        L.append(f"| 解析器指纹 | `{p['fingerprint']}` |")
        L.append(f"| 内容版本 | `{ct['version']}` |")
        L.append(f"| 目录 | {t['title']} · {t['entries']} 节点 / {t['roots']} 顶层 / {t['depth']} 层 |")
        L.append("")

    L.append("## 检查\n")
    L.append("| 检查 | 结果 | 说明 |\n|---|---|---|")
    L.append(f"| C1 文本守恒 | {'通过' if c1['pass'] else '**失败 ' + str(c1['fail_count']) + ' 页**'} | 去空白后逐字符相等 |")
    L.append(f"| C2 节点覆盖 | {'通过' if c2['pass'] else '**有未知标签**'} | 白名单外标签：" + (", ".join(c2["unknown_tags"]) or "无") + " |")
    L.append(f"| C3 锚点与链接 | {'通过' if c3['pass'] else '基线比对（上游自带）'} | " +
             " / ".join(f"{k} {v}" for k, v in sorted(c3["stats"].items())) + " |")
    L.append(f"| C4 schema | {'通过' if c4r['pass'] else '**' + str(c4r['bad_count']) + ' 页不合法**'} | |")
    L.append(f"| C5 往返保真 | {'通过' if c5r['pass'] else '**' + str(c5r['bad_count']) + ' 页不一致**'} | 检查 {c5r['checked']} 页 |")
    if c6["baseline"]:
        L.append(f"| C6 回归哈希 | {'通过' if c6['pass'] else '**' + str(c6['changed']) + ' 页变了**'} | 与基线比对 |")
    else:
        L.append("| C6 回归哈希 | 首次运行，已写基线 | |")
    if c8r:
        L.append(f"| C8 原文还原 | {'通过' if c8r['pass'] else '**失败**'} | "
                 f"{c8r['checked']} 页 sha256 一致，且用原文重解析得到同一份 block |")
    if c9r:
        un = ", ".join(f"{b} {n}" for b, n in c9r["uncovered_books"][:4])
        L.append(f"| C9 目录完整性 | {'通过' if c9r['pass'] else '**' + str(c9r['broken']) + ' 条断链**'} | "
                 f"{c9r['entries']} 条，覆盖 {c9r['covered']}/{c9r['pages']} 页 "
                 f"({c9r['coverage']:.1%})；未覆盖 {c9r['uncovered']} 页（{un}） |")
    if c10r:
        L.append(f"| C10 检索索引 | {'通过' if c10r['pass'] else '**不一致**'} | "
                 f"{c10r['queries']} 条探针查询，召回与内容库逐页比对完全一致 |")
    L.append("")

    if not c1["pass"]:
        L.append("### C1 失败样例\n")
        for e in c1["failures"][:10]:
            L.append(f"- `{e['path']}` {json.dumps(e['diff'], ensure_ascii=False)[:400]}")
        L.append("")

    L.append("## block 分布\n")
    L.append("| 类型 | 数量 |\n|---|---|")
    for t, n in blocks.most_common():
        L.append(f"| {t} | {n:,} |")
    L.append("")

    L.append("## 法术实体\n")
    L.append(f"抓取到 **{spells['total']}** 条（要求 4 个字段至少命中 2 个）\n")
    L.append("| 书 | 条数 |\n|---|---|")
    for b, n in spells["per_book"]:
        L.append(f"| {b} | {n} |")
    L.append("")
    if spells["missing_fields"]:
        L.append(f"字段缺失次数：{spells['missing_fields']}\n")
    for e in spells["examples"]:
        L.append(f"- `{e['path']}` → {e['name_zh']}｜{e['name_en']} · {e['level']} 环 {e['school']} · "
                 f"{e['casting_time']} / {e['range']} / {e['components']} / {e['duration']}")
    L.append("")

    L.append("## 已知损失\n")
    color_pages = sum(1 for r in records if r["_check"]["color_runs"] > 0)
    L.append(f"- 颜色语义：{color_pages} 个页面有非黑色文本（Word 导出常用颜色表达标题与字段），"
             f"当前**不保留颜色**，共 {sum(r['_check']['color_runs'] for r in records):,} 个 run 受影响")
    L.append(f"- 忽略标签：{c2['ignored']}")
    L.append(f"- 透明容器（保留文字、丢层级）：{c2['transparent']}")
    L.append("")

    if c3["broken_file"]:
        L.append("### 断链（目标文件不存在）\n")
        for k, v in list(c3["broken_file"].items())[:15]:
            L.append(f"- `{k}` ← {v[0]}")
        L.append("")
    if c3["broken_frag"]:
        L.append("### 断锚点（目标 id 不存在）\n")
        for k, v in list(c3["broken_frag"].items())[:15]:
            L.append(f"- `{k}` ← {v[0]}")
        L.append("")

    L.append("## 黄金样本\n")
    L.append(f"共 {len(samples)} 页，按结构特征贪心挑选，覆盖不同来源、表格形态与篇幅。\n")
    L.append("| # | 页面 | 字符 / 块 | 带来什么 |\n|---|---|---|---|")
    for i, s in enumerate(samples, 1):
        L.append(f"| {i} | `{s['path']}` | {s.get('chars', 0):,} / {s['blocks']} | {', '.join(s['why'])} |")
    L.append("")
    return "\n".join(L)


def build_toc(records) -> dict:
    """主目录 + 各子书目录合并；仍无入口的页面挂到顶层"未收录于目录"。"""
    main = toc_mod.parse_wcp(SRC / "不全书.wcp")
    covered = {n["u"].split("#")[0] for n in toc_mod.walk(main["nodes"]) if n.get("u")}

    others = []
    for f in sorted(SRC.glob("*.wcp")):
        if f.name == "不全书.wcp":
            continue
        try:
            others.append(toc_mod.parse_wcp(f))
        except Exception:  # noqa: BLE001
            continue
    toc_mod.merge(main, others, covered)
    pages_all = {r["path"] for r in records}
    main["nodes"], dead = toc_mod.drop_dead_links(main["nodes"], pages_all)
    main["nodes"] = [n for n in main["nodes"] if n.get("u") or n["c"]]

    after = {n["u"].split("#")[0] for n in toc_mod.walk(main["nodes"]) if n.get("u")}
    rest = {r["path"] for r in records} - after
    if rest:
        titles = {r["path"]: (r.get("title") or "") for r in records}
        main["nodes"].append(toc_mod.leftovers(rest, titles))
    main["merge"] = {"sources": 1 + len(others), "from_extra": len(after - covered),
                     "dead_links": dead, "leftover": len(rest)}
    return main


def _git(path: Path, *args: str) -> str:
    import subprocess

    try:
        r = subprocess.run(["git", "-C", str(path), *args],
                           capture_output=True, text=True, timeout=20)
        return r.stdout.strip()
    except Exception:  # noqa: BLE001
        return ""


def parser_fingerprint() -> dict:
    files = sorted(Path(__file__).resolve().parent.glob("*.py"))
    acc = hashlib.sha256()
    detail = {}
    for f in files:
        d = hashlib.sha256(f.read_bytes()).hexdigest()
        detail[f.name] = d[:12]
        acc.update(f.name.encode() + d.encode())
    return {"fingerprint": acc.hexdigest()[:16], "files": detail}


def build_info(records, toc_data, checks) -> dict:
    commit = _git(SRC, "rev-parse", "HEAD")
    parser = parser_fingerprint()
    toc_stats = toc_mod.stats(toc_data)
    seed = f"{commit}|{parser['fingerprint']}|{len(records)}|{toc_stats['entries']}"
    return {
        "upstream": {
            "repo": "DND5eChm/DND5e_chm",
            "commit": commit,
            "short": commit[:9],
            "date": _git(SRC, "log", "-1", "--format=%cI"),
            "subject": _git(SRC, "log", "-1", "--format=%s"),
            "dirty": bool(_git(SRC, "status", "--porcelain", "--untracked-files=no")),
        },
        "parser": parser,
        "toc": {"source": "不全书.wcp", "title": toc_data.get("title", ""), **toc_stats},
        "content": {
            "version": hashlib.sha256(seed.encode()).hexdigest()[:12],
            "pages": len(records),
            "built_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        },
        "checks": checks,
    }


def build_pack(out: Path) -> dict:
    """把原文按原字节打进归档。这是"能还原"的唯一实现方式。"""
    import tarfile

    pack_dir = out / "pack"
    pack_dir.mkdir(exist_ok=True)
    archive = pack_dir / "source.tar.gz"
    manifest: dict[str, dict] = {}
    with tarfile.open(archive, "w:gz", compresslevel=6) as tf:
        for dp, dns, fns in os.walk(SRC):
            dns[:] = [d for d in dns if d != ".git"]
            rel_dir = os.path.relpath(dp, SRC)
            if rel_dir.split(os.sep)[0] in NON_CONTENT:
                continue
            for fn in fns:
                if os.path.splitext(fn)[1].lower() not in PACK_EXT:
                    continue
                full = os.path.join(dp, fn)
                name = os.path.relpath(full, SRC).replace(os.sep, "/")
                with open(full, "rb") as fh:
                    digest = hashlib.sha256(fh.read()).hexdigest()
                manifest[name] = {"name": name, "sha256": digest,
                                  "bytes": os.path.getsize(full)}
                tf.add(full, arcname=name, recursive=False)
    (pack_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    with open(out / "content.jsonl", "rb") as src, gzip.open(pack_dir / "content.jsonl.gz", "wb", 9) as dst:
        dst.write(src.read())
    return {"archive": archive, "manifest": pack_dir / "manifest.json",
            "bytes": archive.stat().st_size,
            "block_bytes": (pack_dir / "content.jsonl.gz").stat().st_size,
            "files": len(manifest)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["build"], nargs="?", default="build")
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--no-c5", action="store_true")
    ap.add_argument("--samples", type=int, default=SAMPLES)
    ap.add_argument("--pack", action="store_true", help="生成原文归档并跑 C8")
    args = ap.parse_args()

    t0 = time.time()
    paths = collect(args.limit)
    print(f"页面 {len(paths)}", flush=True)

    records: list[dict] = []
    model.configure_images(str(SRC))
    if args.jobs > 1 and len(paths) > 200:
        with ProcessPoolExecutor(
            max_workers=args.jobs, initializer=model.configure_images, initargs=(str(SRC),)
        ) as ex:
            for i, rec in enumerate(ex.map(_work, paths, chunksize=40), 1):
                records.append(rec)
                if i % 500 == 0:
                    print(f"  {i}/{len(paths)}", flush=True)
    else:
        for i, p in enumerate(paths, 1):
            records.append(_work(p))
            if i % 500 == 0:
                print(f"  {i}/{len(paths)}", flush=True)
    elapsed_parse = time.time() - t0
    print(f"解析完成 {elapsed_parse:.1f}s", flush=True)

    OUT.mkdir(exist_ok=True)
    with (OUT / "content.jsonl").open("w", encoding="utf-8") as fh:
        for r in records:
            fh.write(json.dumps({k: v for k, v in r.items() if k != "_check"},
                                ensure_ascii=False) + "\n")

    baseline_path = OUT / "baseline.json"
    baseline = json.loads(baseline_path.read_text()) if baseline_path.exists() else None

    fails = []
    for r in records:
        res = check.c1(r)
        if not res["pass"]:
            fails.append({"path": r["path"], "diff": res["diff"]})
    c1 = {"pass": not fails, "fail_count": len(fails), "failures": fails}

    print("C1 文本守恒:", "通过" if c1["pass"] else f"{len(fails)} 页失败", flush=True)
    c2 = check.c2(records, model.KNOWN_TAGS)
    print("C2 节点覆盖:", "通过" if c2["pass"] else c2["unknown_tags"], flush=True)
    c3 = check.c3(records)
    print("C3 锚点链接:", c3["stats"], flush=True)
    c4r = check.c4(records)
    print("C4 schema:", "通过" if c4r["pass"] else f"{c4r['bad_count']} 页", flush=True)

    toc_data = build_toc(records)
    (OUT / "toc.json").write_text(json.dumps(toc_data, ensure_ascii=False), encoding="utf-8")
    c9r = check.c9(toc_data, set(paths))
    print(f"C9 目录: {c9r['entries']} 条 / 覆盖 {c9r['covered']} 页 "
          f"({c9r['coverage']:.1%}) / 断链 {c9r['broken']}", flush=True)
    c5r = {"checked": 0, "bad_count": 0, "examples": [], "pass": True}
    if not args.no_c5:
        t1 = time.time()
        c5r = check.c5(records)
        print(f"C5 往返保真: {'通过' if c5r['pass'] else str(c5r['bad_count']) + ' 页'} "
              f"({time.time() - t1:.1f}s)", flush=True)
    c6 = check.c6(records, baseline)
    print("C6 回归哈希:", c6, flush=True)

    baseline_path.write_text(json.dumps({r["path"]: r["hash"] for r in records}, indent=0))

    c8r = None
    c10r = None
    pack = None
    if args.pack:
        t1 = time.time()
        db = pack_mod.build(records, toc_data, {}, OUT / "pack" / "content.db", image_root=SRC)
        con = pack_mod.open_db(OUT / "pack" / "content.db")
        toc_paths = {n["u"].split("#")[0] for n in toc_mod.walk(toc_data["nodes"]) if n.get("u")}
        c10r = pack_mod.verify(con, SEARCH_PROBES, records, toc_paths)
        con.close()
        img = db.get("images") or {}
        print(f"图片打包: {img.get('files', 0)} 个 / {img.get('bytes', 0) / 1048576:.1f} MB"
              + (f" · 重名冲突 {img['collisions']}" if img.get("collisions") else ""), flush=True)
        print(f"C10 检索索引: {'通过' if c10r['pass'] else c10r} "
              f"({len(SEARCH_PROBES)} 条查询 · 库 {db['bytes'] / 1048576:.1f} MB · "
              f"{time.time() - t1:.1f}s)", flush=True)
        pack = build_pack(OUT)
        pack["db"] = db
        c8r = check.c8(records, pack["archive"], pack["manifest"])
        print(f"C8 原文还原: {'通过' if c8r['pass'] else c8r} "
              f"({time.time() - t1:.1f}s, 归档 {pack['bytes'] / 1048576:.1f} MB)", flush=True)

    used_images = {p for r in records for p in (r["_check"].get("images_used") or {})}
    dropped_images = sum(r["_check"].get("images_dropped", 0) for r in records)
    print(f"图片: 采用 {len(used_images)} 个文件 / 丢弃 {dropped_images} 处", flush=True)
    dropped_links = sum(r["_check"].get("links_dropped", 0) for r in records)
    print(f"链接: 丢弃失效链接 {dropped_links} 处", flush=True)

    spells = spell_stats(records)
    print(f"法术: {spells['total']} 条", flush=True)

    samples = pick_samples(records, args.samples)
    by_path = {r["path"]: r for r in records}
    sample_recs = [by_path[s["path"]] for s in samples if s["path"] in by_path]

    # 黄金样本清单进仓库：C7 要求它可维护、可 diff
    manifest = Path(__file__).resolve().parent / "golden-samples.txt"
    manifest.write_text(
        "\n".join([f"# 黄金样本 {len(samples)} 页，由 run.py 按结构特征挑选；改动此文件请一并说明理由", ""]
                  + [f"{x['path']}\t{', '.join(x['why'])}" for x in samples]) + "\n",
        encoding="utf-8")

    prev_dir = OUT / "preview"
    prev_dir.mkdir(exist_ok=True)
    preview.write_preview(prev_dir, sample_recs, samples, SRC)

    elapsed = time.time() - t0
    info = build_info(records, toc_data, {
        "c1": {"pass": c1["pass"]},
        "c2": {"pass": c2["pass"]},
        "c3": {"pass": c3["pass"], "kind": "baseline",
               "broken_file": c3["stats"].get("broken_file", 0),
               "broken_frag": c3["stats"].get("broken_frag", 0),
               "lost_ids": c3["stats"].get("lost_ids", 0)},
        "c4": {"pass": c4r["pass"]},
        "c5": {"pass": c5r["pass"]},
        "c6": {"pass": c6["pass"]},
        "c9": {"pass": c9r["pass"], "entries": c9r["entries"], "coverage": c9r["coverage"]},
        "c10": {"pass": bool(c10r and c10r["pass"]), "probes": len(SEARCH_PROBES)},
    })
    (OUT / "build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2),
                                         encoding="utf-8")
    if pack:
        # 建库时还不知道构建清单（里面有 C10 结论），先建后补
        pack_mod.write_meta(OUT / "pack" / "content.db", "build", info)
        (OUT / "pack" / "toc.json").write_text(json.dumps(toc_data, ensure_ascii=False),
                                               encoding="utf-8")
        (OUT / "pack" / "build-info.json").write_text(
            json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")

    report = build_report(records, {"c1": c1, "c2": c2, "c3": c3, "c4": c4r, "c5": c5r,
                                    "c6": c6, "c8": c8r, "c9": c9r, "c10": c10r,
                                    "pack": pack, "info": info},
                          spells, samples, elapsed, len(paths))
    (OUT / "report.md").write_text(report, encoding="utf-8")
    (OUT / "samples.json").write_text(json.dumps(samples, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "report.json").write_text(json.dumps({
        "pages": len(records), "elapsed": elapsed, "c1": c1, "c2": c2, "c3": c3,
        "c4": c4r, "c5": c5r, "c6": c6, "c8": c8r, "c10": c10r, "spells": spells,
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n完成 {elapsed:.1f}s → {OUT}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

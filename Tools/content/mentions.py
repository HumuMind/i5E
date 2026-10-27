"""构建期自动链接：把正文里被提到的条目连到它自己的页面（见 0051）。

分两遍：

1. **建索引**：页面标题 + 带 `id` 的标题块 → 别名（`中文｜English` 拆成两个）。
   顺带统计每个别名出现在多少个页面里——出现在上百页的「生命值」「护甲等级」
   是数据块里的字段名，不是被提及的条目，不自动链。
2. **扫正文**：按别名做最长匹配，命中处把一个 run 拆成"前 / 链接 / 后"三段，
   给中间那段加 `href` 与 `m: 1`。

只在构建期跑：App 端已经会解析「路径#锚点」（0018），补 `href` 即可。
"""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

# 别名至少 3 个字符；两字的（倒地、麻痹）只认带 id 的标题块，
# 页面标题那种两字词（一环、人类、附录）太泛，不进索引。
MIN_ALIAS = 3
# 三档密度：别名出现在多少页以内算"精简 / 标准"，其余是"详细"（见 0051）
TIER_LIMITS = (50, 1000)
# 标题里的中英文分隔符
NAME_SEPARATORS = ("｜", "|")
# 别名按块跳过：表格里作者链接已足够，速查表再链会失控
SKIP_BLOCKS = {"table", "pre"}
LINK_BLOCKS = {"h", "p", "dt", "dd"}

_HAS_WORD = re.compile(r"[0-9A-Za-z\u3400-\u9fff]")


def _ascii_word(char: str) -> bool:
    """拉丁字母/数字/下划线：英文别名要按整词匹配，不能从词中间切。"""
    return char.isascii() and (char.isalnum() or char == "_")


def _whole_word(text: str, start: int, end: int, alias: str) -> bool:
    """英文开头/结尾的别名，前后不能接着拉丁字母。

    中文没有词边界，只能对拉丁部分设限：否则 "Limited Wish" 会把 "Wish"
    链到祈愿术，"Doomsday" 会把 "Doom" 链到末日术。
    """
    if _ascii_word(alias[0]) and start > 0 and _ascii_word(text[start - 1]):
        return False
    if _ascii_word(alias[-1]) and end < len(text) and _ascii_word(text[end]):
        return False
    return True


def _looks_like_name(text: str, start: int, end: int, alias: str) -> bool:
    """纯英文别名要有"中文名后面的英文名"的样子才认。

    中文正文里英文名几乎都跟在中文名后面（"火球术 Fireball"）。反过来，
    夹在英文短语里的词多半是另一回事：`Dawn Carlos` 里的 Dawn 是人名，
    `Doom Song` 里的 Doom 是曲名——这类不链。
    """
    if not alias.isascii():
        return True
    cursor = start - 1
    while cursor >= 0 and text[cursor] in " \u3000":
        cursor -= 1
    # 前面得是中文/全角标点，或者行首
    if cursor >= 0 and text[cursor].isascii():
        return False
    # 后面不该接着另一个英文单词（"Doom Song"、"Dawn Carlos"）
    if end + 1 < len(text) and text[end] in " \u3000" and text[end + 1].isascii() \
        and text[end + 1].isupper():
        return False
    return True


def _load_list(name: str) -> set[str]:
    """读名单文件：一行一个，`#` 之后是注释。"""
    path = Path(__file__).with_name(name)
    if not path.exists():
        return set()
    items: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        text = line.split("#", 1)[0].strip()
        if text:
            items.add(text)
    return items


_BRACKETED = re.compile(r"【[^】]*】|［[^］]*］|\([^)]*\)|（[^）]*）")
_CJK_LATIN = re.compile(r"(?<=[\u3400-\u9fff])(?=[A-Za-z])|(?<=[A-Za-z])(?=[\u3400-\u9fff])")


def _is_cjk(char: str) -> bool:
    return "\u3400" <= char <= "\u9fff"


def _split_names(text: str) -> set[str]:
    """把「中文 English」拆成两个名字。

    源页的写法很杂：`火球术｜Fireball`、`借机攻击 Opportunity Attacks`、
    `倒地 Prone【状态】`，还有中英文直接连着的。只按 `｜` 拆会漏掉一大半。
    """
    cleaned = _BRACKETED.sub(" ", text).strip()
    parts = {cleaned}
    for separator in NAME_SEPARATORS:
        if separator in cleaned:
            parts.update(piece.strip() for piece in cleaned.split(separator))
    for piece in list(parts):
        for sub in _CJK_LATIN.split(piece):
            parts.add(sub.strip())
    for piece in list(parts):
        # 中间有空格时，左边全中文、右边以拉丁字母开头才拆
        for index, char in enumerate(piece):
            if char != " ":
                continue
            left, right = piece[:index].strip(), piece[index + 1 :].strip()
            if not left or not right:
                continue
            if all(_is_cjk(c) for c in left) and right[0].isascii() and right[0].isalpha():
                parts.update((left, right))
            break
    return {p for p in parts if p}


def _aliases(label: str) -> list[str]:
    """标题 → 候选别名。"""
    if not label:
        return []
    return sorted(_split_names(label))


def _usable(alias: str, deny: set[str]) -> bool:
    return (
        len(alias) >= 2
        and alias not in deny
        and bool(_HAS_WORD.search(alias))
    )


def _tree(aliases) -> dict:
    root: dict = {}
    for alias in aliases:
        node = root
        for char in alias:
            node = node.setdefault(char, {})
        node[None] = alias
    return root


def _scan(tree: dict, text: str):
    """在 text 上做最长匹配，产出 (起, 止, 别名)。"""
    size = len(text)
    index = 0
    while index < size:
        node = tree
        cursor = index
        hit = None
        while cursor < size and text[cursor] in node:
            node = node[text[cursor]]
            cursor += 1
            if None in node:
                hit = (node[None], cursor)
        if not hit:
            index += 1
            continue
        alias, end = hit
        if not _whole_word(text, index, end, alias) or not _looks_like_name(
                text, index, end, alias
        ):
            index += 1
            continue
        yield index, end, alias
        index = end


def _book(path: str) -> str:
    return path.split("/")[0]


def _linkable_runs(block: dict):
    """按渲染顺序取出可加链接的 run 列表（跳过表格与 pre）。"""
    kind = block.get("type")
    if kind in SKIP_BLOCKS:
        return
    if kind in LINK_BLOCKS:
        yield block, "runs"
    elif kind == "list":
        for item in block.get("items", []):
            yield item, "runs"
            for child in item.get("blocks", []):
                yield from _linkable_runs(child)
    elif kind in ("div", "quote"):
        for child in block.get("blocks", []):
            yield from _linkable_runs(child)


class _Index:
    def __init__(self, records: list[dict], deny: set[str]) -> None:
        self.targets: dict[str, set[tuple[str, str]]] = {}
        for rec in records:
            path = rec["path"]
            for alias in _aliases(rec.get("title") or ""):
                if len(alias) >= MIN_ALIAS and _usable(alias, deny):
                    self.targets.setdefault(alias, set()).add((path, ""))
            for block in rec["blocks"]:
                if block.get("type") != "h" or not block.get("id"):
                    continue
                label = "".join(run.get("t") or "" for run in block.get("runs", []))
                # 标题块是具体条目（倒地 Prone、借机攻击 Opportunity Attacks），
                # 两字也收；它们比"一环""人类"这种页面标题精确得多
                for alias in _aliases(label):
                    if len(alias) >= 2 and _usable(alias, deny):
                        self.targets.setdefault(alias, set()).add((path, block["id"]))

    def frequency(self, records: list[dict]) -> Counter:
        """每个别名出现在多少个页面里（只数可加链接的正文）。"""
        tree = _tree(self.targets)
        pages: dict[str, set[str]] = {}
        for rec in records:
            seen: set[str] = set()
            for block in rec["blocks"]:
                for holder, key in _linkable_runs(block):
                    for run in holder.get(key, []):
                        for _, _, alias in _scan(tree, run.get("t") or ""):
                            seen.add(alias)
            pages[rec["path"]] = seen
        counter: Counter = Counter()
        for seen in pages.values():
            counter.update(seen)
        return counter

    def resolve(self, alias: str, path: str) -> tuple[str, str] | None:
        targets = self.targets[alias]
        if len(targets) == 1:
            return next(iter(targets))
        same_book = [t for t in targets if _book(t[0]) == _book(path)]
        candidates = same_book or list(targets)
        # 页面级目标优先于标题块：点过去先看整页，比落在一个小节里稳
        pages_only = [t for t in candidates if not t[1]]
        if len(pages_only) == 1:
            return pages_only[0]
        if len(candidates) == 1:
            return candidates[0]
        # 同名跨版本（玩家手册 2014 / 2024）：默认 2024
        current = [t for t in candidates if "2024" in t[0]]
        if len(current) == 1:
            return current[0]
        return None


def _tier(alias: str, frequency: Counter) -> int:
    """返回该别名最早出现在哪一档：1 精简 / 2 标准 / 3 详细。"""
    pages = frequency[alias]
    return 1 if pages <= TIER_LIMITS[0] else 2 if pages <= TIER_LIMITS[1] else 3


def apply(records: list[dict]) -> dict:
    """给 records 补自动链接，返回统计。原地修改 blocks。

    每条链接带 `m` = 详细程度（1…3），App 按用户选的档位筛。
    同一目标在一页里被提到几次就链几次——读者点哪一处都应该跳得过去。
    """
    deny = _load_list("mention-deny.txt")
    allow = _load_list("mention-allow.txt")

    index = _Index(records, deny)
    frequency = index.frequency(records)
    tiers = {
        alias: 1 if alias in allow else _tier(alias, frequency)
        for alias in index.targets
    }
    tree = _tree(tiers)

    stats = Counter()
    per_page: dict[str, int] = {}
    used_aliases: Counter = Counter()

    for rec in records:
        path = rec["path"]
        holders: dict[int, dict] = {}
        # (容器, 键) -> {run 下标: [候选]}
        pending: dict[tuple[int, str], dict[int, list[tuple]]] = {}
        order = 0
        for block in rec["blocks"]:
            for holder, key in _linkable_runs(block):
                holders[id(holder)] = holder
                for run_index, run in enumerate(holder.get(key) or []):
                    text = run.get("t") or ""
                    if run.get("href") or not text:
                        continue
                    for start, end, alias in _scan(tree, text):
                        stats["hits"] += 1
                        target = index.resolve(alias, path)
                        if target is None:
                            stats["ambiguous"] += 1
                            continue
                        if target[0] == path:
                            stats["self"] += 1
                            continue
                        order += 1
                        pending.setdefault((id(holder), key), {}).setdefault(
                            run_index, []
                        ).append((start, end, alias, target, order))

        # 按"容器 + 键"重建：同一个 run 列表只重建一次，否则拆 run 后下标会漂
        added = 0
        for (holder_id, key), grouped in pending.items():
            holder = holders[holder_id]
            runs = holder.get(key) or []
            rebuilt: list[dict] = []
            for run_index, run in enumerate(runs):
                chosen = sorted(grouped.get(run_index, []), key=lambda c: c[0])
                if not chosen:
                    rebuilt.append(run)
                    continue
                text = run["t"]
                cursor = 0
                last_end = -1
                for start, end, alias, target, _ in chosen:
                    if start < cursor:
                        continue
                    # 紧挨着上一条链接的（"倒地"+"状态"）不再链：一条连续下划线
                    # 指向两个不同的页面，点哪儿去哪页会让人莫名其妙
                    if start == last_end:
                        continue
                    if start > cursor:
                        rebuilt.append({**run, "t": text[cursor:start]})
                    href = target[0] + (("#" + target[1]) if target[1] else "")
                    piece = {**run, "t": text[start:end], "href": href, "m": tiers[alias]}
                    rebuilt.append(piece)
                    cursor = end
                    last_end = end
                    added += 1
                    stats["links"] += 1
                    stats[f"tier{tiers[alias]}"] += 1
                    used_aliases[alias] += 1
                if cursor < len(text):
                    rebuilt.append({**run, "t": text[cursor:]})
            holder[key] = rebuilt

        if added:
            per_page[path] = added

    stats["pages"] = len(per_page)
    stats["aliases"] = len(tiers)
    stats["top"] = used_aliases.most_common(10)
    return dict(stats)

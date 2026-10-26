from __future__ import annotations

import os
import posixpath
import re
from urllib.parse import unquote

from text_utils import _runs_text

# ---------------- 实体标注：法术 ----------------

CN_NUM = {"零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6,
          "七": 7, "八": 8, "九": 9, "十": 10}


FIELD_LABELS = ("施法时间", "施法距离", "法术成分", "持续时间")
FIELD_KEYS = {
    "施法时间": "casting_time", "施法距离": "range",
    "法术成分": "components", "持续时间": "duration",
}


def _fields(rest: str) -> dict:
    """按字段标签切分。最后一个字段（持续时间）之后紧接正文，以换行为界。"""
    pat = re.compile("(" + "|".join(re.escape(l) + "[：:]" for l in FIELD_LABELS) + ")")
    chunks = pat.split(rest)
    out: dict = {}
    for i in range(1, len(chunks), 2):
        label = chunks[i].rstrip("：:")
        val = chunks[i + 1] if i + 1 < len(chunks) else ""
        if label == "持续时间":
            val = val.split(SEP)[0]
        key = FIELD_KEYS.get(label)
        if key:
            out[key] = re.sub(r"\s+", " ", val).strip()
    return out


def extract_spells(blocks: list[dict]) -> list[dict]:
    """从 block 序列里抽法术条目。

    形态（2014 与 2024 同构）：<H4 id="En_Name">中文｜English</H4>
    紧跟一个 P，首段是 <EM>环阶 学派（职业）</EM>，其后是 <STRONG>字段：</STRONG>。
    """
    out: list[dict] = []
    i = 0
    n = len(blocks)
    while i < n:
        b = blocks[i]
        if b["type"] != "h" or b["level"] != 4 or not b.get("id"):
            i += 1
            continue
        raw = _runs_text(b["runs"]).strip()
        if "｜" not in raw:
            i += 1
            continue
        name_zh, _, name_en = raw.partition("｜")
        entry = {
            "id": b["id"],
            "name_zh": name_zh.strip(),
            "name_en": name_en.strip(),
            "level": None, "school": None, "ritual": False, "classes": [],
            "casting_time": None, "range": None, "components": None, "duration": None,
            "text": "",
        }
        body: list[dict] = []
        j = i + 1
        while j < n and not (blocks[j]["type"] == "h" and blocks[j]["level"] <= 4 and blocks[j].get("id")):
            body.append(blocks[j])
            j += 1

        if body and body[0]["type"] == "p":
            runs = body[0]["runs"]
            head = _runs_text(runs).split(SEP)[0]
            pos = 0
            if head:
                # 两版顺序不同：2014 是「一环 防护（…）」，2024 是「塑能 戏法（…）」，
                # 所以不按位置取值，按词形识别环阶。
                core, sep, tail = head.partition("（")
                if not sep:
                    core, sep, tail = head.partition("(")
                tail = tail.strip().rstrip("）)")
                for tok in (t for t in re.split(r"[\s　]+", core.strip()) if t):
                    if tok == "戏法" or re.fullmatch(r"[零一二三四五六七八九十]环", tok):
                        entry["level"] = 0 if tok == "戏法" else CN_NUM.get(tok[0])
                    elif entry["school"] is None:
                        entry["school"] = tok
                entry["ritual"] = "仪式" in tail
                entry["classes"] = [
                    c.strip() for c in re.split(r"[、,，；;]", tail.replace("仪式", ""))
                    if c.strip()
                ]
                rest = "".join(
                    r.get("t", "") for k, r in enumerate(runs) if k >= pos
                )
                entry.update(_fields(rest))
        entry["text"] = _runs_text(
            [r for bb in body for r in (bb.get("runs") or [])]
        ).strip()
        out.append(entry)
        i = j
    return out

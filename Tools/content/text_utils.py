from __future__ import annotations

import re

# 行分隔符：源页的 <BR> 转成它，与普通空白区分开
SEP = "\u2028"
WS = set("\t\n\r\f\v \u00a0\u3000\u200b\u200c\u200d\u2060\ufeff" + SEP)

def decode(data: bytes) -> tuple[str, str]:
    """按 BOM → UTF-8 → GB18030 的顺序解码。GB18030 是 GBK/GB2312 的超集。"""
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8", "replace"), "utf-8-bom"
    for enc in ("utf-8", "gb18030"):
        try:
            return data.decode(enc), enc
        except UnicodeDecodeError:
            continue
    return data.decode("gb18030", "replace"), "gb18030-replace"


_WS_RUN = re.compile(r"[\t\n\r\f\v \u00a0\u3000\u200b\u200c\u200d\u2060\ufeff]+")


def clean_text(s: str) -> str:
    """折叠源页里的普通空白。

    源页（尤其 Word 导出的）经常在句中插入真实换行，比如「不大于20 \n尺」，
    直接渲染会在中间断开。这里把普通空白折叠成单个空格；
    `\u2028` 是 `<BR>` 的显式换行，必须保留。
    """
    return SEP.join(_WS_RUN.sub(" ", part) for part in s.split(SEP))


def norm_text(s: str) -> str:
    return "".join(ch for ch in s if ch not in WS)


def _merge(runs: list[dict]) -> list[dict]:
    out: list[dict] = []
    for r in runs:
        if r.get("t") == "":
            continue
        # 样式必须逐项相等才能合并；只比键集合会把不同颜色的相邻段并成一段
        if out and "t" in r and "t" in out[-1]:
            if {k: v for k, v in out[-1].items() if k != "t"} == \
               {k: v for k, v in r.items() if k != "t"}:
                out[-1]["t"] += r["t"]
                continue
        out.append(r)
    return out


def _runs_text(runs: list[dict]) -> str:
    return "".join(r.get("t", "") for r in runs)

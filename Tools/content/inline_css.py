"""解析页面内联 <style> 里的标签级规则。

只做一件事：把 `h1 { color: #971869 }` 这类规则解析出来，
供标题渲染覆盖全局默认色。不做选择器组合、不做盒模型。
"""

from __future__ import annotations

import re

HEADING_TAGS = ("h1", "h2", "h3", "h4", "h5", "h6")

_STYLE_BLOCK = re.compile(r"<style[^>]*>(.*?)</style>", re.S | re.I)
_COMMENT = re.compile(r"/\*.*?\*/", re.S)
_RULE = re.compile(r"([^{}]+)\{([^}]*)\}")
_COLOR = re.compile(r"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")


def _normalize_color(value: str) -> str | None:
    value = value.strip().lower()
    if _COLOR.match(value):
        if len(value) == 4:  # #abc → #aabbcc
            return "#" + "".join(ch * 2 for ch in value[1:])
        return value
    named = {
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
        "blue": "#0000ff", "purple": "#800080", "gray": "#808080", "grey": "#808080",
        "maroon": "#800000", "navy": "#000080", "olive": "#808000", "teal": "#008080",
    }
    return named.get(value)


def heading_styles(html_text: str) -> dict[int, dict]:
    """返回 `{level: {"c": 颜色, "b": 1}}`，只保留内联样式里显式声明过的值。

    只匹配形如 `h1 { ... }` 的简单选择器；`div.stat-block h5` 这类交给
    App 侧的 ClassStyle 处理，避免两套规则打架。
    """
    found: dict[int, dict] = {}
    for block in _STYLE_BLOCK.findall(html_text):
        text = _COMMENT.sub("", block)
        for selector, body in _RULE.findall(text):
            # 选择器可能是列表（`h2,h3,U{...}`），把命中的标题标签都收进来
            names = [s.strip().lower() for s in selector.split(",")]
            levels = [int(name[1]) for name in names if name in HEADING_TAGS]
            if not levels:
                continue
            for level in levels:
                _apply_declarations(body, found, level)
    return found


def _apply_declarations(body: str, found: dict[int, dict], level: int) -> None:
    """把一条规则的声明合并进某个标题层级。"""
    for declaration in body.split(";"):
        if ":" not in declaration:
            continue
        prop, value = declaration.split(":", 1)
        prop = prop.strip().lower()
        value = value.strip()
        if prop == "color":
            color = _normalize_color(value)
            if color:
                found.setdefault(level, {})["c"] = color
        elif prop == "font-weight" and value.lower() in ("bold", "bolder", "700", "800", "900"):
            found.setdefault(level, {})["b"] = 1
        elif prop == "text-align":
            mapped = {"center": "c", "right": "r", "justify": "j", "left": "l"}.get(value.lower())
            if mapped and mapped != "l":
                found.setdefault(level, {})["al"] = mapped
        elif prop in ("border-bottom", "border") and "none" not in value.lower():
            # 标题下划线：源页大量使用，颜色可能写在值的任意位置
            color = next(
                (_normalize_color(token) for token in value.replace(",", " ").split()
                 if _normalize_color(token)), None)
            found.setdefault(level, {})["bd"] = color or "1"


def table_has_border(html_text: str) -> bool:
    """页面 CSS 里是否给 table 统一加了边框。"""
    for block in _STYLE_BLOCK.findall(html_text):
        text = _COMMENT.sub("", block)
        for selector, body in _RULE.findall(text):
            names = [s.strip().lower() for s in selector.split(",")]
            if "table" not in names:
                continue
            if "border" in body.lower() and "none" not in body.lower():
                return True
    return False

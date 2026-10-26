from __future__ import annotations

import os
import posixpath
import re
from urllib.parse import unquote

IMAGE_ROOT = None
TEMPLATE_PREFIXES = ("template/", "template2/", "空白页模板/")


def configure_images(root) -> None:
    """多进程 worker 的初始化钩子。"""
    global IMAGE_ROOT
    IMAGE_ROOT = root


def resolve_image(page_path: str, src: str) -> str | None:
    """把页面里的相对图片路径解析成语料内路径；解析不到返回 None。"""
    if not src or IMAGE_ROOT is None:
        return None
    cleaned = unquote(src).strip()
    if not cleaned or cleaned.lower().startswith(("http:", "https:", "file:", "data:")):
        return None
    candidates = (
        posixpath.normpath(posixpath.join(posixpath.dirname(page_path), cleaned)),
        posixpath.normpath(cleaned.lstrip("/")),
    )
    for candidate in candidates:
        if candidate.startswith(TEMPLATE_PREFIXES):
            continue
        if os.path.exists(os.path.join(IMAGE_ROOT, candidate)):
            return candidate
    return None


def resolve_link(page_path: str, href: str) -> str | None:
    """把链接解析成"语料内路径#锚点"。

    - 外部链接原样返回；
    - 本页锚点返回 "#锚点"；
    - 内部链接按"相对文件目录 → 相对语料根 → 扩展名互换 → 大小写"依次尝试；
    - 解析不到返回 None（调用方会去掉 href，文字保留）。
    """
    if not href:
        return None
    cleaned = unquote(href).strip().replace("\\", "/")
    if cleaned.lower().startswith(("http:", "https:", "mailto:")):
        return cleaned
    if cleaned.startswith("#"):
        return cleaned
    if IMAGE_ROOT is None:
        return None

    target, _, fragment = cleaned.partition("#")
    candidates = (
        posixpath.normpath(posixpath.join(posixpath.dirname(page_path), target)),
        posixpath.normpath(target.lstrip("/")),
    )
    for candidate in candidates:
        if not candidate.lower().endswith((".htm", ".html")):
            continue
        for probe in (
            candidate,
            candidate[:-5] + (".htm" if candidate.lower().endswith(".html") else ".html"),
        ):
            if os.path.exists(os.path.join(IMAGE_ROOT, probe)):
                return probe + (("#" + fragment) if fragment else "")
    return None

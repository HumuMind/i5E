#!/bin/sh
# 把构建好的内容库放进 App 的资源目录。
# 内容库不进仓库（32 MB 二进制），所以每次构建后需要跑一次。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/build/pack/content.db"
DST="$ROOT/i5E/Resources/content.db"

if [ ! -f "$SRC" ]; then
  echo "找不到 $SRC" >&2
  echo "先跑：python3 Tools/content/run.py build --pack" >&2
  exit 1
fi

mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"
echo "已放入 $DST ($(du -h "$DST" | cut -f1))"

IMG_SRC="$ROOT/build/pack/images"
IMG_DST="$ROOT/i5E/Resources/images"
if [ -d "$IMG_SRC" ]; then
  rm -rf "$IMG_DST"
  mkdir -p "$IMG_DST"
  cp "$IMG_SRC"/* "$IMG_DST"/
  echo "已放入 $IMG_DST ($(ls "$IMG_DST" | wc -l | tr -d ' ') 个文件, $(du -sh "$IMG_DST" | cut -f1))"
fi

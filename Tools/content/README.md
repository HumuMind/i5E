# 内容解析原型

把 `DND5e_chm/` 的 HTML 转成 block 序列，跑 C1–C10 检查，产出报告、预览和一份 App 可直接读的 SQLite。
对应决策：[0001 内容模型](../../Docs/decisions/0001-content-model.md)、
[0002 管线](../../Docs/decisions/0002-pipeline.md)、
[0003 转换验证](../../Docs/decisions/0003-translation-verification.md)、
[0007 存储与检索](../../Docs/decisions/0007-storage.md)。

现状：内容侧已经可用，但**没有增量构建**（每次全量重跑，12 秒；带 pack 约 36 秒），
也没有 iOS 端。构建清单里目前不写 `upstreamCommit` 以外的版本策略。

## 跑

```bash
python3 Tools/content/run.py build            # 全量，默认用 CPU 核数-1 并行
python3 Tools/content/run.py build --pack     # 另外生成原文归档、content.db，跑 C8 与 C10
python3 Tools/content/run.py build --jobs 1   # 单进程，方便看 traceback
python3 Tools/content/run.py build --limit 400 --no-c5
```

依赖：Python 3.10+、lxml。（bs4 用不到，上游 `Generator/` 才用。）

## 产出（`build/`，不进仓库）

| 文件 | 内容 |
|---|---|
| `content.jsonl` | 每页的 block 序列，一行一页 |
| `report.md` | 人读的报告：检查结果、block 分布、法术抽取、已知损失、黄金样本 |
| `report.json` | 同上，机器读 |
| `baseline.json` | C6 的回归基线，下次运行用来比对 |
| `toc.json` | 从 `不全书.wcp` 解出的目录树 |
| `build-info.json` | 构建清单：上游 commit、解析器指纹、内容版本 |
| `pack/source.tar.gz` | 原文归档，逐字节（--pack）|
| `pack/manifest.json` | 每个文件的 sha256（--pack）|
| `pack/content.jsonl.gz` | 阅读层压缩产物（--pack）|
| `pack/content.db` | **App 直读**：pages + FTS5 索引 + 目录（--pack）|
| `pack/images/` | 正文引用到、且确实存在的图片，拍平命名（--pack）|
| `samples.json` | 黄金样本及其入选理由 |
| `preview/index.html` | **先看这个**：左侧渲染结果，右侧 block 结构 |

预览里的图片指向本地原文，直接双击用浏览器打开即可。

## 模块

| 文件 | 职责 |
|---|---|
| `model.py` | 解码、HTML → block、法术实体抽取 |
| `render.py` | block → HTML，以及 C5 用的规范化视图 |
| `check.py` | C1–C10 |
| `preview.py` | 黄金样本预览页 |
| `toc.py` | 解析 `.wcp` 里的目录树，统计覆盖率 |
| `pack.py` | 打单文件 SQLite（pages / FTS5 / meta），含查询与 C10 校验 |
| `run.py` | 命令行、语料遍历、样本挑选、报告、构建清单 |

## 两条不变式

改解析器时先看这两条，它们比"看起来对不对"更容易判错：

1. **文本守恒（C1）**：原文可见文本去掉空白后，必须与 block 里拼出来的文本逐字符相等。
2. **往返幂等（C5）**：`parse(render(parse(x)))` 与 `parse(x)` 结构一致。

## 目前不做的

- 怪物、物品、规则条款的实体抽取（0001 定的第二批）。
- 颜色语义：Word 导出的页面用颜色表达标题与字段，当前丢弃，只在报告里计数。
- 图片打包、内容包、增量构建。

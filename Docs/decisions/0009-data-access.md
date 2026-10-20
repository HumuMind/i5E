# 0009 数据访问：GRDB，只读打开

状态：已定 · 2026-10-20

## 背景

I2。App 要读 `content.db`（32 MB，pages + FTS5 + meta）。三个具体问题会直接卡住第一天：FTS5 有没有、压缩格式对不对、校验逻辑怎么保证一致。

## 决定

1. **用 GRDB**（MIT，SPM 引入），不自己封 `sqlite3`。
2. **只读打开**：`SQLITE_OPEN_READONLY`，内容库随包分发，运行时不写。
3. **FTS5 运行时自检**：启动读 `PRAGMA compile_options`，不含 `ENABLE_FTS5` 就切 GRDB 的自定义 SQLite 构建。
4. **解压用 libz 的 `uncompress()`**，不用 `Compression` 框架。
5. **`page_text()` 在 Swift 复刻**，用 meta 里的正文哈希自检。

## 三个坑，写在这里省得再踩

**压缩格式不兼容。** `blocks` 是 Python `zlib.compress` 产出的 zlib 格式（2 字节头 + Adler-32 校验尾）。Apple `Compression` 框架的 `COMPRESSION_ZLIB` 要的是**裸 deflate**，直接喂会解压失败。libz 的 `uncompress()` 按 zlib 格式解，和 Python 完全对得上。

**校验逻辑必须双端一致。** 搜索是"FTS 召回候选 → 子串校验"两步，第二步依赖 `page_text()`（按文档顺序把 block 拼成正文）。Swift 复刻一份，两边算法不一致就会搜出错结果，而且很难发现。

对策：构建时把全库正文的合并哈希写进 `meta.text_sha256`；App 首次启动用 Swift 版重算一遍比对，不一致直接报错。这个自检比任何单元测试都直接。

**FTS5 不一定在系统库里。** 启动时查一次，别赌。

## 后果

- 多一个第三方依赖。GRDB 是 MIT，与 GPL-3.0 兼容。
- 内容库随包分发，意味着更新内容 = 更新 App（增量通道见 I19）。
- 构建侧要多产出一个 `text_sha256` 字段（已加进 `pack.py`）。

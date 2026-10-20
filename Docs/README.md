# 文档

这里放结论。聊天是草稿纸，这里才是事实来源。

## 讨论规则

1. **一次只解一个决策，带着选项来。** 不问"该怎么做"，问"A 和 B 的代价分别是……"。
2. **按阻塞关系排序，不按兴趣排序。** 先定卡住代码骨架的，再定随时能改的。
3. **每轮只有一个出口**：定了／明确"暂不定"并写下触发条件／拆成更小的问题。没有"回头再说"。

## 记录规则

- 一个决策一个文件：`decisions/NNNN-slug.md`，正文控制在一页。
- 三态流转：`提议` → `已定` → `被 00xx 取代`。**旧文件不删**，半年后还要能查到当初为什么否掉某个方案。
- 决策记录兼任会议纪要：被否掉的选项和理由写在"选项"栏，不另维护纪要。
- **24 小时规则**：聊天里达成的共识，一天内没落成文件，就等于没发生。

## 目录

| 路径 | 放什么 |
|---|---|
| `decisions/` | 架构与产品决策，编号递增 |
| `AppDesign/` | 产品与界面设计；[iOS 待讨论清单](AppDesign/ios-checklist.md) |
| `open-questions.md` | 未决问题，一行一条，写清"在等什么才解" |

## 排期

| # | 决策 | 状态 |
|---|---|---|
| D1 | 内容模型 | [0001](decisions/0001-content-model.md) · 已定 |
| D1b | 原文存档 | [0004](decisions/0004-source-archive.md) · 已定（两层内容包，C8 闭环） |
| D1c | 样式字段 | [0005](decisions/0005-style-fields.md) · 已定（含 class 与底色） |
| D2 | 解析发生在哪一层 | [0002](decisions/0002-pipeline.md) · 已定（构建期预生成） |
| D3 | 存储与检索 | [0007](decisions/0007-storage.md) · 已定（单库 SQLite，单字+双字索引） |
| D6 | 内容范围 | [0006](decisions/0006-scope.md) · 已定（全收，目录 100% 覆盖） |
| V1 | 转换验证 | [0003](decisions/0003-translation-verification.md) · 已定（C1–C10，全量通过） |
| I1 | 平台与框架 | [0008](decisions/0008-platform.md) · 已定（SwiftUI，iOS/macOS 26） |
| I2 | 数据访问 | [0009](decisions/0009-data-access.md) · 已定（GRDB，只读） |
| I3 | 工程结构 | [0010](decisions/0010-project-structure.md) · 已定（单 target + 本地包） |
| I4 | 阅读排版 | [0011](decisions/0011-typography.md) · 已定（720 版心 / 19pt / 表格自适应） |
| D4 | 追新机制 | 待排 |
| D5 | 许可与分发 | 待排（不阻塞写代码，但别拖到首次提审） |
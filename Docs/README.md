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
| I5 | 阅读交互 | [0012](decisions/0012-scrolling.md) · 已定（只滚动，不分页） |
| I6 | 目录首屏 | [0013](decisions/0013-toc-sections.md) · 已定（六个分组） |
| I7 | 搜索界面 | [0014](decisions/0014-search-ui.md) · 已定（按页 + 跳到命中） |
| I8 | 表格呈现 | [0015](decisions/0015-table-layout.md) · 已定（列宽按内容，不铺满） |
| I9 | 图片 | [0016](decisions/0016-images.md) · 已定（只处理包内真有的） |
| I10 | 深色模式 | [0017](decisions/0017-dark-mode.md) · 已定（跟随系统，对比度 4.5） |
| I11 | 交叉引用 | [0018](decisions/0018-cross-references.md) · 已定（压栈 + 锚点定位） |
| I12 | 书签与进度 | [0019](decisions/0019-progress-bookmarks.md) · 已定（字符偏移 + UserDefaults） |
| I13 | 速查页 | [0020](decisions/0020-reference-pages.md) · 已定（卡片 + 筛选，可切原版） |
| I14 | 双版本 | [0021](decisions/0021-editions.md) · 已定（章节路径 + 旧版徽标） |
| I15 | 实体页 | [0022](decisions/0022-no-entity-pages.md) · 不做（被速查与搜索覆盖） |
| I16 | 可访问性 | [0023](decisions/0023-accessibility.md) · 已定（三档字号 + VoiceOver） |
| I17 | 性能预算 | [0024](decisions/0024-performance.md) · 已定（五项预算 + 打点） |
| I18 | 分发与许可 | [0025](decisions/0025-license-distribution.md) · 已定（App Store；代码 MIT） |
| I19 | 内容更新 | [0026](decisions/0026-offline-updates.md) · 已定（随 App 发版，不联网） |
| I20 | 包体 | [0027](decisions/0027-bundle-size.md) · 已定（48 MB，预算 80 MB） |
| I21 | 测试策略 | [0028](decisions/0028-testing.md) · 已定（三层；UI 起步） |
| I22 | App 图标 | [0029](decisions/0029-app-icon.md) · 已定（书 + 5E，三套变体） |
| I23 | 标识与版本 | [0030](decisions/0030-identity-and-versioning.md) · 已定（`io.github.kusa.i5e`） |
| I24 | 年龄分级 | [0031](decisions/0031-age-rating.md) · 已定 13+（上架地区待定） |
| I25 | 隐私 | [0032](decisions/0032-privacy.md) · 已定（不收集 + 隐私清单） |
| I26 | 商店页 | [0033](decisions/0033-store-listing.md) · 文案已定，截图待 UI |
| I27 | TestFlight | [0034](decisions/0034-testflight.md) · 待定（个人阶段不启用） |
| I28 | 信息架构 | [0035](decisions/0035-navigation.md) · 已定（全屏 + 浮动按钮 + 抽屉） |
| I29 | Mac 窗口 | [0036](decisions/0036-mac-window.md) · 已定（单窗口 + 快捷键） |
| I30 | 分享复制 | [0037](decisions/0037-no-sharing.md) · 不做 |
| I31 | 状态与搜索 | [0038](decisions/0038-state-and-search.md) · 已定（展开记忆 + 搜索面板） |
| I32 | 内容版本 | [0039](decisions/0039-content-version.md) · 已定（设置页显示上游版本） |
| I33 | 启动自检 | [0040](decisions/0040-integrity-check.md) · 已定（quick_check + 重装指引） |
| I34 | 搜索质量 | [0041](decisions/0041-search-ranking.md) · 已定（标题优先排序） |
| I35 | 缺图提示 | [0042](decisions/0042-missing-images.md) · 不做（保持静默） |
| I36 | 上游同步 | [0043](decisions/0043-upstream-sync.md) · 已定（一条命令） |
| I37 | Issue 模板 | [0044](decisions/0044-issue-template.md) · 已备好 |
| I38 | 崩溃与反馈 | [0045](decisions/0045-crash-reporting.md) · 不做自建上报 |
| I39 | class 样式 | [0046](decisions/0046-class-styles.md) · 已定（stat-block 系列 + 空列折叠） |
| I40 | 表格断行 | [0047](decisions/0047-table-min-width.md) · 已定（按实测词宽定下限） |


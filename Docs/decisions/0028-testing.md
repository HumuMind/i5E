# 0028 测试策略：三层，UI 只起个头

状态：已定 · 2026-10-21

## 现状

| 层 | 覆盖 | 规模 |
|---|---|---|
| 内容管线（Python）| C1–C10：文本守恒、节点覆盖、锚点链接、schema、往返、回归、原文还原、目录、检索 | 全量 7,187 页 |
| 数据层（ContentKit）| 抽取、搜索、表格列宽、对比度、存储、偏移往返、参考表 | 29 个测试 |
| UI（XCUITest）| 启动 → 搜索 → 结果出现 | **1 个测试（起步）** |

## 决定

1. **UI 测试只起头，不铺开。** 当前只有一条主链路用例，因为 UI 还会反复改，写多了维护成本高于收益。等界面稳定后再补：目录跳转、字号切换、书签、原版表格切换。
2. **不做快照测试。** 基准图在 UI 变动期会频繁过期，改一次基准就要重看一遍图，收益为负。等 UI 定稿再评估。
3. **真机矩阵靠人工**：iPad（主）、iPhone、Mac 各过一遍冒烟清单。
4. **两个脚本分工**：`Scripts/test.sh` 跑数据层（秒级，可高频跑）；`Scripts/uitest.sh` 跑 UI（约 35 秒，含构建）。

## 一个必须记住的坑

**macOS 上的 UI 测试必须允许本地 adhoc 签名**（`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"`）。

用 `CODE_SIGNING_ALLOWED=NO` 构建时，测试 runner 会被系统直接 kill，报错是：

```
Early unexpected exit, operation never finished bootstrapping
Test crashed with signal kill before establishing connection
```

看上去像权限问题或代码问题，实际上只是没签名。`uitest.sh` 里已经写死这组参数。

## 用例的写法约定

- App 侧给关键控件加 `accessibilityIdentifier`，测试里通过标识符查找，不依赖文案——文案会改，标识符不会。
- 标识符集中在 `i5EUITests/SmokeTests.swift` 的 `AccessibilityID` 里，与 App 侧字符串保持一致，改的时候两边一起改。
- 等待统一用 `waitForExistence(timeout:)`，不用 `sleep`。

## 补记：UI 测试已暂停（2026-10-21）

UI 测试会启动 App、抢前台、结束后再关掉，日常使用电脑时很打扰，因此**在 scheme 里标为 skipped**：

- `xcodebuild test` 与 Xcode 的 Test 动作都不会再跑它
- 需要时手动执行 `./Scripts/uitest.sh`，它会明确提示会抢占前台
- 代码和 target 都保留，重新启用只需把 scheme 里的 `skipped` 改回 `NO`

暂停时它还有一处不稳定：如果 App 已经被手动打开（哪怕是旧 bundle id 的版本），测试可能拿不到窗口层次结构而超时。用例里加了 `terminate()` 也无济于事——这属于 macOS 自动化与前台窗口的老问题，等真正要用时再解决。

现在 `./Scripts/test.sh`（数据层 30 个测试）仍是唯一的自动化回归入口，秒级、不打扰。

## 重审条件

- UI 定稿后：补快照测试，覆盖阅读页、参考卡片、深色模式。
- TestFlight 有了真实反馈后：把反馈里出现过的回归点各补一条 UI 用例。

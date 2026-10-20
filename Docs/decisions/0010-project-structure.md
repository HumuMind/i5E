# 0010 工程结构：单 target + 本地 Swift Package

状态：已定 · 2026-10-20

## 背景

I3。工程怎么切，决定后面能不能单独测数据层、能不能低成本做 Mac 版。

## 决定

```
i5E.xcodeproj          提交进仓库
i5E/                   app target（iPad / iPhone / Mac 同一个）
Packages/ContentKit/   本地 Swift Package：数据库、模型、搜索
  Sources/ContentKit/
  Tests/ContentKitTests/
```

- **提交 `.xcodeproj`**，不用 XcodeGen/Tuist。单人项目，开箱即用比 diff 干净更值钱。
- **数据层单独成包**：没有 UI 依赖，可以脱离模拟器跑测试。
- **Swift 6 语言模式**（工具链 Xcode 27 / Swift 6.4 默认），严格并发。

## 理由

数据层和 UI 的变更节奏完全不同：前者跟着上游内容与管线走，后者跟着设计走。放在一个 target 里，改 UI 时也要重编译数据层，测试也没法只跑一半。

单独成包的另一个好处是 Mac 版直接复用——不用等 UI 做完，数据层就能在命令行验证。

## 后果

- 引入包边界，跨模块类型要 `public`，多一层样板。
- Xcode 版本事实上被钉住（Xcode 27 起），换版本要重新验证。
- Swift 6 严格并发下，数据库连接要在 actor 里或明确 `Sendable`，早期就按这个写，别事后补。

## 重审条件

如果发现包边界带来的样板远超收益（比如大量类型要在两层之间重复声明），退回单 target + 目录分层。

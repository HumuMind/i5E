# 0052 窗口与尺寸：单窗口，iPad 全屏

状态：已定 · 2026-10-27

## 背景

[0036](0036-mac-window.md) 定了 Mac 单窗口：所有窗口共享同一个 `AppModel`，多开只会显示同一页。
但当时只去掉了「新建窗口」菜单，场景本身仍然允许多窗口——iPad 更直接：内置
`Info.plist` 里 `UIApplicationSupportsMultipleScenes` 是 `true`，从窗口控件就能再开一个。

尺寸上，Mac 有 720pt 下限（[0050](0050-mac-sidebar.md)）；iPad 一直没有说法。分屏到 1/3 时
（约 320–375pt）正文只剩很窄一列，表格会被压得很碎，这不值得为它单独做一套排版。

## 决定

1. **三端都只有一个窗口。** 场景清单里 `UIApplicationSupportsMultipleScenes = false`。
   `AppModel` 仍是单例，不需要按窗口拆状态。
2. **iPad 按全屏设计**：声明 `UIRequiresFullScreen = true`，不做分屏 / 台前调度的窄宽布局。
   宽度就是设备宽度（竖屏 834、横屏 1194 这一类），`ReadingMetrics.measure(forAvailable:)`
   的 280pt 下限只是兜底，不是设计目标。
3. Mac 保持 0050 的 720×480 下限。

## 实现

- `Info.plist` 放在 `Config/`，不放 `i5E/`：Xcode 16 的文件系统同步组会把工程目录里的 plist
  当资源再拷贝一次，直接报 "Multiple commands produce Info.plist"。
- `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Config/Info.plist` 合并：自己那份只写
  场景清单与全屏声明，其余键（显示名、方向、启动屏、版权）继续由 Xcode 生成。
- 必须同时把 `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` 关掉：否则生成的清单会带上
  `UIApplicationSupportsMultipleScenes = true`，把自定义的 `false` 覆盖掉（两个键会同时出现在
  Info.plist 里，生成的那个在 `UIApplicationSceneManifest` 内部，优先生效）。
- 转场动画尊重「减弱动态效果」：开了 Reduce Motion 就不做动画，直接换页（[0018](0018-cross-references.md) 补记）。

## 后果

- iPad 没有「再开一个窗口对照阅读」了；要对照只能换设备或重新走一次返回。
- iOS 26 起 iPad 默认窗口化，`UIRequiresFullScreen` 是否被系统完全遵守要以真机为准；
  即使仍允许拖窗口，也不为窄宽做专门排版（内容会自适应，可能挤）。
- 关闭多窗口也让"两个窗口抢同一份阅读位置"这类问题不会出现。

## 重审条件

真要做「规则与法术对照」这类并排阅读时，再考虑每窗口独立 `AppModel`，那时才解开单窗口限制。

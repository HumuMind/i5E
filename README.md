<div align="center">

# i5E · 5E不全书

**把《DND5e不全书》做成更好读的原生应用。**

开源 · 免费 · 离线 · 无广告 · 无内购

![Platform](https://img.shields.io/badge/platform-iPadOS%20%7C%20iOS%20%7C%20macOS-1f6feb?style=flat-square)
![Status](https://img.shields.io/badge/status-early%20development-orange?style=flat-square)
![License](https://img.shields.io/badge/license-MIT%20%2F%20%E5%86%85%E5%AE%B9-GPL--3.0-2ea44f?style=flat-square)

</div>

## 这是什么

**i5E** 是英文名，**5E不全书** 是中文名。

它是 [DND5e_chm](https://github.com/DND5eChm/DND5e_chm) 的非官方原生阅读应用：把上游的 HTML 内容转换成原生页面，在 iPad、iPhone 和 Mac 上阅读，而不是套一个网页壳。

## 特性

- **原生阅读**：HTML 转换为原生排版，翻页、目录和长文阅读更接近电子书。
- **目录、索引、书签**：按书的层级浏览，快速定位条目，随时标记阅读位置。
- **自动链接**：正文里提到的条目带一条淡下划线，点一下就能跳到它自己的页面；设置里可选关闭 / 精简 / 标准 / 详细。
- **跟随上游更新**：内容随版本更新，与上游保持同步（不联网、不做后台下载）。
- **离线优先**：内容保存在本地，没有网络也能阅读。
- **多设备**：iPad 优先，然后是 iPhone 和 Mac。
- **开源免费**：没有广告、内购和账号。

## 平台

iPad 是主要阅读场景；iPhone 适合随手查阅；Mac 适合大屏对照。三端共享同一套内容，并按各自屏幕重新设计布局。

## 项目状态

项目处于起步阶段，尚无可下载版本；计划通过 TestFlight 测试并发布到 App Store。后续进展会在 issue 中更新。

## 开发

```bash
python3 Tools/content/run.py build --pack   # 生成内容库（约 50 秒）
./Scripts/stage-content.sh                  # 放进 App 资源目录（40 MB，不入库）

./Scripts/build.sh                          # 构建 App（iOS 模拟器）
./Scripts/test.sh                           # 数据层测试（49 个，含跨语言正文哈希）
./Scripts/lint.sh                           # swift-format + swiftlint
./Scripts/uitest.sh                         # UI 冒烟测试（macOS，约 35 秒）
```

或者直接打开 `i5E.xcodeproj`。最低 iOS / macOS 26。

`Scripts/build.sh` 会把完整日志写到 `build/xcodebuild.log`，只把 error/warning 打到终端。

注意：构建需要 xcodebuild 能写 `~/Library/Caches/org.swift.swiftpm`（SwiftPM 解析依赖用）。
在受限沙箱里跑会被拒，普通终端没有这个问题。

## 参与贡献

- **内容纠错**：请提交给上游 [DND5e_chm](https://github.com/DND5eChm/DND5e_chm)，本项目不直接修改原文。
- **代码与设计**：开始前请阅读 [AGENTS.md](AGENTS.md)，大改动先开 issue 对齐范围。
- **提交时不要包含**：`DND5e_chm/`、生成物、密钥或签名材料。

## 许可与声明

**代码与内容分开授权**，详见 [NOTICE](NOTICE)：

- **代码**（App、数据层、构建工具）：**MIT**，见 [LICENSE](LICENSE)。
- **内容**（`DND5e_chm/` 及其派生的内容库、图片）：来自上游 [DND5e_chm](https://github.com/DND5eChm/DND5e_chm)（GPL-3.0），文本、翻译与美术素材的著作权归 Wizards of the Coast 及相应译者/权利人所有。本项目免费、非商业、不销售内容、不修改原文。
- 本项目为非官方项目，与 Wizards of the Coast 无关联。

这样区分的原因是：App 是独立实现的，只读取上游产出的内容文件，不链接上游代码；
而内容本身的授权与权利不属于本项目可以处分的范围。

## 链接

- 上游项目：https://github.com/DND5eChm/DND5e_chm
- 问题与讨论：请使用本仓库的 issue

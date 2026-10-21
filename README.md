<div align="center">

# i5E · 5E不全书

**把《DND5e不全书》做成更好读的原生应用。**

开源 · 免费 · 离线 · 无广告 · 无内购

![Platform](https://img.shields.io/badge/platform-iPadOS%20%7C%20iOS%20%7C%20macOS-1f6feb?style=flat-square)
![Status](https://img.shields.io/badge/status-early%20development-orange?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-2ea44f?style=flat-square)

</div>

## 这是什么

**i5E** 是英文名，**5E不全书** 是中文名。

它是 [DND5e_chm](https://github.com/DND5eChm/DND5e_chm) 的非官方原生阅读应用：把上游的 HTML 内容转换成原生页面，在 iPad、iPhone 和 Mac 上阅读，而不是套一个网页壳。

## 特性

- **原生阅读**：HTML 转换为原生排版，翻页、目录和长文阅读更接近电子书。
- **目录、索引、书签**：按书的层级浏览，快速定位条目，随时标记阅读位置。
- **定期追新**：跟随上游更新，尽量保持内容同步。
- **离线优先**：内容保存在本地，没有网络也能阅读。
- **多设备**：iPad 优先，然后是 iPhone 和 Mac。
- **开源免费**：没有广告、内购和账号。

## 平台

iPad 是主要阅读场景；iPhone 适合随手查阅；Mac 适合大屏对照。三端共享同一套内容，并按各自屏幕重新设计布局。

## 项目状态

项目处于起步阶段，尚无可下载版本；计划通过 TestFlight 测试并发布到 App Store。后续进展会在 issue 中更新。

## 开发

```bash
# 1. 从上游内容生成内容库（约 35 秒）
python3 Tools/content/run.py build --pack

# 2. 把内容库放进 App 资源目录（32 MB，不入库）
./Scripts/stage-content.sh

# 3. 数据层测试（需要一个构建好的内容库）
cd Packages/ContentKit
CONTENT_DB=../../build/pack/content.db swift test
```

然后打开 `i5E.xcodeproj`。最低 iOS / macOS 26。

现状：数据层（`Packages/ContentKit`）已实现并有测试覆盖；App 还没在 Xcode 里完整跑过一次，
第一次打开若提示包依赖未解析，让 Xcode 重新解析即可。

## 参与贡献

- **内容纠错**：请提交给上游 [DND5e_chm](https://github.com/DND5eChm/DND5e_chm)，本项目不直接修改原文。
- **代码与设计**：开始前请阅读 [AGENTS.md](AGENTS.md)，大改动先开 issue 对齐范围。
- **提交时不要包含**：`DND5e_chm/`、生成物、密钥或签名材料。

## 许可与声明

- 代码采用 **GPL-3.0**，与上游一致（`LICENSE` 随首个代码提交加入）。
- 内容来自上游社区的整合与翻译，版权归 Wizards of the Coast 及相应译者/权利人所有。本项目免费、非商业，不主张内容版权，也不销售内容。
- 本项目为非官方项目，与 Wizards of the Coast 无关联。

## 链接

- 上游项目：https://github.com/DND5eChm/DND5e_chm
- 问题与讨论：请使用本仓库的 issue

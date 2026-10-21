# 0032 隐私：不收集数据，补齐隐私清单

状态：已定 · 2026-10-21

## 决定

1. **App Store 的「App 隐私」全部选「不收集」**，追踪选「否」。
2. **补齐 `PrivacyInfo.xcprivacy`**（隐私清单），声明使用 `UserDefaults` 的理由为 `CA92.1`。
3. **隐私政策写在仓库里**（`Docs/privacy.md`），发布时挂到公开地址。

## 为什么需要隐私清单

Apple 从 2024 年 5 月起要求：使用「需声明理由的 API」的应用必须提供 `PrivacyInfo.xcprivacy`，否则提交会被拒。

我们用 `UserDefaults` 存书签、阅读位置和字号，它属于该类 API。声明理由是 `CA92.1`——"访问应用自身的偏好设置"。

清单内容：

```xml
NSPrivacyTracking            false
NSPrivacyTrackingDomains     []      （无）
NSPrivacyCollectedDataTypes  []      （不收集）
NSPrivacyAccessedAPITypes    UserDefaults / CA92.1
```

文件放在 `i5E/PrivacyInfo.xcprivacy`，iOS 落在 bundle 根目录，macOS 落在 `Contents/Resources`。两个平台都验证过产物里存在。

## 为什么"不收集"是站得住的

| 常见会被算作收集的行为 | 我们的情况 |
|---|---|
| 分析 SDK、崩溃 SDK | 没有 |
| 广告标识符 | 没有 |
| 网络请求携带设备信息 | 完全不联网 |
| 账号与云端同步 | 没有 |
| 第三方登录 | 没有 |

书签和阅读位置存在本机，**不上传**——"收集"指的是把数据传出设备，本地存储不算。

## 隐私政策的要点

- 一句话结论："不收集任何数据"
- 明确列出本机保存的三类数据及用途
- 说明外链由系统浏览器打开，应用不参与
- 说明崩溃报告只在用户开启系统共享时由 Apple 提供
- 保留内容版权与非官方声明（与 [0025](0025-license-distribution.md) 一致）

## 待办（上架前）

- 把 `Docs/privacy.md` 挂到一个公开 URL（GitHub Pages 或仓库的 raw 链接），填进 App Store Connect 的「隐私政策 URL」——这是必填项，即使不收集数据。

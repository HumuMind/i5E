# 0030 Bundle ID、版本号与版权署名

状态：已定 · 2026-10-21

## 决定

| 项 | 值 |
|---|---|
| Bundle ID | `io.github.kusa.i5e` |
| UI 测试 Bundle ID | `io.github.kusa.i5e.uitests` |
| 显示名 | `5E不全书` |
| 版本号（MARKETING_VERSION）| `0.1.0` 起步，测试期 `0.1.x`，正式版从 `1.0` 起 |
| 构建号（CURRENT_PROJECT_VERSION）| `git rev-list --count HEAD`，由 `Scripts/bump-build.sh` 写入 |
| 版权 | `2026 i5E` |

## 为什么是 `io.github.kusa.i5e`

反向 DNS 的惯例是用自己可控的域名。没有域名时，`io.github.<用户名>` 是社区常见做法——它指向一个真实可查的账号，比凭空编的 `com.` 前缀更诚实。

**这个值上架后不可更改**，所以现在定下来，后面所有构建、存档、TestFlight 都用它。

## 为什么构建号用提交数

构建号只需要单调递增，不需要有意义。用 git 提交数意味着：

- 不会忘记改，也不会重复（同一个提交只有同一个号）
- CI 或本地构建结果一致
- 发布记录可以直接对应到某个 commit

版本号仍然手改，因为它是产品决策，不该自动生成。

## 签名

**暂未配置开发团队**。上架前需要：

1. Apple Developer 账号（个人 99 美元/年）
2. Team ID 填入 `DEVELOPMENT_TEAM`
3. 首次 TestFlight 前完成 App Store Connect 的 App 记录

这些等真正要上架时再做，现在构建用 `CODE_SIGNING_ALLOWED=NO` 或 adhoc 即可。

#if os(macOS)
    import AppKit
    import Foundation

    /// 调试用：`-snapshotPath /tmp/x.png` 启动后把窗口内容存成 PNG 并退出。
    ///
    /// 应用截自己的窗口不需要「屏幕录制」权限，所以这条路在无权限的机器上也能用。
    enum Snapshot {
        static func captureIfRequested() {
            guard let path = UserDefaults.standard.string(forKey: "snapshotPath"),
                !path.isEmpty
            else { return }

            Task { @MainActor in
                // 等首帧与异步加载完成
                try? await Task.sleep(for: .seconds(3))
                guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
                    let view = window.contentView,
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else {
                    NSApplication.shared.terminate(nil)
                    return
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
#endif

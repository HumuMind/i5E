import Foundation
import os

/// 性能打点。用 Instruments 的 "os_signpost" 模板即可看到这些区间。
enum Signpost {
    private static let log = OSLog(subsystem: "com.i5e.reader", category: .pointsOfInterest)
    private static let signposter = OSSignposter(logHandle: log)

    /// 标注为 @MainActor：调用方都在主 actor 上，避免把非 Sendable 的闭包
    /// 送进 nonisolated 上下文（Swift 6 严格并发会直接报错）。
    @MainActor
    static func measure<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    /// 同步版本，用于渲染路径。
    static func measureSync<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return body()
    }
}

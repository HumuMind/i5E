import Foundation
import GRDB
import CryptoKit

/// 只读内容库。数据由 `Tools/content` 构建，格式见 Docs/decisions/0007-storage.md。
public final class ContentDatabase: Sendable {

    private let dbQueue: DatabaseQueue

    public init(url: URL) throws {
        var config = Configuration()
        config.readonly = true
        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
    }

    // MARK: - 目录

    public func tableOfContents() async throws -> TOC {
        let json: String? = try await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'toc'")
        }
        guard let json, let data = json.data(using: .utf8) else {
            throw ContentError.missingMeta("toc")
        }
        return try JSONDecoder().decode(TOC.self, from: data)
    }

    public func metaValue(_ key: String) async throws -> String? {
        try await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key])
        }
    }

    // MARK: - 页面

    public func page(id: Int64) async throws -> Page? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT id, path, title, blocks FROM pages WHERE id = ?", arguments: [id])
            else { return nil }
            return try Self.makePage(row)
        }
    }

    public func page(path: String) async throws -> Page? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT id, path, title, blocks FROM pages WHERE path = ?", arguments: [path])
            else { return nil }
            return try Self.makePage(row)
        }
    }

    private static func makePage(_ row: Row) throws -> Page {
        let blob: Data = row["blocks"]
        let json = try Zlib.inflate(blob)
        let blocks = try JSONDecoder().decode([Block].self, from: json)
        return Page(id: row["id"], path: row["path"], title: row["title"] ?? "", blocks: blocks)
    }

    // MARK: - 搜索

    /// 三步走：FTS 召回候选 → 正文子串校验 → 够数即停。
    public func search(_ raw: String, limit: Int = 50) async throws -> [SearchHit] {
        guard let expression = SearchQuery.matchExpression(for: raw) else { return [] }
        let needle = SearchQuery.normalized(raw)
        guard !needle.isEmpty else { return [] }

        return try await dbQueue.read { db in
            let ids = try Int64.fetchAll(
                db, sql: "SELECT rowid FROM search WHERE search MATCH ?", arguments: [expression])

            var hits: [SearchHit] = []
            for id in ids {
                guard let row = try Row.fetchOne(
                    db, sql: "SELECT id, path, title, blocks FROM pages WHERE id = ?", arguments: [id])
                else { continue }

                let blob: Data = row["blocks"]
                let blocks = try JSONDecoder().decode([Block].self, from: try Zlib.inflate(blob))
                let text = PageText.of(blocks)
                guard let range = text.lowercased().range(of: needle) else { continue }

                let snippet = Self.snippet(text, around: range)
                hits.append(SearchHit(pageID: row["id"], path: row["path"],
                                      title: row["title"] ?? "", snippet: snippet))
                if hits.count >= limit { break }
            }
            return hits
        }
    }

    private static func snippet(_ text: String, around range: Range<String.Index>, radius: Int = 24) -> String {
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }

    // MARK: - 跨语言自检

    /// 重算全库正文哈希，与构建时写入的 `text_sha256` 比对。
    ///
    /// 若不一致，说明 Swift 的 `PageText` 与 Python 的 `page_text` 行为不同，
    /// 搜索的校验步骤会给出错误结果——这种 bug 很难靠肉眼发现，必须机器检查。
    public func verifyTextDigest() async throws -> Bool {
        guard let raw = try await metaValue("text_sha256"),
              let data = raw.data(using: .utf8),
              let expected = try? JSONDecoder().decode(String.self, from: data)
        else { return false }

        return try await dbQueue.read { db in
            var hasher = SHA256()
            let cursor = try Row.fetchCursor(db, sql: "SELECT blocks FROM pages ORDER BY id")
            while let row = try cursor.next() {
                let blob: Data = row["blocks"]
                let blocks = try JSONDecoder().decode([Block].self, from: try Zlib.inflate(blob))
                hasher.update(data: Data(PageText.of(blocks).utf8))
                hasher.update(data: Data("\n".utf8))
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return digest == expected
        }
    }
}

public enum ContentError: Error, CustomStringConvertible {
    case missingMeta(String)
    case badCompressedData

    public var description: String {
        switch self {
        case .missingMeta(let key): "内容库缺少 meta.\(key)"
        case .badCompressedData: "压缩数据无法解压"
        }
    }
}

/// 解 zlib 格式（Python `zlib.compress` 的产物）。
///
/// 苹果的 `Compression` 框架只认裸 deflate，所以要剥掉 2 字节头和 4 字节 Adler-32 校验尾。
enum Zlib {
    static func inflate(_ data: Data) throws -> Data {
        guard data.count > 6 else { throw ContentError.badCompressedData }
        let body = data.dropFirst(2).dropLast(4)
        do {
            return try (body as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ContentError.badCompressedData
        }
    }
}

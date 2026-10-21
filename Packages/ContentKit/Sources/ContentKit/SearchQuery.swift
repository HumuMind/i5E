import Foundation

/// FTS5 查询构造，与 `Tools/content/pack.py::search` 同一套规则。
///
/// 索引里是**单字 + 双字**，detail=none（只记有无、不记位置），所以：
/// - 单字查询直接用该字；
/// - 多字查询拆成相邻双字，用 AND 连接，得到候选集；
/// - 候选必然过匹配（例如 “AC” 会命中任何含 a、c 相邻的行），必须在正文上再做子串校验。
public enum SearchQuery {

    /// 扫描长度下限；低于这个长度不发起搜索。
    public static let minimumLength = 1

    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 生成 FTS5 MATCH 表达式。返回 nil 表示不该搜。
    public static func matchExpression(for raw: String) -> String? {
        let q = normalized(raw)
        guard q.count >= minimumLength else { return nil }
        let chars = Array(q)

        if chars.count == 1 {
            return quote(String(chars[0]))
        }
        let bigrams = (0..<(chars.count - 1)).map { quote(String(chars[$0...$0 + 1])) }
        return bigrams.joined(separator: " AND ")
    }

    /// FTS5 字符串字面量里的双引号要写成两个。
    private static func quote(_ token: String) -> String {
        "\"" + token.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

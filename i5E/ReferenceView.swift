import ContentKit
import SwiftUI

/// 速查页的专用视图：默认是卡片瀑布流 + 筛选，可切回原版表格。
///
/// 判据见 `ReferenceTableExtractor`：行数最多的一张表且 ≥50 行。
struct ReferenceView: View {
    let page: Page
    let table: ReferenceTable

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readingMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode { case cards, table }

    @State private var mode: Mode = .cards
    @State private var query = ""
    @State private var selected: [Int: Set<String>] = [:]

    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().overlay(theme.border)
            content
        }
        .background(theme.background)
        .environment(\.readingTheme, theme)
        .overlay(alignment: .bottomTrailing) { modeToggle }
        .navigationTitle(page.title.isEmpty ? page.path : page.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 筛选

    private var facetColumns: [(index: Int, values: [String])] {
        (1..<table.columnCount)
            .map { ($0, table.facets(column: $0)) }
            .filter { !$0.1.isEmpty }
            .prefix(4)
            .map { (index: $0.0, values: $0.1) }
    }

    private var filteredRows: [[ReferenceCell]] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return table.rows.filter { row in
            for (column, values) in selected where !values.isEmpty {
                guard column < row.count, values.contains(row[column].text) else { return false }
            }
            guard !needle.isEmpty else { return true }
            return row.contains { $0.text.lowercased().contains(needle) }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(theme.muted)
                TextField("筛选（\(table.rows.count) 条）", text: $query)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    #endif
                if !query.isEmpty || !selected.isEmpty {
                    Button {
                        query = ""
                        selected = [:]
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if !facetColumns.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(facetColumns, id: \.index) { column in
                            facetMenu(column.index, values: column.values)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.top, 6)
        .background(theme.surface)
    }

    private func facetMenu(_ column: Int, values: [String]) -> some View {
        let picked = selected[column] ?? []
        let label =
            table.headers.count > column && !table.headers[column].isEmpty
            ? table.headers[column] : "第 \(column + 1) 列"
        return Menu {
            Button("全部") { selected[column] = nil }
            ForEach(values, id: \.self) { value in
                Button {
                    var set = selected[column] ?? []
                    if set.contains(value) { set.remove(value) } else { set.insert(value) }
                    selected[column] = set.isEmpty ? nil : set
                } label: {
                    Label(value, systemImage: picked.contains(value) ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(picked.isEmpty ? label : "\(label) · \(picked.count)")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                picked.isEmpty ? theme.surface : theme.accent.opacity(0.15),
                in: .capsule
            )
            .overlay(Capsule().stroke(theme.border, lineWidth: 0.5))
            .foregroundStyle(picked.isEmpty ? theme.muted : theme.accent)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .cards: cardGrid
        case .table: tableScroll
        }
    }

    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                alignment: .leading, spacing: 12
            ) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    card(row)
                }
            }
            .padding(16)
            if filteredRows.isEmpty {
                ContentUnavailableView("没有匹配", systemImage: "line.3.horizontal.decrease.circle")
                    .padding(.top, 60)
            }
        }
    }

    private func card(_ row: [ReferenceCell]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = row.first {
                Text(first.text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(first.link == nil ? theme.text : theme.link)
                    .multilineTextAlignment(.leading)
            }
            ForEach(Array(row.enumerated().dropFirst().prefix(6)), id: \.offset) { index, cell in
                if !cell.text.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(fieldLabel(index))
                            .font(.caption2)
                            .foregroundStyle(theme.muted)
                            .frame(width: 46, alignment: .leading)
                        Text(cell.text)
                            .font(.caption)
                            .foregroundStyle(theme.text)
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.surface, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardLabel(row))
        .accessibilityAddTraits(row.first?.link == nil ? [] : .isButton)
        .contentShape(.rect)
        .onTapGesture {
            if let href = row.first?.link { follow(href) }
        }
    }

    /// 卡片朗读文本：「火球术，环阶：三环，学派：塑能」。
    private func cardLabel(_ row: [ReferenceCell]) -> String {
        row.enumerated().compactMap { index, cell in
            guard !cell.text.isEmpty else { return nil }
            return index == 0 ? cell.text : "\(fieldLabel(index))：\(cell.text)"
        }
        .joined(separator: "，")
    }

    private func fieldLabel(_ index: Int) -> String {
        table.headers.count > index && !table.headers[index].isEmpty
            ? table.headers[index] : "—"
    }

    // MARK: - 原版表格

    private var tableScroll: some View {
        let widths = columnWidths()
        let total = widths.reduce(0, +)
        return ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                headerRow(widths)
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    rowView(row, widths)
                }
            }
            .frame(width: max(total, 320), alignment: .leading)
        }
    }

    private func headerRow(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                Text(fieldLabel(index))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .frame(width: width, alignment: .leading)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 0.5))
            }
        }
        .background(theme.surface)
    }

    private func rowView(_ row: [ReferenceCell], _ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                Text(index < row.count ? row[index].text : "")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        index == 0 && row.first?.link != nil ? theme.link : theme.text
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(width: width, alignment: .leading)
                    .overlay(Rectangle().stroke(theme.border, lineWidth: 0.5))
            }
        }
    }

    /// 原版列宽：按内容估，取上限避免某列吃掉整行。
    private func columnWidths() -> [CGFloat] {
        (0..<table.columnCount).map { column in
            var units = 6.0
            for row in table.rows.prefix(200) where column < row.count {
                units = max(units, min(26, TableLayoutCalculator.displayUnits(row[column].text)))
            }
            return CGFloat(units) * 6 + 14
        }
    }

    // MARK: - 悬浮开关

    private var modeToggle: some View {
        HStack(spacing: 2) {
            toggleItem(.cards, icon: "square.grid.2x2", label: "卡片")
            toggleItem(.table, icon: "tablecells", label: "原版")
        }
        .padding(3)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().stroke(theme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(20)
    }

    private func toggleItem(_ item: Mode, icon: String, label: String) -> some View {
        let active = mode == item
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { mode = item }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? theme.accent.opacity(0.16) : .clear, in: .capsule)
            .foregroundStyle(active ? theme.accent : theme.muted)
        }
        .buttonStyle(.plain)
    }

    private func follow(_ href: String) {
        if let url = URL(string: href) { model.handleLink(url) }
    }
}

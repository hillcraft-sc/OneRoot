import Foundation

/// Formats for exporting Advanced Search results — see
/// `SearchResultExportService`.
enum SearchResultExportFormat: String, CaseIterable {
    case csv
    case plainText
    case markdown
    case interactiveHTML

    var title: String {
        switch self {
        case .csv: return "CSV"
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .interactiveHTML: return "Interactive HTML"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .plainText: return "txt"
        case .markdown: return "md"
        case .interactiveHTML: return "html"
        }
    }
}

/// Serializes Advanced Search results into one of `SearchResultExportFormat`.
/// UI-agnostic (Foundation-only, CLAUDE.md §1) — `AdvancedSearchView` picks
/// the format and destination, this just produces the file contents.
struct SearchResultExportService {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    func export(_ results: [SearchResult], mode: SearchMode, format: SearchResultExportFormat) -> String {
        switch format {
        case .csv: return csv(results, mode: mode)
        case .plainText: return plainText(results, mode: mode)
        case .markdown: return markdown(results, mode: mode)
        case .interactiveHTML: return interactiveHTML(results, mode: mode)
        }
    }

    // MARK: CSV

    private func csv(_ results: [SearchResult], mode: SearchMode) -> String {
        var lines = [csvRow(columns(for: mode))]
        for result in results {
            lines.append(csvRow(row(for: result)))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func csvRow(_ fields: [String]) -> String {
        fields.map(csvEscape).joined(separator: ",")
    }

    private func csvEscape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: Plain text

    private func plainText(_ results: [SearchResult], mode: SearchMode) -> String {
        results.map { result in
            let cells = row(for: result)
            return zip(columns(for: mode), cells).map { "\($0): \($1)" }.joined(separator: "  |  ")
        }.joined(separator: "\n") + "\n"
    }

    // MARK: Markdown

    private func markdown(_ results: [SearchResult], mode: SearchMode) -> String {
        let headers = columns(for: mode)
        var lines = ["| " + headers.joined(separator: " | ") + " |"]
        lines.append("| " + headers.map { _ in "---" }.joined(separator: " | ") + " |")
        for result in results {
            let cells = row(for: result).map { $0.replacingOccurrences(of: "|", with: "\\|") }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Interactive HTML

    /// Self-contained — everything inlined, no CDN/external requests — a
    /// sortable (click a header), filterable (type in the box) table. Loads
    /// fine offline and doesn't depend on this specific machine having
    /// anything installed.
    private func interactiveHTML(_ results: [SearchResult], mode: SearchMode) -> String {
        let headers = columns(for: mode)
        let headerCells = headers.map { "<th onclick=\"sortBy('\(htmlEscape($0))')\">\(htmlEscape($0))</th>" }.joined()
        let bodyRows = results.map { result -> String in
            let cells = row(for: result).map { "<td>\(htmlEscape($0))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>OneRoot Search Results</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 13px -apple-system, BlinkMacSystemFont, sans-serif; margin: 16px; }
        input { padding: 6px 8px; width: 100%; max-width: 420px; margin-bottom: 12px; box-sizing: border-box; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid rgba(128,128,128,0.3); }
        th { cursor: pointer; user-select: none; position: sticky; top: 0; background: Canvas; }
        th:hover { text-decoration: underline; }
        tr:hover td { background: rgba(128,128,128,0.1); }
        #count { color: gray; margin-bottom: 8px; }
        </style>
        </head>
        <body>
        <input id="filter" type="text" placeholder="Filter results…" oninput="applyFilter()">
        <div id="count"></div>
        <table id="results">
        <thead><tr>\(headerCells)</tr></thead>
        <tbody>
        \(bodyRows)
        </tbody>
        </table>
        <script>
        let sortAscending = true;
        function applyFilter() {
            const query = document.getElementById('filter').value.toLowerCase();
            const rows = document.querySelectorAll('#results tbody tr');
            let visible = 0;
            rows.forEach(row => {
                const matches = row.textContent.toLowerCase().includes(query);
                row.style.display = matches ? '' : 'none';
                if (matches) visible++;
            });
            document.getElementById('count').textContent = visible + ' of ' + rows.length + ' shown';
        }
        function sortBy(columnName) {
            const table = document.getElementById('results');
            const headers = Array.from(table.querySelectorAll('th'));
            const columnIndex = headers.findIndex(h => h.textContent === columnName);
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            rows.sort((a, b) => {
                const aText = a.children[columnIndex].textContent;
                const bText = b.children[columnIndex].textContent;
                return sortAscending ? aText.localeCompare(bText, undefined, { numeric: true })
                                      : bText.localeCompare(aText, undefined, { numeric: true });
            });
            sortAscending = !sortAscending;
            rows.forEach(row => tbody.appendChild(row));
        }
        applyFilter();
        </script>
        </body>
        </html>
        """
    }

    private func htmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Shared row/column shaping

    private func columns(for mode: SearchMode) -> [String] {
        mode == .contents
            ? ["Name", "Line", "Match", "Path"]
            : ["Name", "Size", "Date Modified", "Path"]
    }

    private func row(for result: SearchResult) -> [String] {
        let path = result.node.url.deletingLastPathComponent().path
        if let contentMatch = result.contentMatch {
            return [result.node.name, String(contentMatch.lineNumber), contentMatch.snippet, path]
        }
        let size = result.node.isDirectory ? "--" : (result.node.size.map { Self.byteFormatter.string(fromByteCount: $0) } ?? "")
        let date = result.node.modificationDate.map(Self.dateFormatter.string) ?? ""
        return [result.node.name, size, date, path]
    }
}

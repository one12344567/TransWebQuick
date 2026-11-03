import Foundation

public struct CapturedContext: Sendable {
    public let selection: String
    public let context: String
    public let sourceApp: String
    public let limited: Bool
    public init(selection: String, context: String, sourceApp: String, limited: Bool) {
        self.selection = selection; self.context = context; self.sourceApp = sourceApp; self.limited = limited
    }
}
public enum ContextBuilder {
    public static func make(selection: String, surrounding: String?, sourceApp: String) -> CapturedContext? {
        let selected = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, selected.unicodeScalars.count <= 1000 else { return nil }
        guard let surrounding, let range = surrounding.range(of: selected) else {
            return CapturedContext(selection: selected, context: selected, sourceApp: sourceApp, limited: true)
        }
        let before = surrounding[..<range.lowerBound].suffix(600)
        let after = surrounding[range.upperBound...].prefix(1200)
        return CapturedContext(selection: selected, context: String(before) + selected + String(after), sourceApp: sourceApp, limited: before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
public enum AnswerParts {
    public static func split(_ text: String) -> (meaning: String, explanation: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let range = normalized.range(of: "\n\n") else { return (normalized, "") }
        return (String(normalized[..<range.lowerBound]), String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
public struct SSEParser {
    private var data: [String] = []
    public init() {}
    public mutating func line(_ line: String) -> String? {
        if line.isEmpty {
            defer { data.removeAll(keepingCapacity: true) }
            return data.isEmpty ? nil : data.joined(separator: "\n")
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5)); if value.first == " " { value.removeFirst() }
            data.append(value)
        }
        return nil
    }
}

import Foundation

enum TranslationTargetMode: String, Codable, CaseIterable, Equatable {
    case automatic
    case fixed
}

enum TranslationFormattingMode: String, Codable, CaseIterable, Equatable {
    case strict
    case smart
    case polish

    var displayName: String {
        switch self {
        case .strict: return "严格保留"
        case .smart: return "智能排版"
        case .polish: return "智能润色"
        }
    }
}

enum SmartTranslationFormatter {
    static func format(_ raw: String, mode: TranslationFormattingMode) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let hadTrailingNewline = normalized.hasSuffix("\n")
        let lines = normalized.components(separatedBy: "\n").map(trimTrailingWhitespace)
        // 已有换行是源应用提供的最可靠结构证据。智能排版与润色的
        // 结构恢复交给 Azure GPT；本地层只做无损规范化，绝不提前合并。
        var result = lines.joined(separator: "\n")
        if !hadTrailingNewline, result.hasSuffix("\n") { result.removeLast() }
        return result
    }

    private static func trimTrailingWhitespace(_ line: String) -> String {
        let withoutSpaces = String(line.reversed().drop(while: { $0 == " " }).reversed())
        let tabCount = withoutSpaces.reduce(0) { $1 == "\t" ? $0 + 1 : $0 }
        guard tabCount < 2 else { return withoutSpaces }
        return String(withoutSpaces.reversed().drop(while: { $0 == "\t" }).reversed())
    }

    private static func isStructuredLine(_ line: String) -> Bool {
        if line.contains("\t") { return true }
        if line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("|") { return true }
        if line.range(of: #"^(?:[-*+•◦▪‣–]\s+|\d+[.)]\s+)"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^(?:From|To|Cc|Bcc|Subject|Date|Reply-To|发件人|收件人|抄送|主题|日期)\s*[:：]"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return false
    }

    private static func joinSeparator(left: String, right: String) -> String {
        guard let leftScalar = left.unicodeScalars.last,
              let rightScalar = right.unicodeScalars.first else { return "" }
        return isCJK(leftScalar) || isCJK(rightScalar) ? "" : " "
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }
}

enum SpeechTextFormatter {
    static func speechText(from source: String) -> String {
        var output: [String] = []
        var inCodeFence = false
        for line in source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence {
                output.append(line)
                continue
            }
            output.append(removingSpokenStructure(from: line))
        }
        return output.joined(separator: "\n")
    }

    private static func removingSpokenStructure(from line: String) -> String {
        let patterns = [
            #"^\s*#{1,6}\s+"#,
            #"^\s*(?:[-*+]\s+|\d+[.)]\s+)"#,
            #"^\s*>\s?"#
        ]
        for pattern in patterns where line.range(of: pattern, options: .regularExpression) != nil {
            return line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return line
    }
}

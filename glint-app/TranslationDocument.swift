import Foundation

struct TranslationFragment: Equatable {
    let id: String
    let text: String
    let protectedTokens: [TranslationProtectedToken]

    init(id: String, text: String, protectedTokens: [TranslationProtectedToken] = []) {
        self.id = id
        self.text = text
        self.protectedTokens = protectedTokens
    }
}

struct TranslationProtectedToken: Equatable {
    let placeholder: String
    let originalText: String
}

struct TranslationFragmentResponse: Equatable {
    let id: String
    let translatedText: String
    let detectedLanguage: String?
}

struct TranslationDocumentResult: Equatable {
    let text: String
    let detectedLanguage: String?
}

struct TranslationBatchLimits: Equatable {
    let maxItems: Int
    let maxCharacters: Int

    static let azureDefault = TranslationBatchLimits(maxItems: 100, maxCharacters: 45_000)
}

struct TranslationDocument {
    let formattedText: String
    let fragments: [TranslationFragment]
    private let template: String

    init(formattedText: String) {
        self.formattedText = formattedText
        var collected: [TranslationFragment] = []
        var output: [String] = []
        var inCodeFence = false

        func placeholder(for text: String) -> String {
            Self.stableChunks(
                text,
                maximumCharacters: TranslationBatchLimits.azureDefault.maxCharacters
            ).map { chunk in
                let fragmentIndex = collected.count
                let id = String(format: "fragment-%04d", fragmentIndex)
                let protected = Self.protectTokens(in: chunk, fragmentIndex: fragmentIndex)
                collected.append(TranslationFragment(
                    id: id,
                    text: protected.text,
                    protectedTokens: protected.tokens
                ))
                return "\u{E000}\(id)\u{E001}"
            }.joined()
        }

        for line in formattedText.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                output.append(line)
                inCodeFence.toggle()
                continue
            }
            if inCodeFence || trimmed.isEmpty || Self.isTableDelimiter(trimmed) {
                output.append(line)
                continue
            }
            if line.contains("\t") {
                let cells = line.components(separatedBy: "\t").map { cell -> String in
                    let leading = String(cell.prefix(while: { $0 == " " }))
                    let trailing = String(cell.reversed().prefix(while: { $0 == " " }).reversed())
                    let content = cell.trimmingCharacters(in: .whitespaces)
                    return content.isEmpty ? cell : leading + placeholder(for: content) + trailing
                }
                output.append(cells.joined(separator: "\t"))
                continue
            }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                if cells.count >= 2 {
                    for index in cells.indices where !cells[index].trimmingCharacters(in: .whitespaces).isEmpty {
                        let clean = cells[index].trimmingCharacters(in: .whitespaces)
                        cells[index] = " " + placeholder(for: clean) + " "
                    }
                    output.append(cells.joined(separator: "|"))
                    continue
                }
            }
            if let match = Self.prefixMatch(in: line, pattern: #"^(\s*#{1,6}\s+)(.+)$"#) {
                output.append(match.prefix + placeholder(for: match.content))
                continue
            }
            if let match = Self.prefixMatch(in: line, pattern: #"^(\s*(?:[-*+•◦▪‣–]|\d+[.)])\s+)(.+)$"#) {
                output.append(match.prefix + placeholder(for: match.content))
                continue
            }
            if let match = Self.prefixMatch(in: line, pattern: #"^(\s*>\s*)(.+)$"#) {
                output.append(match.prefix + placeholder(for: match.content))
                continue
            }
            let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let trailing = String(line.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
            let content = line.trimmingCharacters(in: .whitespaces)
            output.append(content.isEmpty ? line : leading + placeholder(for: content) + trailing)
        }
        fragments = collected
        template = output.joined(separator: "\n")
    }

    func batches(limits: TranslationBatchLimits) -> [[TranslationFragment]] {
        let maxItems = max(1, limits.maxItems)
        let maxCharacters = max(1, limits.maxCharacters)
        var result: [[TranslationFragment]] = []
        var current: [TranslationFragment] = []
        var characters = 0
        for fragment in fragments {
            let wouldOverflow = !current.isEmpty
                && (current.count >= maxItems || characters + fragment.text.count > maxCharacters)
            if wouldOverflow {
                result.append(current)
                current = []
                characters = 0
            }
            current.append(fragment)
            characters += fragment.text.count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    func reassemble(_ responses: [TranslationFragmentResponse]) -> TranslationDocumentResult? {
        let expected = Set(fragments.map(\.id))
        let actual = Set(responses.map(\.id))
        guard expected == actual, responses.count == fragments.count else { return nil }
        let map = Dictionary(uniqueKeysWithValues: responses.map { ($0.id, $0.translatedText) })
        guard map.count == fragments.count else { return nil }
        var replacements: [String: String] = [:]
        for fragment in fragments {
            guard var replacement = map[fragment.id] else { return nil }
            for token in fragment.protectedTokens {
                guard Self.occurrenceCount(of: token.placeholder, in: replacement) == 1 else { return nil }
                replacement = replacement.replacingOccurrences(of: token.placeholder, with: token.originalText)
            }
            replacements[fragment.id] = replacement
        }
        guard let result = Self.renderTemplate(template, replacements: replacements) else { return nil }
        let detected = responses.compactMap(\.detectedLanguage).first { !$0.isEmpty }
        return TranslationDocumentResult(text: result, detectedLanguage: detected)
    }

    private static func stableChunks(_ text: String, maximumCharacters: Int) -> [String] {
        let limit = max(1, maximumCharacters)
        guard text.count > limit else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }

    private static func renderTemplate(
        _ template: String,
        replacements: [String: String]
    ) -> String? {
        let startMarker = "\u{E000}"
        let endMarker = "\u{E001}"
        var output = ""
        var cursor = template.startIndex
        var consumed = Set<String>()

        while let markerRange = template.range(of: startMarker, range: cursor..<template.endIndex) {
            output += template[cursor..<markerRange.lowerBound]
            let idStart = markerRange.upperBound
            guard let idEndRange = template.range(of: endMarker, range: idStart..<template.endIndex) else {
                return nil
            }
            let id = String(template[idStart..<idEndRange.lowerBound])
            guard let replacement = replacements[id], consumed.insert(id).inserted else { return nil }
            output += replacement
            cursor = idEndRange.upperBound
        }
        output += template[cursor..<template.endIndex]
        guard consumed.count == replacements.count else { return nil }
        return output
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        line.range(of: #"^\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?$"#, options: .regularExpression) != nil
    }

    private static func prefixMatch(in line: String, pattern: String) -> (prefix: String, content: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 3,
              let prefixRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[prefixRange]), String(line[contentRange]))
    }

    private static func protectTokens(
        in text: String,
        fragmentIndex: Int
    ) -> (text: String, tokens: [TranslationProtectedToken]) {
        let pattern = #"(?i:https?://[^\s<>\"]+)|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\b\d{4}-\d{2}-\d{2}\b|\b(?:USD|EUR|GBP|CNY|RMB|JPY)\s+\d[\d,]*(?:\.\d+)?\b|(?:/(?:[^/\s]+))+|\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b|\b\d+(?:[.,]\d+)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return (text, []) }

        var protectedText = text
        var tokens: [TranslationProtectedToken] = []
        for (tokenIndex, match) in matches.enumerated().reversed() {
            guard let range = Range(match.range, in: protectedText) else { continue }
            let original = String(protectedText[range])
            let placeholder = String(
                format: "\u{E100}protected-%04d-%04dX\u{E101}",
                fragmentIndex,
                tokenIndex
            )
            protectedText.replaceSubrange(range, with: placeholder)
            tokens.insert(
                TranslationProtectedToken(placeholder: placeholder, originalText: original),
                at: 0
            )
        }
        return (protectedText, tokens)
    }

    private static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }
}

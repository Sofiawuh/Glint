import Foundation

enum TranslationContentValidator {
    static func isFormattingFaithful(original: String, candidate: String) -> Bool {
        removingUnicodeWhitespace(original) == removingUnicodeWhitespace(candidate)
    }

    static func preservesProtectedFacts(original: String, candidate: String) -> Bool {
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let tokens = protectedTokens(in: original) + namedEntityTokens(in: original)
        for token in tokens where occurrenceCount(of: token, in: candidate) != occurrenceCount(of: token, in: original) {
            return false
        }
        let originalItems = listItems(in: original)
        let candidateItems = listItems(in: candidate)
        guard originalItems.count == candidateItems.count else { return false }
        let originalAnchorSets = originalItems.map(lexicalAnchors)
        for (index, pair) in zip(originalItems, candidateItems).enumerated() {
            let (originalItem, candidateItem) = pair
            let itemTokens = protectedTokens(in: originalItem) + namedEntityTokens(in: originalItem)
            let anchorsFromOtherItems = originalAnchorSets.enumerated().reduce(into: Set<String>()) {
                if $1.offset != index { $0.formUnion($1.element) }
            }
            let discriminatingAnchors = originalAnchorSets[index].subtracting(anchorsFromOtherItems)
            guard itemTokens.allSatisfy({ candidateItem.contains($0) }),
                  listItemsDescribeSameFact(
                    originalItem,
                    candidateItem,
                    discriminatingAnchors: discriminatingAnchors
                  ) else { return false }
        }
        return true
    }

    private static func removingUnicodeWhitespace(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    private static func protectedTokens(in text: String) -> [String] {
        let patterns = [
            #"(?i:https?://[^\s<>\"]+)"#,
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#,
            #"\b(?:USD|EUR|GBP|CNY|RMB|JPY)\s+\d[\d,]*(?:\.\d+)?\b"#,
            #"\b\d+(?:\.\d+)?%"#,
            #"\b[A-Z][A-Z0-9]+-\d+\b"#,
            #"(?<![\p{L}\p{N}])\d[\d,]*(?:\.\d+)?(?![\p{L}\p{N}])"#,
            #"(?:/(?:[^/\s:]+))+"#,
            #"\b[a-z]+[A-Z][A-Za-z0-9]*\b"#,
            #"(?<=[:,(]\s)\b[A-Z][A-Za-z'’-]{1,}\b"#,
            #"\b(?:First|Second|Third|Fourth|Fifth|Sixth|Seventh|Eighth|Ninth|Tenth)\b"#,
            #"\b[A-Z][a-z]+(?:\s+[A-Z][A-Za-z]+)+\b"#
        ]
        var values: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let swiftRange = Range(match.range, in: text) {
                    values.append(String(text[swiftRange]))
                }
            }
        }
        return Array(Set(values)).sorted { $0.count > $1.count }
    }

    private static func namedEntityTokens(in text: String) -> [String] {
        var values: [String] = []

        // Do not treat every title-cased sentence opener as an entity: that rejects valid
        // polishing such as "Customers" → "Clients". Protect single-word English names and
        // resources only when their surrounding grammar makes the entity role explicit.
        let englishEntityPatterns: [(String, Int)] = [
            (#"(?:^|[.!?]\s+)([A-Z][A-Za-z'’-]{1,})(?=\s+(?:will|shall|must|can)\b)"#, 1),
            (#"\b(?:notify|contact|ask|tell|email|call|use|visit|deploy to|migrate to)\s+([A-Z][A-Za-z'’-]{1,})\b"#, 1),
            (#"\b([A-Z][A-Za-z'’-]{1,})(?=\s+(?:migration|project|platform|gateway|service|system|database|cluster|team)\b)"#, 1)
        ]
        for (pattern, capture) in englishEntityPatterns {
            values.append(contentsOf: regexValues(pattern: pattern, in: text, capture: capture))
        }

        // Chinese has no capitalization. Protect names and named resources when the
        // surrounding grammar gives us high-confidence boundaries.
        let chineseEntityPatterns: [(String, Int)] = [
            (#"(?:^|[，。；\n])([\p{Han}]{2,4}?)(?=将|会|负责|联系|检查|处理|通知|确认|审核)"#, 1),
            (#"(?:请由|由|联系人[:：]?|负责人[:：]?)([\p{Han}]{2,4}?)(?=将|会|负责|联系|检查|处理|通知|确认|审核|[，。；、\s])"#, 1),
            (#"(?:^|[，。；\n])([\p{Han}]{2,4})(?=是[\p{Han}]{2,12}(?:负责人|代表|经理|主管|工程师|联系人))"#, 1),
            (#"(?:联系|检查|访问|使用|通知|迁移到|部署到|和|与)([\p{Han}]{2,12}?(?:数据平台|平台|网关|公司|集团|团队|部门|中心|服务|系统|项目|资源|数据库|集群))"#, 1)
        ]
        for (pattern, capture) in chineseEntityPatterns {
            values.append(contentsOf: regexValues(pattern: pattern, in: text, capture: capture))
        }

        return Array(Set(values)).sorted { $0.count > $1.count }
    }

    private static func listItemsDescribeSameFact(
        _ original: String,
        _ candidate: String,
        discriminatingAnchors: Set<String>
    ) -> Bool {
        let originalAnchors = lexicalAnchors(in: original)
        let candidateAnchors = lexicalAnchors(in: candidate)
        if !discriminatingAnchors.isEmpty {
            return discriminatingAnchors.isSubset(of: candidateAnchors)
        }
        guard !originalAnchors.isEmpty else {
            return removingUnicodeWhitespace(original).lowercased()
                == removingUnicodeWhitespace(candidate).lowercased()
        }
        return !originalAnchors.isDisjoint(with: candidateAnchors)
    }

    private static func lexicalAnchors(in text: String) -> Set<String> {
        let englishStopWords: Set<String> = [
            "about", "after", "again", "before", "from", "into", "that", "their",
            "then", "there", "these", "this", "those", "with", "your"
        ]
        var anchors = Set(
            regexValues(pattern: #"\b[A-Za-z]{4,}\b"#, in: text)
                .map { $0.lowercased() }
                .filter { !englishStopWords.contains($0) }
        )

        for run in regexValues(pattern: #"[\p{Han}]{2,}"#, in: text) {
            let characters = Array(run)
            if characters.count == 2 {
                anchors.insert(run)
            } else {
                for index in 0..<(characters.count - 1) {
                    anchors.insert(String(characters[index...index + 1]))
                }
            }
        }
        return anchors
    }

    private static func regexValues(
        pattern: String,
        in text: String,
        capture: Int = 0
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > capture,
                  let swiftRange = Range(match.range(at: capture), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func listItems(in text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { line in
            let pattern = #"^\s*(?:[-*+•◦▪‣–]|\d+[.)])\s+(.+)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[range])
        }
    }

    private static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }
}

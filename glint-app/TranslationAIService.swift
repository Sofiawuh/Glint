import Foundation

enum TranslationBlock: Equatable {
    case salutation(String)
    case heading(String)
    case paragraph(String)
    case keyPoints([String])
    case quote(String)
    case code(String)
    case table(String)
    case signature(String)
}

struct TranslationAIAutomaticResult: Equatable {
    let sourceBlocks: [TranslationBlock]
    let translationBlocks: [TranslationBlock]
}

struct TranslationAIService {
    let config: AzureOpenAIConfig

    func buildAutomaticRequest(
        sourceText: String,
        translatedText: String,
        mode: TranslationFormattingMode
    ) -> URLRequest? {
        guard mode != .strict else { return nil }
        let system = """
        You are Glint's structured business-document editor. Return JSON only, with exactly source_blocks and translation_blocks.
        Allowed block types: salutation, heading, paragraph, key_points, quote, code, table, signature.
        Never return HTML, Markdown fences, CSS, colors, fonts, sizes, labels such as "Key points", or any visual parameter.

        Create a restrained, highly readable structured-report hierarchy:
        - preserve explicit subject lines, headings, paragraphs, blank-line boundaries, quotations, tables, code and signatures;
        - use salutation for the opening greeting and signature for the real closing/sign-off block;
        - use key_points for existing bullets, numbered steps, requests, decisions, risks, deadlines and action items that should be easy to scan;
        - use heading only when the input already contains a genuine heading or subject-like section; never invent a heading;
        - keep every block in the original order and never invent, summarize, omit, merge or duplicate content.

        For smart mode, preserve every non-whitespace character and its order; only repair Unicode whitespace and structure. In key_points, retain an existing bullet or number marker inside the item text when that marker is part of the input.
        For polish mode, source_blocks still follow smart rules. translation_blocks may improve grammar, wording, tone and readability, but must preserve every person, organization, identifier, number, amount, percentage, date, time, URL, email, IP, path, variable, code token, list fact count and list order.
        Existing correct structure always wins. When uncertain, keep the original text as a paragraph instead of guessing.
        """
        let user = """
        mode: \(mode.rawValue)
        source_text:
        \(sourceText)

        translated_text:
        \(translatedText)

        Required JSON keys: source_blocks, translation_blocks
        """
        return config.buildRequest(
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            maxTokens: 8_000,
            stream: false
        )
    }

    func buildSingleRequest(text: String, mode: TranslationFormattingMode) -> URLRequest? {
        guard mode != .strict else { return nil }
        let system = """
        Return JSON only with exactly one key named blocks. Allowed block types: salutation, heading, paragraph, key_points, quote, code, table, signature. Never return HTML, Markdown fences, CSS, colors, fonts, sizes or decorative labels.
        Build a restrained, readable business-report hierarchy while preserving existing paragraphs, lists, quotes, tables, code and signatures in order. Use key_points only for real bullets, numbered steps, requests, decisions, risks, deadlines or action items. Use heading only for a genuine existing heading. Never invent, summarize, omit, merge or duplicate content.
        Smart mode may only change Unicode whitespace and must preserve each non-whitespace character in order; keep existing list markers inside key_points items. Polish mode may improve language while preserving every factual token, list fact count and list order. When uncertain, keep a paragraph.
        """
        return config.buildRequest(
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": "mode: \(mode.rawValue)\ntext:\n\(text)"]
            ],
            maxTokens: 6_000,
            stream: false
        )
    }

    func parseAutomaticResponse(data: Data) -> TranslationAIAutomaticResult? {
        guard let content = config.parseResponse(data: data),
              let object = Self.parseJSONObject(content),
              Set(object.keys) == Set(["source_blocks", "translation_blocks"]),
              let sourceObjects = object["source_blocks"] as? [[String: Any]],
              let translationObjects = object["translation_blocks"] as? [[String: Any]],
              let source = Self.parseBlocks(sourceObjects),
              let translation = Self.parseBlocks(translationObjects),
              !source.isEmpty, !translation.isEmpty else { return nil }
        return TranslationAIAutomaticResult(sourceBlocks: source, translationBlocks: translation)
    }

    func parseSingleResponse(data: Data) -> [TranslationBlock]? {
        guard let content = config.parseResponse(data: data),
              let object = Self.parseJSONObject(content),
              Set(object.keys) == Set(["blocks"]),
              let objects = object["blocks"] as? [[String: Any]],
              let blocks = Self.parseBlocks(objects),
              !blocks.isEmpty else { return nil }
        return blocks
    }

    private static func parseJSONObject(_ content: String) -> [String: Any]? {
        for candidate in jsonObjectCandidates(in: content) {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            return object
        }
        return nil
    }

    private static func jsonObjectCandidates(in content: String) -> [Substring] {
        var candidates: [Substring] = []
        var objectStart: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]
            if objectStart == nil {
                if character == "{" {
                    objectStart = index
                    depth = 1
                    isInsideString = false
                    isEscaped = false
                }
                index = content.index(after: index)
                continue
            }

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                switch character {
                case "\"":
                    isInsideString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0, let start = objectStart {
                        let end = content.index(after: index)
                        candidates.append(content[start..<end])
                        objectStart = nil
                    }
                default:
                    break
                }
            }
            index = content.index(after: index)
        }
        return candidates
    }

    private static func parseBlocks(_ objects: [[String: Any]]) -> [TranslationBlock]? {
        var blocks: [TranslationBlock] = []
        for object in objects {
            guard let type = object["type"] as? String else { return nil }
            switch type {
            case "key_points":
                guard Set(object.keys) == Set(["type", "items"]),
                      let items = object["items"] as? [String],
                      !items.isEmpty,
                      items.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
                blocks.append(.keyPoints(items))
            case "salutation", "heading", "paragraph", "quote", "code", "table", "signature":
                guard Set(object.keys) == Set(["type", "text"]),
                      let text = object["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                switch type {
                case "salutation": blocks.append(.salutation(text))
                case "heading": blocks.append(.heading(text))
                case "paragraph": blocks.append(.paragraph(text))
                case "quote": blocks.append(.quote(text))
                case "code": blocks.append(.code(text))
                case "table": blocks.append(.table(text))
                default: blocks.append(.signature(text))
                }
            default:
                return nil
            }
        }
        return blocks
    }

}

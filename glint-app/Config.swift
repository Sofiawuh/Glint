import Foundation

// ============================================================
// 配置模型与多协议适配层 (OpenAI / Anthropic / Gemini Compatible)
// 持久化到 ~/.config/glint/config.json。
// ============================================================

let kConfigDir = (("~/.config/glint" as NSString).expandingTildeInPath)
let kLogPath = kConfigDir + "/glint.log"

enum APIFormat: String, Codable, CaseIterable, Equatable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"

    // 新增自定义服务商时开放全部三种协议格式
    static var customSelectableCases: [APIFormat] {
        [.openai, .anthropic, .gemini]
    }

    var displayName: String {
        switch self {
        case .openai:    return "OpenAI 兼容 (/chat/completions)"
        case .anthropic: return "Anthropic 兼容 (/v1/messages)"
        case .gemini:    return "Gemini 兼容 (/v1beta/models)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini:    return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModelPlaceholder: String {
        switch self {
        case .openai:    return "deepseek-chat / mimo-v2.5 / gpt-4o"
        case .anthropic: return "claude-sonnet-4-5"
        case .gemini:    return "gemini-3.8-flash"
        }
    }
}

enum StreamEvent: Equatable {
    case ignore
    case delta(String)
    case done
    case error(String)
}

private enum AzureErrorFormatter {
    static func sanitized(_ value: String, secrets: [String]) -> String {
        var result = value
        for secret in secrets {
            let clean = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                result = result.replacingOccurrences(of: clean, with: "[已隐藏]", options: [.caseInsensitive])
            }
        }
        return result
    }

    static func message(statusCode: Int, data: Data?, service: String, secrets: [String]) -> String {
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            let code: String
            if let stringCode = error["code"] as? String {
                code = stringCode
            } else if let numberCode = error["code"] as? NSNumber {
                code = numberCode.stringValue
            } else {
                code = "HTTP \(statusCode)"
            }
            let detail = error["message"] as? String ?? "请求失败"
            return sanitized("\(service) 出错（\(code)）：\(detail)", secrets: secrets)
        }
        return "\(service) 出错（HTTP \(statusCode)），请检查 Endpoint、Key、区域或服务状态"
    }
}

struct AzureTranslatorConfig: Codable, Equatable {
    var endpoint: String
    var apiKey: String
    var region: String

    init(endpoint: String = "https://api.cognitive.microsofttranslator.com", apiKey: String = "", region: String = "") {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.region = region
    }

    static func targetLanguage(for text: String) -> String {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
                return "en"
            default:
                continue
            }
        }
        return "zh-Hans"
    }

    private func translateURL(target: String) -> URL? {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/translate") { base += "/translate" }
        guard var components = URLComponents(string: base),
              components.scheme?.lowercased() == "https",
              components.host != nil else { return nil }
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: target)
        ]
        return components.url
    }

    func buildRequest(text: String) -> URLRequest? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty,
              let url = translateURL(target: Self.targetLanguage(for: text)) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanRegion.isEmpty {
            request.setValue(cleanRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [["Text": text]])
        return request
    }

    func buildProbeRequest() -> URLRequest? {
        buildRequest(text: "test")
    }

    func parseResponse(data: Data) -> String? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = items.first,
              let translations = first["translations"] as? [[String: Any]],
              let text = translations.first?["text"] as? String,
              !text.isEmpty else { return nil }
        return text
    }

    func parseError(statusCode: Int, data: Data?) -> String {
        AzureErrorFormatter.message(
            statusCode: statusCode,
            data: data,
            service: "Azure Translator",
            secrets: [apiKey]
        )
    }
}

struct AzureOpenAIConfig: Codable, Equatable {
    var endpoint: String
    var apiKey: String
    var deploymentName: String
    var supportsVision: Bool

    init(endpoint: String = "", apiKey: String = "", deploymentName: String = "", supportsVision: Bool = false) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.deploymentName = deploymentName
        self.supportsVision = supportsVision
    }

    private var chatCompletionsURL: URL? {
        var base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
        guard let url = URL(string: base),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }

    func buildRequest(
        messages: [[String: Any]],
        maxTokens: Int,
        stream: Bool
    ) -> URLRequest? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDeployment = deploymentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanDeployment.isEmpty, let url = chatCompletionsURL else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = stream ? 60 : 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "api-key")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        let body: [String: Any] = [
            "model": cleanDeployment,
            "messages": messages,
            "max_completion_tokens": maxTokens,
            "stream": stream
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    func buildProbeRequest() -> URLRequest? {
        buildRequest(
            messages: [["role": "user", "content": "Reply with OK."]],
            maxTokens: 8,
            stream: false
        )
    }

    func parseResponse(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else { return nil }
        return content
    }

    func parseStreamLine(_ line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(":") || trimmed.hasPrefix("event:") { return .ignore }
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .ignore }
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? String ?? "stream_error"
            let detail = error["message"] as? String ?? "流式请求失败"
            return .error(AzureErrorFormatter.sanitized("\(code)：\(detail)", secrets: [apiKey]))
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else { return .ignore }
        return .delta(content)
    }

    func parseError(statusCode: Int, data: Data?) -> String {
        AzureErrorFormatter.message(
            statusCode: statusCode,
            data: data,
            service: "Azure GPT",
            secrets: [apiKey]
        )
    }
}

struct Provider: Codable, Equatable {
    var name: String
    var format: APIFormat
    var baseURL: String
    var apiKey: String
    var model: String
    var vision: Bool

    init(
        name: String,
        format: APIFormat = .openai,
        baseURL: String,
        apiKey: String,
        model: String,
        vision: Bool
    ) {
        self.name = name
        self.format = format
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.vision = vision
    }

    enum CodingKeys: String, CodingKey {
        case name, format, baseURL, apiKey, model, vision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.baseURL = try c.decode(String.self, forKey: .baseURL)
        self.apiKey = try c.decode(String.self, forKey: .apiKey)
        self.model = try c.decode(String.self, forKey: .model)
        self.vision = try c.decode(Bool.self, forKey: .vision)
        self.format = (try? c.decode(APIFormat.self, forKey: .format)) ?? .openai
    }

    // 兼容旧属性名
    var chatURL: String { endpointURL(stream: false) }

    func endpointURL(stream: Bool = false) -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }

        let urlPath = URL(string: base)?.path ?? ""
        let hasOnlyRootPath = urlPath.isEmpty || urlPath == "/"

        switch format {
        case .openai:
            if base.hasSuffix("/chat/completions") { return base }
            if hasOnlyRootPath { return base + "/v1/chat/completions" }
            return base + "/chat/completions"

        case .anthropic:
            if base.hasSuffix("/messages") { return base }
            if hasOnlyRootPath { return base + "/v1/messages" }
            return base + "/messages"

        case .gemini:
            if base.contains("/models/") {
                var normalized = base
                if let colonRange = normalized.range(of: ":generateContent") ?? normalized.range(of: ":streamGenerateContent") {
                    normalized = String(normalized[..<colonRange.lowerBound])
                }
                return stream ? "\(normalized):streamGenerateContent?alt=sse" : "\(normalized):generateContent"
            }

            let vBase: String
            if base.contains("aiplatform.googleapis.com") {
                if hasOnlyRootPath {
                    vBase = base + "/v1/publishers/google"
                } else if !base.contains("/publishers/") {
                    vBase = base + "/publishers/google"
                } else {
                    vBase = base
                }
            } else {
                vBase = hasOnlyRootPath ? (base + "/v1beta") : base
            }
            let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelPath: String
            if cleanModel.hasPrefix("publishers/google/models/") && vBase.hasSuffix("/publishers/google") {
                modelPath = String(cleanModel.dropFirst("publishers/google/".count))
            } else if cleanModel.hasPrefix("models/") {
                modelPath = cleanModel
            } else {
                modelPath = "models/\(cleanModel)"
            }
            if stream {
                return "\(vBase)/\(modelPath):streamGenerateContent?alt=sse"
            } else {
                return "\(vBase)/\(modelPath):generateContent"
            }
        }
    }

    private static func parseDataURL(_ dataURL: String) -> (mimeType: String, base64Data: String)? {
        guard dataURL.hasPrefix("data:"),
              let commaIdx = dataURL.firstIndex(of: ",") else { return nil }
        let meta = String(dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<commaIdx])
        let b64 = String(dataURL[dataURL.index(after: commaIdx)...])
        let mime = meta.components(separatedBy: ";").first ?? "image/png"
        guard !b64.isEmpty else { return nil }
        return (mime.isEmpty ? "image/png" : mime, b64)
    }

    func buildRequest(
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int,
        stream: Bool
    ) -> URLRequest? {
        guard let url = URL(string: endpointURL(stream: stream)) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        req.timeoutInterval = stream ? 60 : 30

        let body: [String: Any]
        switch format {
        case .openai:
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "max_completion_tokens": maxTokens,
                "thinking": ["type": "disabled"],
                "stream": stream
            ]

        case .anthropic:
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            var systemPrompts: [String] = []
            var antMessages: [[String: Any]] = []

            for m in messages {
                guard let role = m["role"] as? String else { continue }
                if role == "system" {
                    if let s = m["content"] as? String, !s.isEmpty {
                        systemPrompts.append(s)
                    }
                    continue
                }
                if let textContent = m["content"] as? String {
                    antMessages.append(["role": role, "content": textContent])
                } else if let blocks = m["content"] as? [[String: Any]] {
                    var converted: [[String: Any]] = []
                    for b in blocks {
                        let bType = b["type"] as? String ?? ""
                        if bType == "text", let t = b["text"] as? String {
                            converted.append(["type": "text", "text": t])
                        } else if bType == "image_url",
                                  let imgObj = b["image_url"] as? [String: Any],
                                  let urlStr = imgObj["url"] as? String,
                                  let parsed = Provider.parseDataURL(urlStr) {
                            converted.append([
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": parsed.mimeType,
                                    "data": parsed.base64Data
                                ]
                            ])
                        }
                    }
                    antMessages.append(["role": role, "content": converted])
                }
            }

            var b: [String: Any] = [
                "model": model,
                "messages": antMessages,
                "max_tokens": maxTokens,
                "temperature": temperature,
                "stream": stream
            ]
            if !systemPrompts.isEmpty {
                b["system"] = systemPrompts.joined(separator: "\n\n")
            }
            body = b

        case .gemini:
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.lowercased().hasPrefix("bearer ") {
                let token = String(trimmedKey.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else if trimmedKey.hasPrefix("ya29.") {
                req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            } else {
                req.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            }

            var systemPrompts: [String] = []
            var contents: [[String: Any]] = []

            for m in messages {
                guard let role = m["role"] as? String else { continue }
                if role == "system" {
                    if let s = m["content"] as? String, !s.isEmpty {
                        systemPrompts.append(s)
                    }
                    continue
                }
                let gemRole = (role == "assistant") ? "model" : "user"
                if let textContent = m["content"] as? String {
                    contents.append([
                        "role": gemRole,
                        "parts": [["text": textContent]]
                    ])
                } else if let blocks = m["content"] as? [[String: Any]] {
                    var parts: [[String: Any]] = []
                    for b in blocks {
                        let bType = b["type"] as? String ?? ""
                        if bType == "text", let t = b["text"] as? String {
                            parts.append(["text": t])
                        } else if bType == "image_url",
                                  let imgObj = b["image_url"] as? [String: Any],
                                  let urlStr = imgObj["url"] as? String,
                                  let parsed = Provider.parseDataURL(urlStr) {
                            parts.append([
                                "inline_data": [
                                    "mime_type": parsed.mimeType,
                                    "data": parsed.base64Data
                                ]
                            ])
                        }
                    }
                    contents.append([
                        "role": gemRole,
                        "parts": parts
                    ])
                }
            }

            var b: [String: Any] = [
                "contents": contents,
                "generationConfig": [
                    "temperature": temperature,
                    "maxOutputTokens": maxTokens
                ]
            ]
            if !systemPrompts.isEmpty {
                b["systemInstruction"] = [
                    "parts": [["text": systemPrompts.joined(separator: "\n\n")]]
                ]
            }
            body = b
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        return req
    }

    func parseResponse(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        switch format {
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let content = msg["content"] as? String else { return nil }
            return content

        case .anthropic:
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            var accum = ""
            for block in content {
                if (block["type"] as? String) == "text", let t = block["text"] as? String {
                    accum += t
                }
            }
            return accum.isEmpty ? nil : accum

        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            var accum = ""
            for part in parts {
                if (part["thought"] as? Bool) == true { continue }
                if let t = part["text"] as? String {
                    accum += t
                }
            }
            return accum.isEmpty ? nil : accum
        }
    }

    func parseStreamLine(_ line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(":") || trimmed.hasPrefix("event:") {
            return .ignore
        }
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let d = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return .ignore
        }

        if let errObj = json["error"] as? [String: Any],
           let msg = errObj["message"] as? String, !msg.isEmpty {
            return .error(msg)
        }

        switch format {
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let piece = delta["content"] as? String, !piece.isEmpty else {
                return .ignore
            }
            return .delta(piece)

        case .anthropic:
            let evType = json["type"] as? String ?? ""
            if evType == "message_stop" { return .done }
            if evType == "error" {
                let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Anthropic 流式请求出错"
                return .error(msg)
            }
            if evType == "content_block_delta",
               let delta = json["delta"] as? [String: Any] {
                let dType = delta["type"] as? String ?? ""
                if (dType == "text_delta" || dType.isEmpty),
                   let piece = delta["text"] as? String, !piece.isEmpty {
                    return .delta(piece)
                }
            }
            return .ignore

        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                return .ignore
            }
            var accum = ""
            for part in parts {
                if (part["thought"] as? Bool) == true { continue }
                if let t = part["text"] as? String {
                    accum += t
                }
            }
            return accum.isEmpty ? .ignore : .delta(accum)
        }
    }
}

struct SupportedLanguage: Equatable {
    let code: String
    let displayName: String
}

final class LegacyAppConfig {
    static let shared = LegacyAppConfig()
    static let languagePlaceholder = "<languages>"
    static let defaultLanguage = "Simplified Chinese"

    static let supportedLanguages: [SupportedLanguage] = [
        SupportedLanguage(code: "Simplified Chinese", displayName: "简体中文 (Simplified Chinese)"),
        SupportedLanguage(code: "Traditional Chinese", displayName: "繁體中文 (Traditional Chinese)"),
        SupportedLanguage(code: "English", displayName: "英语 (English)"),
        SupportedLanguage(code: "Japanese", displayName: "日语 (Japanese)"),
        SupportedLanguage(code: "Korean", displayName: "韩语 (Korean)"),
        SupportedLanguage(code: "Russian", displayName: "俄语 (Russian)"),
        SupportedLanguage(code: "French", displayName: "法语 (French)"),
        SupportedLanguage(code: "German", displayName: "德语 (German)"),
        SupportedLanguage(code: "Spanish", displayName: "西班牙语 (Spanish)"),
        SupportedLanguage(code: "Portuguese", displayName: "葡萄牙语 (Portuguese)"),
        SupportedLanguage(code: "Arabic", displayName: "阿拉伯语 (Arabic)")
    ]

    static let defaultTranslatePrompt = "You are a professional translation engine. Translate the user's text into <languages>. Output ONLY the translation itself — no explanations, no quotes, no extra words."

    static func resolvePrompt(_ prompt: String, language: String) -> String {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultLanguage : language
        return prompt.replacingOccurrences(of: languagePlaceholder, with: lang)
    }

    private(set) var providers: [Provider] = []
    private(set) var activeName: String = ""
    private(set) var language: String = LegacyAppConfig.defaultLanguage
    private(set) var translatePrompt: String = LegacyAppConfig.defaultTranslatePrompt
    private var path: String { kConfigDir + "/config.json" }

    var resolvedTranslatePrompt: String {
        LegacyAppConfig.resolvePrompt(translatePrompt, language: language)
    }

    // 当前厂商:按名字找;找不到回退第一条(永不为 nil,只要至少一条)
    var active: Provider? { providers.first { $0.name == activeName } ?? providers.first }

    private struct Stored: Codable {
        var active: String
        var providers: [Provider]
        var language: String?
        var translatePrompt: String?
    }

    // 官方支持的四大预置厂商: DeepSeek、Gemini、Vertex AI、MiMo
    static func presets() -> [Provider] {
        [
            Provider(
                name: "DeepSeek",
                format: .openai,
                baseURL: "https://api.deepseek.com/v1",
                apiKey: "",
                model: "deepseek-chat",
                vision: false
            ),
            Provider(
                name: "Gemini",
                format: .gemini,
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKey: "",
                model: "gemini-3.8-flash",
                vision: true
            ),
            Provider(
                name: "Vertex AI",
                format: .gemini,
                baseURL: "https://aiplatform.googleapis.com/v1/publishers/google",
                apiKey: "",
                model: "gemini-3.8-flash",
                vision: true
            ),
            Provider(
                name: "MiMo",
                format: .openai,
                baseURL: "https://api.xiaomimimo.com/v1",
                apiKey: "",
                model: "mimo-v2.5",
                vision: true
            )
        ]
    }

    // 查询是否为官方内置预设平台
    static func officialPreset(named name: String) -> Provider? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return presets().first { $0.name.lowercased() == trimmed }
    }

    static func isOfficialPreset(_ name: String) -> Bool {
        officialPreset(named: name) != nil
    }

    // 保留用户已有厂商配置(含自定义 API Key / 模型名),并自动补齐缺失的官方预置厂商
    static func mergeOfficialPresets(into existing: [Provider]) -> [Provider] {
        var result = existing.map { item -> Provider in
            if let preset = officialPreset(named: item.name) {
                return Provider(
                    name: preset.name,
                    format: preset.format,
                    baseURL: preset.baseURL,
                    apiKey: item.apiKey,
                    model: item.model.isEmpty ? preset.model : item.model,
                    vision: item.vision
                )
            }
            return item
        }
        for preset in presets() {
            let exists = result.contains { $0.name.lowercased() == preset.name.lowercased() }
            if !exists {
                result.append(preset)
            }
        }
        return result
    }

    // 启动调用一次。无文件/损坏 → 使用官方预置初始化并落盘;有文件 → 自动补齐新增官方预置与默认字段
    func load() {
        let fm = FileManager.default
        if let data = fm.contents(atPath: path),
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           !stored.providers.isEmpty {
            let merged = LegacyAppConfig.mergeOfficialPresets(into: stored.providers)
            providers = merged
            activeName = stored.active
            let rawLang = stored.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            language = rawLang.isEmpty ? LegacyAppConfig.defaultLanguage : rawLang
            let rawTrans = stored.translatePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            translatePrompt = rawTrans.isEmpty ? LegacyAppConfig.defaultTranslatePrompt : (stored.translatePrompt ?? LegacyAppConfig.defaultTranslatePrompt)
            if merged != stored.providers || stored.language == nil || stored.translatePrompt == nil {
                save()
            }
            return
        }
        providers = LegacyAppConfig.presets()
        activeName = "MiMo"
        language = LegacyAppConfig.defaultLanguage
        translatePrompt = LegacyAppConfig.defaultTranslatePrompt
        save()
    }

    @discardableResult
    func save() -> Bool {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = Stored(
            active: activeName,
            providers: providers,
            language: language,
            translatePrompt: translatePrompt
        )
        guard let data = try? enc.encode(payload) else { return false }
        try? FileManager.default.createDirectory(atPath: kConfigDir, withIntermediateDirectories: true, attributes: nil)
        do { try data.write(to: URL(fileURLWithPath: path), options: .atomic); return true }
        catch { return false }
    }

    // 落盘失败时回滚内存,保证内存与文件一致(避免「界面显示已保存、实际丢了」)
    @discardableResult
    func setProviders(_ ps: [Provider], active: String) -> Bool {
        let oldP = providers, oldA = activeName
        providers = ps
        activeName = active
        if save() { return true }
        providers = oldP; activeName = oldA
        return false
    }

    @discardableResult
    func setLanguageAndTranslatePrompt(language newLang: String, translatePrompt newTrans: String) -> Bool {
        let oldL = language, oldT = translatePrompt
        let cleanL = newLang.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanT = newTrans.trimmingCharacters(in: .whitespacesAndNewlines)
        language = cleanL.isEmpty ? LegacyAppConfig.defaultLanguage : cleanL
        translatePrompt = cleanT.isEmpty ? LegacyAppConfig.defaultTranslatePrompt : newTrans
        if save() { return true }
        language = oldL; translatePrompt = oldT
        return false
    }
}

final class AppConfig: Codable {
    static let shared = AppConfig()

    var translator: AzureTranslatorConfig
    var azureOpenAI: AzureOpenAIConfig
    var screenshotHotKey: ScreenshotHotKey
    var textCommandHotKey: TextCommandHotKey

    private enum CodingKeys: String, CodingKey {
        case translator
        case azureOpenAI
        case screenshotHotKey
        case textCommandHotKey
    }

    private static var defaultURL: URL {
        URL(fileURLWithPath: kConfigDir).appendingPathComponent("config.json")
    }

    init(
        translator: AzureTranslatorConfig = AzureTranslatorConfig(),
        azureOpenAI: AzureOpenAIConfig = AzureOpenAIConfig(),
        screenshotHotKey: ScreenshotHotKey = .default,
        textCommandHotKey: TextCommandHotKey = .default
    ) {
        self.translator = translator
        self.azureOpenAI = azureOpenAI
        self.screenshotHotKey = screenshotHotKey
        self.textCommandHotKey = textCommandHotKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translator = try container.decode(AzureTranslatorConfig.self, forKey: .translator)
        azureOpenAI = try container.decode(AzureOpenAIConfig.self, forKey: .azureOpenAI)
        screenshotHotKey = try container.decodeIfPresent(ScreenshotHotKey.self, forKey: .screenshotHotKey) ?? .default
        textCommandHotKey = try container.decodeIfPresent(TextCommandHotKey.self, forKey: .textCommandHotKey) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(translator, forKey: .translator)
        try container.encode(azureOpenAI, forKey: .azureOpenAI)
        try container.encode(screenshotHotKey, forKey: .screenshotHotKey)
        try container.encode(textCommandHotKey, forKey: .textCommandHotKey)
    }

    func load() {
        let loaded = Self.loadOrCreate(at: Self.defaultURL)
        translator = loaded.translator
        azureOpenAI = loaded.azureOpenAI
        screenshotHotKey = loaded.screenshotHotKey
        textCommandHotKey = loaded.textCommandHotKey
    }

    @discardableResult
    func save() -> Bool {
        save(to: Self.defaultURL)
    }

    @discardableResult
    func save(to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(from url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    static func loadOrCreate(at url: URL) -> AppConfig {
        if let loaded = load(from: url) { return loaded }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("config.pre-azure-backup.json")
            if !fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.copyItem(at: url, to: backupURL)
            }
        }

        let defaults = AppConfig()
        _ = defaults.save(to: url)
        return defaults
    }

    @discardableResult
    func setAzureServices(translator newTranslator: AzureTranslatorConfig, azureOpenAI newAzureOpenAI: AzureOpenAIConfig) -> Bool {
        let oldTranslator = translator
        let oldAzureOpenAI = azureOpenAI
        translator = newTranslator
        azureOpenAI = newAzureOpenAI
        if save() { return true }
        translator = oldTranslator
        azureOpenAI = oldAzureOpenAI
        return false
    }

    @discardableResult
    func setScreenshotHotKey(_ newHotKey: ScreenshotHotKey) -> Bool {
        let oldHotKey = screenshotHotKey
        screenshotHotKey = newHotKey
        if save() { return true }
        screenshotHotKey = oldHotKey
        return false
    }

    @discardableResult
    func setTextCommandHotKey(_ newHotKey: TextCommandHotKey) -> Bool {
        let oldHotKey = textCommandHotKey
        textCommandHotKey = newHotKey
        if save() { return true }
        textCommandHotKey = oldHotKey
        return false
    }
}

enum PromptContextPayload: Equatable {
    case text(String)
    case imageDataURL(String)
}

struct ConversationTurn: Equatable {
    let role: String
    let content: String

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

enum PromptContextBuilder {
    static func canSubmitPrompt(_ rawPrompt: String) -> Bool {
        !rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func previewSnippet(for selectedText: String, maxLines: Int = 3, maxChars: Int = 180) -> String {
        let normalized = selectedText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        let safeMaxLines = max(1, maxLines)
        let safeMaxChars = max(1, maxChars)
        let allLines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !allLines.isEmpty else { return "" }

        var truncated = allLines.count > safeMaxLines
        var joined = allLines.prefix(safeMaxLines).joined(separator: "\n")
        if joined.count > safeMaxChars {
            truncated = true
            let keepCount = max(1, safeMaxChars - 1)
            joined = String(joined.prefix(keepCount)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return truncated ? (joined + "…") : joined
    }

    static func formatTextWithPrompt(contextText: String, userPrompt: String) -> String {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return "<context>\n\(contextText)\n</context>\n\n\(prompt)"
    }

    static func buildMessages(context: PromptContextPayload, turns: [ConversationTurn]) -> [[String: Any]] {
        guard !turns.isEmpty else { return [] }
        var messages: [[String: Any]] = []
        for (i, turn) in turns.enumerated() {
            if i == 0 && turn.role == "user" {
                switch context {
                case .text(let ctxText):
                    messages.append([
                        "role": "user",
                        "content": formatTextWithPrompt(contextText: ctxText, userPrompt: turn.content)
                    ])
                case .imageDataURL(let dataURL):
                    let prompt = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parts: [[String: Any]] = [
                        ["type": "image_url", "image_url": ["url": dataURL]],
                        ["type": "text", "text": prompt]
                    ]
                    messages.append(["role": "user", "content": parts])
                }
            } else {
                messages.append(["role": turn.role, "content": turn.content])
            }
        }
        return messages
    }
}

enum LaunchAtLogin {
    static let defaultPlistPath = ("~/Library/LaunchAgents/com.yoryon.glint.plist" as NSString).expandingTildeInPath
    static let defaultExecutablePath = "/Applications/Glint.app/Contents/MacOS/Glint"
    static let label = "com.yoryon.glint"

    static func isEnabled(plistPath: String = defaultPlistPath) -> Bool {
        guard FileManager.default.fileExists(atPath: plistPath),
              let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
              (dict["RunAtLoad"] as? Bool) == true else {
            return false
        }
        return true
    }

    @discardableResult
    static func setEnabled(
        _ enabled: Bool,
        plistPath: String = defaultPlistPath,
        executablePath: String = defaultExecutablePath
    ) -> Bool {
        let fm = FileManager.default
        if enabled {
            let parent = (plistPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
                return false
            }
            do {
                try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            if fm.fileExists(atPath: plistPath) {
                do {
                    try fm.removeItem(atPath: plistPath)
                    return true
                } catch {
                    return false
                }
            }
            return true
        }
    }
}

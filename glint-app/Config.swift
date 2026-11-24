import Foundation

enum AzureAPIKeySlot: String, CaseIterable, Hashable {
    case translator
    case openAI
    case speech
}

struct AzureKeychainClient {
    let read: (AzureAPIKeySlot) -> String?
    let write: (String, AzureAPIKeySlot) -> Bool

    static let unavailable = AzureKeychainClient(
        read: { _ in nil },
        write: { _, _ in false }
    )
}

// ============================================================
// Azure 专用配置与请求适配层。
// 非敏感配置持久化到 ~/.config/glint/config.json，API Key 仅存 Keychain。
// ============================================================

let kConfigDir: String = {
    if let override = ProcessInfo.processInfo.environment["GLINT_CONFIG_DIR"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        return (override as NSString).expandingTildeInPath
    }
    return (("~/.config/glint" as NSString).expandingTildeInPath)
}()
let kLogPath = kConfigDir + "/glint.log"

enum StreamEvent: Equatable {
    case ignore
    case delta(String)
    case done
    case error(String)
}

struct TranslationPreferences: Codable, Equatable {
    var targetMode: TranslationTargetMode
    var fixedTargetLanguage: String
    var formattingMode: TranslationFormattingMode

    init(
        targetMode: TranslationTargetMode = .automatic,
        fixedTargetLanguage: String = "zh-Hans",
        formattingMode: TranslationFormattingMode = .smart
    ) {
        self.targetMode = targetMode
        self.fixedTargetLanguage = fixedTargetLanguage
        self.formattingMode = formattingMode
    }

    func targetLanguage(for text: String) -> String {
        targetMode == .fixed
            ? fixedTargetLanguage
            : AzureTranslatorConfig.targetLanguage(for: text)
    }
}

private enum AzureErrorFormatter {
    static func sanitized(_ value: String, secrets: [String]) -> String {
        var result = value
        let cleanSecrets = secrets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for secret in cleanSecrets {
            result = result.replacingOccurrences(of: secret, with: "[已隐藏]", options: [.caseInsensitive])
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
        buildRequest(text: text, targetLanguage: Self.targetLanguage(for: text))
    }

    func buildRequest(text: String, targetLanguage: String) -> URLRequest? {
        buildRequest(
            fragments: [TranslationFragment(id: "fragment-0000", text: text)],
            targetLanguage: targetLanguage
        )
    }

    func buildRequest(fragments: [TranslationFragment], targetLanguage: String) -> URLRequest? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTarget = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanTarget.isEmpty, !fragments.isEmpty,
              fragments.count <= TranslationBatchLimits.azureDefault.maxItems,
              fragments.reduce(0, { $0 + $1.text.count }) <= TranslationBatchLimits.azureDefault.maxCharacters,
              let url = translateURL(target: cleanTarget) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanRegion.isEmpty {
            request.setValue(cleanRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: fragments.map { ["Text": $0.text] }
        )
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

    func parseFragmentResponses(
        data: Data,
        fragments: [TranslationFragment]
    ) -> [TranslationFragmentResponse]? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              items.count == fragments.count else { return nil }
        var responses: [TranslationFragmentResponse] = []
        responses.reserveCapacity(fragments.count)
        for (index, item) in items.enumerated() {
            guard let translations = item["translations"] as? [[String: Any]],
                  let translatedText = translations.first?["text"] as? String else { return nil }
            let detectedLanguage = (item["detectedLanguage"] as? [String: Any])?["language"] as? String
            responses.append(TranslationFragmentResponse(
                id: fragments[index].id,
                translatedText: translatedText,
                detectedLanguage: detectedLanguage
            ))
        }
        return responses
    }

    func parseError(statusCode: Int, data: Data?) -> String {
        return AzureErrorFormatter.message(
            statusCode: statusCode,
            data: data,
            service: "Azure Translator",
            secrets: [apiKey]
        )
    }
}

struct AzureSpeechConfig: Codable, Equatable {
    static let automaticVoice = "auto"

    var endpoint: String
    var apiKey: String
    var voice: String { Self.automaticVoice }

    init(endpoint: String = "", apiKey: String = "", voice: String = AzureSpeechConfig.automaticVoice) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        _ = voice // 兼容旧调用；新版始终按语言自动选 Voice。
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint
        case apiKey
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case endpoint
        case apiKey
        case region
        case voice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        // region / voice 只为兼容旧 JSON 解码，升级后不再作为用户配置。
        _ = try container.decodeIfPresent(String.self, forKey: .region)
        _ = try container.decodeIfPresent(String.self, forKey: .voice)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(apiKey, forKey: .apiKey)
    }

    func voiceName(for languageCode: String) -> String {
        let code = languageCode.lowercased()
        if code.hasPrefix("zh-hant") || code.hasPrefix("zh-tw") { return "zh-TW-HsiaoChenNeural" }
        if code.hasPrefix("zh") { return "zh-CN-XiaoxiaoNeural" }
        if code.hasPrefix("ja") { return "ja-JP-NanamiNeural" }
        if code.hasPrefix("ko") { return "ko-KR-SunHiNeural" }
        if code.hasPrefix("fr") { return "fr-FR-DeniseNeural" }
        if code.hasPrefix("de") { return "de-DE-KatjaNeural" }
        if code.hasPrefix("es") { return "es-ES-ElviraNeural" }
        if code.hasPrefix("pt") { return "pt-BR-FranciscaNeural" }
        return "en-US-JennyNeural"
    }

    func locale(for languageCode: String) -> String {
        String(voiceName(for: languageCode).split(separator: "-").prefix(2).joined(separator: "-"))
    }

    func buildSynthesisRequest(text: String, languageCode: String) -> URLRequest? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, let url = runtimeSynthesisURL else { return nil }
        let voiceName = voiceName(for: languageCode)
        guard Self.isValidVoiceName(voiceName) else { return nil }
        let locale = locale(for: languageCode)
        let escaped = Self.escapeXML(SpeechTextFormatter.speechText(from: text))
            .replacingOccurrences(of: "\n\n", with: "<break time=\"700ms\"/>")
            .replacingOccurrences(of: "\n", with: "<break time=\"350ms\"/>")
        let ssml = "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"\(locale)\"><voice name=\"\(voiceName)\">\(escaped)</voice></speak>"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(cleanKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("Glint", forHTTPHeaderField: "User-Agent")
        request.httpBody = ssml.data(using: .utf8)
        return request
    }

    func buildProbeRequest() -> URLRequest? {
        buildSynthesisRequest(text: "Speech connection test.", languageCode: "en")
    }

    var inputValidationMessage: String? {
        if endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写 Speech Endpoint"
        }
        if runtimeSynthesisURL == nil {
            return "Speech Endpoint 格式不正确，无法识别 Azure 区域"
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写 Speech API Key"
        }
        return nil
    }

    func parseError(statusCode: Int, data: Data?) -> String {
        if statusCode == 401 || statusCode == 403 {
            return "Speech Key 无效或资源区域不匹配"
        }
        if statusCode == 400 {
            return "自动选择的语音在当前区域不可用"
        }
        return AzureErrorFormatter.message(
            statusCode: statusCode,
            data: data,
            service: "Azure Speech",
            secrets: sanitizedSecrets
        )
    }

    func parseNetworkError(_ error: Error) -> String {
        AzureErrorFormatter.sanitized(error.localizedDescription, secrets: sanitizedSecrets)
    }

    private var sanitizedSecrets: [String] {
        var values = [apiKey, endpoint]
        if let components = URLComponents(string: endpoint) {
            if let query = components.query, !query.isEmpty {
                values.append(query)
                values.append("?" + query)
            }
            if let encodedQuery = components.percentEncodedQuery, !encodedQuery.isEmpty {
                values.append(encodedQuery)
                values.append("?" + encodedQuery)
            }
            for item in components.queryItems ?? [] {
                if let value = item.value, !value.isEmpty {
                    values.append(value)
                    values.append("\(item.name)=\(value)")
                }
            }
        }
        return values
    }

    private var runtimeSynthesisURL: URL? {
        let clean = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: clean),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else { return nil }

        if host.hasSuffix(".api.cognitive.microsoft.com") {
            let suffix = ".api.cognitive.microsoft.com"
            let region = String(host.dropLast(suffix.count))
            guard !region.isEmpty,
                  region.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else { return nil }
            components.host = "\(region).tts.speech.microsoft.com"
            components.path = "/cognitiveservices/v1"
            components.query = nil
            components.fragment = nil
            return components.url
        }

        guard host.hasSuffix(".tts.speech.microsoft.com") else { return nil }
        components.path = "/cognitiveservices/v1"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isValidVoiceName(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z]{2,3}-[A-Za-z]{2,4}-[A-Za-z0-9]+Neural$"#,
            options: .regularExpression
        ) != nil
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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

final class AppConfig: Codable {
    static let shared = AppConfig()
    private static var runtimeKeychain = AzureKeychainClient.unavailable

    var translator: AzureTranslatorConfig
    var azureOpenAI: AzureOpenAIConfig
    var screenshotHotKey: ScreenshotHotKey
    var textCommandHotKey: TextCommandHotKey
    var translationPreferences: TranslationPreferences
    var speech: AzureSpeechConfig

    private enum CodingKeys: String, CodingKey {
        case translator
        case azureOpenAI
        case screenshotHotKey
        case textCommandHotKey
        case translationPreferences
        case speech
    }

    private static var defaultURL: URL {
        URL(fileURLWithPath: kConfigDir).appendingPathComponent("config.json")
    }

    private struct PersistedConfig: Codable {
        struct Translator: Codable {
            var endpoint: String
            var region: String
        }

        struct OpenAI: Codable {
            var endpoint: String
            var deploymentName: String
            var supportsVision: Bool
        }

        struct Speech: Codable {
            var endpoint: String
        }

        var translator: Translator
        var azureOpenAI: OpenAI
        var screenshotHotKey: ScreenshotHotKey
        var textCommandHotKey: TextCommandHotKey
        var translationPreferences: TranslationPreferences
        var speech: Speech

        init(_ config: AppConfig) {
            translator = Translator(
                endpoint: config.translator.endpoint,
                region: config.translator.region
            )
            azureOpenAI = OpenAI(
                endpoint: config.azureOpenAI.endpoint,
                deploymentName: config.azureOpenAI.deploymentName,
                supportsVision: config.azureOpenAI.supportsVision
            )
            screenshotHotKey = config.screenshotHotKey
            textCommandHotKey = config.textCommandHotKey
            translationPreferences = config.translationPreferences
            speech = Speech(endpoint: config.speech.endpoint)
        }

        func makeConfig() -> AppConfig {
            AppConfig(
                translator: AzureTranslatorConfig(
                    endpoint: translator.endpoint,
                    apiKey: "",
                    region: translator.region
                ),
                azureOpenAI: AzureOpenAIConfig(
                    endpoint: azureOpenAI.endpoint,
                    apiKey: "",
                    deploymentName: azureOpenAI.deploymentName,
                    supportsVision: azureOpenAI.supportsVision
                ),
                screenshotHotKey: screenshotHotKey,
                textCommandHotKey: textCommandHotKey,
                translationPreferences: translationPreferences,
                speech: AzureSpeechConfig(endpoint: speech.endpoint, apiKey: "")
            )
        }
    }

    init(
        translator: AzureTranslatorConfig = AzureTranslatorConfig(),
        azureOpenAI: AzureOpenAIConfig = AzureOpenAIConfig(),
        screenshotHotKey: ScreenshotHotKey = .default,
        textCommandHotKey: TextCommandHotKey = .default,
        translationPreferences: TranslationPreferences = TranslationPreferences(),
        speech: AzureSpeechConfig = AzureSpeechConfig()
    ) {
        self.translator = translator
        self.azureOpenAI = azureOpenAI
        self.screenshotHotKey = screenshotHotKey
        self.textCommandHotKey = textCommandHotKey
        self.translationPreferences = translationPreferences
        self.speech = speech
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translator = try container.decode(AzureTranslatorConfig.self, forKey: .translator)
        azureOpenAI = try container.decode(AzureOpenAIConfig.self, forKey: .azureOpenAI)
        screenshotHotKey = try container.decodeIfPresent(ScreenshotHotKey.self, forKey: .screenshotHotKey) ?? .default
        textCommandHotKey = try container.decodeIfPresent(TextCommandHotKey.self, forKey: .textCommandHotKey) ?? .default
        translationPreferences = try container.decodeIfPresent(TranslationPreferences.self, forKey: .translationPreferences) ?? TranslationPreferences()
        speech = try container.decodeIfPresent(AzureSpeechConfig.self, forKey: .speech) ?? AzureSpeechConfig()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(translator, forKey: .translator)
        try container.encode(azureOpenAI, forKey: .azureOpenAI)
        try container.encode(screenshotHotKey, forKey: .screenshotHotKey)
        try container.encode(textCommandHotKey, forKey: .textCommandHotKey)
        try container.encode(translationPreferences, forKey: .translationPreferences)
        try container.encode(speech, forKey: .speech)
    }

    func load() {
        let loaded = Self.loadOrCreate(at: Self.defaultURL, keychain: Self.runtimeKeychain)
        translator = loaded.translator
        azureOpenAI = loaded.azureOpenAI
        screenshotHotKey = loaded.screenshotHotKey
        textCommandHotKey = loaded.textCommandHotKey
        translationPreferences = loaded.translationPreferences
        speech = loaded.speech
    }

    @discardableResult
    func save() -> Bool {
        save(to: Self.defaultURL, keychain: Self.runtimeKeychain)
    }

    @discardableResult
    func save(to url: URL) -> Bool {
        save(to: url, keychain: Self.runtimeKeychain)
    }

    static func load(from url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let config = decodeConfig(from: data) else { return nil }
        applyRuntimeKeys(to: config, keychain: runtimeKeychain)
        return config
    }

    static func loadOrCreate(at url: URL) -> AppConfig {
        loadOrCreate(at: url, keychain: runtimeKeychain)
    }

    static func installRuntimeKeychain(_ client: AzureKeychainClient) {
        runtimeKeychain = client
    }

    static func loadOrCreate(
        at url: URL,
        keychain: AzureKeychainClient
    ) -> AppConfig {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let backupURL = directory.appendingPathComponent("config.pre-azure-backup.json")
        let configData = try? Data(contentsOf: url)
        let backupData = try? Data(contentsOf: backupURL)
        let decodedConfig = configData.flatMap(decodeConfig)
        let decodedBackup = backupData.flatMap(decodeConfig)

        guard let loaded = decodedConfig ?? decodedBackup else {
            try? secureDirectory(directory, fileManager: fileManager)
            if let backupData {
                if containsAPIKeyField(backupData) || !isJSONObject(backupData) {
                    _ = writePrivateData(
                        sanitizedLegacyBackupData(from: backupData),
                        to: backupURL,
                        fileManager: fileManager
                    )
                } else {
                    try? secureFile(backupURL, fileManager: fileManager)
                }
            } else if let configData {
                _ = writePrivateData(
                    sanitizedLegacyBackupData(from: configData),
                    to: backupURL,
                    fileManager: fileManager
                )
            }
            let defaults = AppConfig()
            _ = writeSanitized(defaults, to: url, fileManager: fileManager)
            return defaults
        }

        let legacyBackup = decodedBackup
        let keyValues: [(AzureAPIKeySlot, String)] = [
            (.translator, firstNonEmpty(loaded.translator.apiKey, legacyBackup?.translator.apiKey)),
            (.openAI, firstNonEmpty(loaded.azureOpenAI.apiKey, legacyBackup?.azureOpenAI.apiKey)),
            (.speech, firstNonEmpty(loaded.speech.apiKey, legacyBackup?.speech.apiKey))
        ]
        var effective: [AzureAPIKeySlot: String] = [:]
        var pendingWrites: [(AzureAPIKeySlot, String)] = []
        for (slot, legacyValue) in keyValues {
            let existing = keychain.read(slot)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !existing.isEmpty {
                effective[slot] = existing
            } else if !legacyValue.isEmpty {
                effective[slot] = legacyValue
                pendingWrites.append((slot, legacyValue))
            }
        }

        let migrationSucceeded = pendingWrites.allSatisfy { pair in
            keychain.write(pair.1, pair.0)
        }
        applyKeys(effective, to: loaded)
        guard migrationSucceeded else { return loaded }

        let migratedLegacyHotKey = loaded.textCommandHotKey == .legacyDefault
        if loaded.textCommandHotKey == .legacyDefault {
            loaded.textCommandHotKey = .default
        }
        let needsConfigSanitization = decodedConfig == nil || (configData.map(containsAPIKeyField) ?? false)
        let needsBackupSanitization = backupData.map(containsAPIKeyField) ?? false
        if needsConfigSanitization || migratedLegacyHotKey {
            _ = writeSanitized(loaded, to: url, fileManager: fileManager)
        } else {
            try? secureDirectory(directory, fileManager: fileManager)
            try? secureFile(url, fileManager: fileManager)
        }
        if fileManager.fileExists(atPath: backupURL.path) {
            if needsBackupSanitization {
                _ = writeSanitized(loaded, to: backupURL, fileManager: fileManager)
            } else {
                try? secureFile(backupURL, fileManager: fileManager)
            }
        }
        return loaded
    }

    @discardableResult
    private func save(to url: URL, keychain: AzureKeychainClient) -> Bool {
        let credentials: [(AzureAPIKeySlot, String)] = [
            (.translator, translator.apiKey),
            (.openAI, azureOpenAI.apiKey),
            (.speech, speech.apiKey)
        ]
        guard credentials.allSatisfy({ keychain.write($0.1, $0.0) }) else { return false }
        return Self.writeSanitized(self, to: url, fileManager: .default)
    }

    private static func decodeConfig(from data: Data) -> AppConfig? {
        if let legacy = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return legacy
        }
        return (try? JSONDecoder().decode(PersistedConfig.self, from: data))?.makeConfig()
    }

    private static func applyRuntimeKeys(
        to config: AppConfig,
        keychain: AzureKeychainClient
    ) {
        var values: [AzureAPIKeySlot: String] = [:]
        for slot in AzureAPIKeySlot.allCases {
            if let value = keychain.read(slot), !value.isEmpty {
                values[slot] = value
            }
        }
        applyKeys(values, to: config)
    }

    private static func applyKeys(
        _ values: [AzureAPIKeySlot: String],
        to config: AppConfig
    ) {
        if let value = values[.translator] { config.translator.apiKey = value }
        if let value = values[.openAI] { config.azureOpenAI.apiKey = value }
        if let value = values[.speech] { config.speech.apiKey = value }
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private static func containsAPIKeyField(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return containsAPIKeyField(object)
    }

    private static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func containsAPIKeyField(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.lowercased().filter(\.isLetter)
                if normalized == "apikey" || normalized == "azureapikey" { return true }
                if containsAPIKeyField(child) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsAPIKeyField)
        }
        return false
    }

    private static func sanitizedLegacyBackupData(from data: Data) -> Data {
        let object: Any
        if let decoded = try? JSONSerialization.jsonObject(with: data) {
            object = removingAPIKeyFields(from: decoded)
        } else {
            object = [
                "migrationNotice": "Unsupported legacy configuration was replaced; sensitive contents were not retained."
            ]
        }
        return (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data("{}".utf8)
    }

    private static func removingAPIKeyFields(from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, child) in dictionary {
                let normalized = key.lowercased().filter(\.isLetter)
                guard normalized != "apikey", normalized != "azureapikey" else { continue }
                sanitized[key] = removingAPIKeyFields(from: child)
            }
            return sanitized
        }
        if let array = value as? [Any] {
            return array.map(removingAPIKeyFields)
        }
        return value
    }

    @discardableResult
    private static func writeSanitized(
        _ config: AppConfig,
        to url: URL,
        fileManager: FileManager
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(PersistedConfig(config)) else { return false }
        do {
            try secureDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
            try data.write(to: url, options: .atomic)
            try secureFile(url, fileManager: fileManager)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private static func writePrivateData(
        _ data: Data,
        to url: URL,
        fileManager: FileManager
    ) -> Bool {
        do {
            try secureDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
            try data.write(to: url, options: .atomic)
            try secureFile(url, fileManager: fileManager)
            return true
        } catch {
            return false
        }
    }

    private static func secureDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func secureFile(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
    func setTranslationServices(
        translator newTranslator: AzureTranslatorConfig,
        azureOpenAI newAzureOpenAI: AzureOpenAIConfig,
        speech newSpeech: AzureSpeechConfig,
        preferences newPreferences: TranslationPreferences
    ) -> Bool {
        let oldTranslator = translator
        let oldAzureOpenAI = azureOpenAI
        let oldSpeech = speech
        let oldPreferences = translationPreferences
        translator = newTranslator
        azureOpenAI = newAzureOpenAI
        speech = newSpeech
        translationPreferences = newPreferences
        if save() { return true }
        translator = oldTranslator
        azureOpenAI = oldAzureOpenAI
        speech = oldSpeech
        translationPreferences = oldPreferences
        return false
    }

    @discardableResult
    func setTranslationPreferences(
        _ newPreferences: TranslationPreferences,
        to url: URL? = nil
    ) -> Bool {
        let oldPreferences = translationPreferences
        translationPreferences = newPreferences
        let persisted = url.map { save(to: $0) } ?? save()
        if persisted { return true }
        translationPreferences = oldPreferences
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

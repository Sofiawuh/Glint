import Foundation

struct TranslationServiceResult: Equatable {
    let sourceText: String
    let translatedText: String
    let detectedSourceLanguage: String
    let targetLanguage: String
    let formattingMode: TranslationFormattingMode
}

enum TranslationServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case emptyDocument
    case service(String)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Azure Translator 配置不完整。请在设置 → Azure 中检查 Endpoint 和 API Key。"
        case .emptyDocument:
            return "没有可翻译的文字"
        case .service(let message):
            return message
        case .invalidResponse:
            return "Azure Translator 返回解析失败，请稍后重试"
        case .cancelled:
            return "翻译已取消"
        }
    }
}

@discardableResult
func translateDocument(
    _ text: String,
    targetLanguage: String,
    formattingMode: TranslationFormattingMode,
    completion: @escaping (Result<TranslationServiceResult, TranslationServiceError>) -> Void
) -> Task<Void, Never> {
    let config = AppConfig.shared.translator
    let formattedSource = SmartTranslationFormatter.format(text, mode: formattingMode)
    let document = TranslationDocument(formattedText: formattedSource)
    let batches = document.batches(limits: .azureDefault)

    return Task {
        guard !Task.isCancelled else {
            await MainActor.run { completion(.failure(.cancelled)) }
            return
        }
        guard !document.fragments.isEmpty, !batches.isEmpty else {
            await MainActor.run { completion(.failure(.emptyDocument)) }
            return
        }

        var collected: [TranslationFragmentResponse] = []
        collected.reserveCapacity(document.fragments.count)
        for batch in batches {
            guard !Task.isCancelled else {
                await MainActor.run { completion(.failure(.cancelled)) }
                return
            }
            guard let request = config.buildRequest(
                fragments: batch,
                targetLanguage: targetLanguage
            ) else {
                await MainActor.run { completion(.failure(.invalidConfiguration)) }
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else {
                    await MainActor.run { completion(.failure(.cancelled)) }
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    let message = config.parseError(statusCode: status, data: data)
                    await MainActor.run { completion(.failure(.service(message))) }
                    return
                }
                guard let parsed = config.parseFragmentResponses(data: data, fragments: batch) else {
                    await MainActor.run { completion(.failure(.invalidResponse)) }
                    return
                }
                collected.append(contentsOf: parsed)
            } catch is CancellationError {
                await MainActor.run { completion(.failure(.cancelled)) }
                return
            } catch {
                await MainActor.run {
                    completion(.failure(.service("网络错误：\(error.localizedDescription)")))
                }
                return
            }
        }

        guard let assembled = document.reassemble(collected) else {
            await MainActor.run { completion(.failure(.invalidResponse)) }
            return
        }
        let result = TranslationServiceResult(
            sourceText: formattedSource,
            translatedText: SmartTranslationFormatter.format(assembled.text, mode: formattingMode),
            detectedSourceLanguage: assembled.detectedLanguage ?? "auto",
            targetLanguage: targetLanguage,
            formattingMode: formattingMode
        )
        await MainActor.run { completion(.success(result)) }
    }
}

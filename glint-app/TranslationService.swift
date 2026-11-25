import Foundation

enum TranslationAIProcessingState: Equatable {
    case notRequested
    case applied
    case fallback(String)
}

struct TranslationServiceResult: Equatable {
    let sourceText: String
    let translatedText: String
    let detectedSourceLanguage: String
    let targetLanguage: String
    let formattingMode: TranslationFormattingMode
    let sourceBlocks: [TranslationBlock]?
    let translationBlocks: [TranslationBlock]?
    let aiProcessingState: TranslationAIProcessingState
}

struct TranslationAIEditResult: Equatable {
    let text: String
    let blocks: [TranslationBlock]
}

struct TranslationAIProcessedBatch: Equatable {
    let inputText: String
    let blocks: [TranslationBlock]
}

struct TranslationAIPairEditResult: Equatable {
    let sourceText: String
    let translatedText: String
    let sourceApplied: Bool
    let translationApplied: Bool
}

enum TranslationServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidAIConfiguration
    case emptyDocument
    case service(String)
    case invalidResponse
    case invalidAIResponse
    case validationFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Azure Translator 配置不完整。请在设置 → Azure 中检查 Endpoint 和 API Key。"
        case .invalidAIConfiguration:
            return "Azure GPT 未配置。请在设置 → Azure 中填写 Endpoint、API Key 和部署名称。"
        case .emptyDocument:
            return "没有可翻译的文字"
        case .service(let message):
            return message
        case .invalidResponse:
            return "Azure Translator 未返回可用译文，请稍后重试"
        case .invalidAIResponse:
            return "智能处理未完成，当前内容未改变"
        case .validationFailed:
            return "AI 处理结果可能改动受保护内容，已保留处理前内容"
        case .cancelled:
            return "翻译已取消"
        }
    }
}

struct TranslationTextPair {
    let source: String
    let translation: String
}

typealias TranslationRunner = (
    _ sourceText: String,
    _ targetLanguage: String
) async throws -> (translatedText: String, detectedSourceLanguage: String)

typealias TranslationAIPostprocessor = (
    _ sourceText: String,
    _ translatedText: String,
    _ mode: TranslationFormattingMode
) async throws -> (sourceText: String, translatedText: String)?

func translateDocument(
    _ text: String,
    targetLanguage: String,
    formattingMode: TranslationFormattingMode,
    translator: TranslationRunner,
    aiPostprocessor: TranslationAIPostprocessor?
) async -> Result<TranslationServiceResult, TranslationServiceError> {
    _ = aiPostprocessor
    let source = text
    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(.emptyDocument)
    }

    do {
        let translated = try await translator(source, targetLanguage)
        guard !translated.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidResponse)
        }
        return .success(TranslationServiceResult(
            sourceText: source,
            translatedText: translated.translatedText,
            detectedSourceLanguage: translated.detectedSourceLanguage,
            targetLanguage: targetLanguage,
            formattingMode: formattingMode,
            sourceBlocks: nil,
            translationBlocks: nil,
            aiProcessingState: .notRequested
        ))
    } catch is CancellationError {
        return .failure(.cancelled)
    } catch let error as TranslationServiceError {
        return .failure(error)
    } catch {
        return .failure(.service("网络错误：\(error.localizedDescription)"))
    }
}

@discardableResult
func translateDocument(
    _ text: String,
    targetLanguage: String,
    formattingMode: TranslationFormattingMode,
    completion: @escaping (Result<TranslationServiceResult, TranslationServiceError>) -> Void
) -> Task<Void, Never> {
    let translatorConfig = AppConfig.shared.translator
    let sourceText = text
    let chunks = translationTextChunks(
        sourceText,
        maximumCharacters: TranslationBatchLimits.azureDefault.maxCharacters
    )

    return Task {
        guard !Task.isCancelled else {
            await MainActor.run { completion(.failure(.cancelled)) }
            return
        }
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !chunks.isEmpty else {
            await MainActor.run { completion(.failure(.emptyDocument)) }
            return
        }

        var translatedChunks: [String] = []
        translatedChunks.reserveCapacity(chunks.count)
        var detectedLanguage = "auto"
        for (index, chunk) in chunks.enumerated() {
            guard !Task.isCancelled else {
                await MainActor.run { completion(.failure(.cancelled)) }
                return
            }
            guard let request = translatorConfig.buildRequest(
                text: chunk,
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
                    let message = translatorConfig.parseError(statusCode: status, data: data)
                    await MainActor.run { completion(.failure(.service(message))) }
                    return
                }
                let fragment = TranslationFragment(
                    id: String(format: "translation-chunk-%04d", index),
                    text: chunk
                )
                guard let parsed = translatorConfig.parseFragmentResponses(
                    data: data,
                    fragments: [fragment]
                )?.first,
                      !parsed.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    await MainActor.run { completion(.failure(.invalidResponse)) }
                    return
                }
                translatedChunks.append(parsed.translatedText)
                if detectedLanguage == "auto",
                   let detected = parsed.detectedLanguage,
                   !detected.isEmpty {
                    detectedLanguage = detected
                }
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

        let translatedText = translatedChunks.joined()
        guard !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { completion(.failure(.invalidResponse)) }
            return
        }

        let result = TranslationServiceResult(
            sourceText: sourceText,
            translatedText: translatedText,
            detectedSourceLanguage: detectedLanguage,
            targetLanguage: targetLanguage,
            formattingMode: formattingMode,
            sourceBlocks: nil,
            translationBlocks: nil,
            aiProcessingState: .notRequested
        )
        await MainActor.run { completion(.success(result)) }
    }
}

@discardableResult
func processTranslationPairWithAI(
    sourceText: String,
    translatedText: String,
    mode: TranslationFormattingMode,
    completion: @escaping (Result<TranslationAIPairEditResult, TranslationServiceError>) -> Void
) -> Task<Void, Never> {
    guard mode != .strict else {
        Task { @MainActor in completion(.failure(.invalidAIConfiguration)) }
        return Task {}
    }

    let config = AppConfig.shared.azureOpenAI
    let service = TranslationAIService(config: config)
    guard service.buildSingleRequest(text: sourceText, mode: mode) != nil,
          service.buildSingleRequest(text: translatedText, mode: mode) != nil else {
        Task { @MainActor in completion(.failure(.invalidAIConfiguration)) }
        return Task {}
    }

    return Task {
        let sourceResult = await performTranslationAITextRequest(
            sourceText,
            mode: mode,
            config: config,
            service: service
        )
        guard !Task.isCancelled else {
            await MainActor.run { completion(.failure(.cancelled)) }
            return
        }
        let translationResult = await performTranslationAITextRequest(
            translatedText,
            mode: mode,
            config: config,
            service: service
        )
        guard !Task.isCancelled else {
            await MainActor.run { completion(.failure(.cancelled)) }
            return
        }

        let sourceValue = try? sourceResult.get()
        let translationValue = try? translationResult.get()
        guard sourceValue != nil || translationValue != nil else {
            await MainActor.run { completion(.failure(.invalidAIResponse)) }
            return
        }
        let result = TranslationAIPairEditResult(
            sourceText: sourceValue ?? sourceText,
            translatedText: translationValue ?? translatedText,
            sourceApplied: sourceValue != nil,
            translationApplied: translationValue != nil
        )
        await MainActor.run { completion(.success(result)) }
    }
}

@discardableResult
func processTranslationTextWithAI(
    _ text: String,
    mode: TranslationFormattingMode,
    completion: @escaping (Result<TranslationAIEditResult, TranslationServiceError>) -> Void
) -> Task<Void, Never> {
    let config = AppConfig.shared.azureOpenAI
    let service = TranslationAIService(config: config)
    let textBatches = singleTextBatches(text)
    guard let firstBatch = textBatches.first,
          service.buildSingleRequest(text: firstBatch, mode: mode) != nil else {
        Task { @MainActor in completion(.failure(.invalidAIConfiguration)) }
        return Task {}
    }

    return Task {
        let result = await performTranslationAITextRequest(
            text,
            mode: mode,
            config: config,
            service: service
        )
        switch result {
        case .success(let processedText):
            await MainActor.run {
                completion(.success(TranslationAIEditResult(
                    text: processedText,
                    blocks: [.paragraph(processedText)]
                )))
            }
        case .failure(let error):
            await MainActor.run { completion(.failure(error)) }
        }
    }
}

private func performTranslationAITextRequest(
    _ text: String,
    mode: TranslationFormattingMode,
    config: AzureOpenAIConfig,
    service: TranslationAIService
) async -> Result<String, TranslationServiceError> {
    do {
        let batches = singleTextBatches(text)
        guard !batches.isEmpty else { return .failure(.invalidAIResponse) }
        var outputs: [String] = []
        outputs.reserveCapacity(batches.count)
        for batch in batches {
            guard !Task.isCancelled else { return .failure(.cancelled) }
            guard let request = service.buildSingleRequest(text: batch, mode: mode) else {
                return .failure(.invalidAIConfiguration)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return .failure(.cancelled) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return .failure(.service(config.parseError(statusCode: status, data: data)))
            }
            guard let output = service.parsePlainTextResponse(data: data) else {
                return .failure(.invalidAIResponse)
            }
            outputs.append(output)
        }
        let completed = outputs.joined(separator: outputs.count > 1 ? "\n\n" : "")
        return completed.isEmpty ? .failure(.invalidAIResponse) : .success(completed)
    } catch is CancellationError {
        return .failure(.cancelled)
    } catch {
        return .failure(.service("网络错误：\(error.localizedDescription)"))
    }
}

func translationTextChunks(
    _ text: String,
    maximumCharacters: Int = TranslationBatchLimits.azureDefault.maxCharacters
) -> [String] {
    let limit = max(1, maximumCharacters)
    guard !text.isEmpty else { return [] }
    guard text.count > limit else { return [text] }

    var chunks: [String] = []
    var remaining = text[...]
    while remaining.count > limit {
        let hardEnd = remaining.index(remaining.startIndex, offsetBy: limit)
        let prefix = remaining[..<hardEnd]
        let splitIndex = prefix.range(of: "\n\n", options: .backwards)?.upperBound
            ?? prefix.lastIndex(of: "\n").map { prefix.index(after: $0) }
            ?? hardEnd
        chunks.append(String(remaining[..<splitIndex]))
        remaining = remaining[splitIndex...]
    }
    if !remaining.isEmpty { chunks.append(String(remaining)) }
    return chunks
}

func assembleAIProcessedText(
    originalText: String,
    batches: [TranslationAIProcessedBatch],
    mode: TranslationFormattingMode
) -> TranslationAIEditResult? {
    guard !batches.isEmpty,
          batches.map(\.inputText).joined() == originalText,
          batches.allSatisfy({ !$0.blocks.isEmpty }) else { return nil }

    var blocks: [TranslationBlock] = []
    for (index, batch) in batches.enumerated() {
        var incoming = batch.blocks
        if index > 0,
           !batches[index - 1].inputText.hasSuffix("\n\n"),
           !batch.inputText.hasPrefix("\n\n"),
           let previous = blocks.popLast(),
           let first = incoming.first {
            if let merged = mergeArtificiallySplitBlocks(previous, first) {
                blocks.append(merged)
                incoming.removeFirst()
            } else {
                blocks.append(previous)
            }
        }
        blocks.append(contentsOf: incoming)
    }

    let report = TranslationBlockRenderer.render(blocks: blocks)
    let isValid = mode == .smart
        ? TranslationContentValidator.isFormattingFaithful(
            original: originalText,
            candidate: report.plainText
        )
        : TranslationContentValidator.preservesProtectedFacts(
            original: originalText,
            candidate: report.plainText
        )
    guard isValid else { return nil }
    return TranslationAIEditResult(text: report.plainText, blocks: blocks)
}

private func mergeArtificiallySplitBlocks(
    _ leading: TranslationBlock,
    _ trailing: TranslationBlock
) -> TranslationBlock? {
    switch (leading, trailing) {
    case let (.salutation(left), .salutation(right)):
        return .salutation(left + right)
    case let (.heading(left), .heading(right)):
        return .heading(left + right)
    case let (.paragraph(left), .paragraph(right)):
        return .paragraph(left + right)
    case let (.quote(left), .quote(right)):
        return .quote(left + right)
    case let (.code(left), .code(right)):
        return .code(left + right)
    case let (.table(left), .table(right)):
        return .table(left + right)
    case let (.signature(left), .signature(right)):
        return .signature(left + right)
    case let (.keyPoints(left), .keyPoints(right)):
        guard let last = left.last, let first = right.first else { return nil }
        var items = left
        items[items.count - 1] = last + first
        items.append(contentsOf: right.dropFirst())
        return .keyPoints(items)
    default:
        return nil
    }
}

func pairedTextBatches(
    source: String,
    translation: String,
    maximumCombinedCharacters: Int = 16_000
) -> [TranslationTextPair] {
    let limit = max(2, maximumCombinedCharacters)
    guard !source.isEmpty, !translation.isEmpty else { return [] }
    guard source.count + translation.count > limit else {
        return [TranslationTextPair(source: source, translation: translation)]
    }

    let sourceParts = paragraphUnitsPreservingSeparators(source)
    let translationParts = paragraphUnitsPreservingSeparators(translation)
    guard sourceParts.count == translationParts.count else {
        return hardSplitPair(source: source, translation: translation, limit: limit)
    }

    var output: [TranslationTextPair] = []
    var sourceBuffer = ""
    var translationBuffer = ""
    var characterCount = 0

    func flush() {
        guard !sourceBuffer.isEmpty else { return }
        output.append(TranslationTextPair(
            source: sourceBuffer,
            translation: translationBuffer
        ))
        sourceBuffer.removeAll(keepingCapacity: true)
        translationBuffer.removeAll(keepingCapacity: true)
        characterCount = 0
    }

    for (sourcePart, translationPart) in zip(sourceParts, translationParts) {
        let nextCount = sourcePart.count + translationPart.count
        if nextCount > limit {
            flush()
            output.append(contentsOf: hardSplitPair(
                source: sourcePart,
                translation: translationPart,
                limit: limit
            ))
            continue
        }
        if !sourceBuffer.isEmpty, characterCount + nextCount > limit {
            flush()
        }
        sourceBuffer += sourcePart
        translationBuffer += translationPart
        characterCount += nextCount
    }
    flush()
    return output
}

func singleTextBatches(
    _ text: String,
    maximumCharacters: Int = 12_000
) -> [String] {
    let limit = max(1, maximumCharacters)
    guard text.count > limit else { return [text] }
    let parts = paragraphUnitsPreservingSeparators(text)
    var output: [String] = []
    var buffer = ""
    var characterCount = 0

    func flush() {
        guard !buffer.isEmpty else { return }
        output.append(buffer)
        buffer.removeAll(keepingCapacity: true)
        characterCount = 0
    }

    for part in parts {
        if part.count > limit {
            flush()
            output.append(contentsOf: hardSplitText(part, limit: limit))
            continue
        }
        if !buffer.isEmpty, characterCount + part.count > limit {
            flush()
        }
        buffer += part
        characterCount += part.count
    }
    flush()
    return output
}

private func paragraphUnitsPreservingSeparators(_ text: String) -> [String] {
    let parts = text.components(separatedBy: "\n\n")
    guard parts.count > 1 else { return [text] }
    return parts.enumerated().map { index, part in
        index == parts.count - 1 ? part : part + "\n\n"
    }
}

private func hardSplitPair(
    source: String,
    translation: String,
    limit: Int
) -> [TranslationTextPair] {
    var partCount = max(2, Int(ceil(Double(source.count + translation.count) / Double(limit))))
    while true {
        let sourceParts = splitIntoPartCount(source, partCount: partCount)
        let translationParts = splitIntoPartCount(translation, partCount: partCount)
        let pairs = zip(sourceParts, translationParts).map {
            TranslationTextPair(source: $0.0, translation: $0.1)
        }
        if pairs.allSatisfy({ $0.source.count + $0.translation.count <= limit }) {
            return pairs
        }
        partCount += 1
    }
}

private func splitIntoPartCount(_ text: String, partCount: Int) -> [String] {
    var remaining = text[...]
    var output: [String] = []
    for index in 0..<partCount {
        let slots = partCount - index
        let length = remaining.isEmpty ? 0 : (remaining.count + slots - 1) / slots
        let end = remaining.index(remaining.startIndex, offsetBy: length)
        output.append(String(remaining[..<end]))
        remaining = remaining[end...]
    }
    return output
}

private func hardSplitText(_ text: String, limit: Int) -> [String] {
    var remaining = text[...]
    var output: [String] = []
    while !remaining.isEmpty {
        let length = min(limit, remaining.count)
        let end = remaining.index(remaining.startIndex, offsetBy: length)
        output.append(String(remaining[..<end]))
        remaining = remaining[end...]
    }
    return output
}

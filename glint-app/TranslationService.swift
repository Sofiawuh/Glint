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
    let sourceBlocks: [TranslationBlock]
    let translationBlocks: [TranslationBlock]
}

enum TranslationServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidAIConfiguration
    case emptyDocument
    case service(String)
    case invalidResponse
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
            return "Azure GPT 返回内容不完整或格式异常，已保留处理前内容"
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
    let source = SmartTranslationFormatter.format(text, mode: formattingMode)
    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(.emptyDocument)
    }

    do {
        let translated = try await translator(source, targetLanguage)
        let baseTranslation = SmartTranslationFormatter.format(
            translated.translatedText,
            mode: formattingMode
        )
        return .success(TranslationServiceResult(
            sourceText: source,
            translatedText: baseTranslation,
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
            guard let request = translatorConfig.buildRequest(
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
                    let message = translatorConfig.parseError(statusCode: status, data: data)
                    await MainActor.run { completion(.failure(.service(message))) }
                    return
                }
                guard let parsed = translatorConfig.parseFragmentResponses(data: data, fragments: batch) else {
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
        let baseTranslation = SmartTranslationFormatter.format(assembled.text, mode: formattingMode)

        let result = TranslationServiceResult(
            sourceText: formattedSource,
            translatedText: baseTranslation,
            detectedSourceLanguage: assembled.detectedLanguage ?? "auto",
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
    let pairs = pairedTextBatches(source: sourceText, translation: translatedText)
    guard let firstPair = pairs.first,
          service.buildAutomaticRequest(
            sourceText: firstPair.source,
            translatedText: firstPair.translation,
            mode: mode
          ) != nil else {
        Task { @MainActor in completion(.failure(.invalidAIConfiguration)) }
        return Task {}
    }

    return Task {
        do {
            var sourceBatches: [TranslationAIProcessedBatch] = []
            var translationBatches: [TranslationAIProcessedBatch] = []
            for pair in pairs {
                guard !Task.isCancelled else { throw TranslationServiceError.cancelled }
                guard let request = service.buildAutomaticRequest(
                    sourceText: pair.source,
                    translatedText: pair.translation,
                    mode: mode
                ) else { throw TranslationServiceError.invalidAIConfiguration }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { throw TranslationServiceError.cancelled }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    throw TranslationServiceError.service(
                        config.parseError(statusCode: status, data: data)
                    )
                }
                guard let parsed = service.parseAutomaticResponse(data: data) else {
                    throw TranslationServiceError.invalidResponse
                }
                sourceBatches.append(TranslationAIProcessedBatch(
                    inputText: pair.source,
                    blocks: parsed.sourceBlocks
                ))
                translationBatches.append(TranslationAIProcessedBatch(
                    inputText: pair.translation,
                    blocks: parsed.translationBlocks
                ))
            }

            guard let sourceResult = assembleAIProcessedText(
                originalText: sourceText,
                batches: sourceBatches,
                mode: .smart
            ), let translationResult = assembleAIProcessedText(
                originalText: translatedText,
                batches: translationBatches,
                mode: mode
            ) else { throw TranslationServiceError.validationFailed }

            let result = TranslationAIPairEditResult(
                sourceText: sourceResult.text,
                translatedText: translationResult.text,
                sourceBlocks: sourceResult.blocks,
                translationBlocks: translationResult.blocks
            )
            await MainActor.run { completion(.success(result)) }
        } catch is CancellationError {
            await MainActor.run { completion(.failure(.cancelled)) }
        } catch let error as TranslationServiceError {
            await MainActor.run { completion(.failure(error)) }
        } catch {
            await MainActor.run {
                completion(.failure(.service("网络错误：\(error.localizedDescription)")))
            }
        }
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
        do {
            var processedBatches: [TranslationAIProcessedBatch] = []
            for batch in textBatches {
                guard !Task.isCancelled else { throw TranslationServiceError.cancelled }
                guard let request = service.buildSingleRequest(text: batch, mode: mode) else {
                    throw TranslationServiceError.invalidAIConfiguration
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { throw TranslationServiceError.cancelled }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(status) else {
                    throw TranslationServiceError.service(
                        config.parseError(statusCode: status, data: data)
                    )
                }
                guard let parsed = service.parseSingleResponse(data: data), !parsed.isEmpty else {
                    throw TranslationServiceError.invalidResponse
                }
                processedBatches.append(TranslationAIProcessedBatch(
                    inputText: batch,
                    blocks: parsed
                ))
            }
            guard let completedResult = assembleAIProcessedText(
                originalText: text,
                batches: processedBatches,
                mode: mode
            ) else { throw TranslationServiceError.validationFailed }
            await MainActor.run {
                completion(.success(completedResult))
            }
        } catch is CancellationError {
            await MainActor.run { completion(.failure(.cancelled)) }
        } catch let error as TranslationServiceError {
            await MainActor.run { completion(.failure(error)) }
        } catch {
            await MainActor.run {
                completion(.failure(.service("网络错误：\(error.localizedDescription)")))
            }
        }
    }
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

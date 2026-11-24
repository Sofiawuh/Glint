import Foundation

enum TranslationWorkbenchField: Equatable {
    case source
    case translation
}

struct TranslationRetranslationRequest: Equatable {
    let generation: Int
    let sourceText: String
    let targetLanguage: String
    let formattingMode: TranslationFormattingMode
}

struct TranslationSpeechRequest: Equatable {
    let field: TranslationWorkbenchField
    let text: String
    let languageCode: String
}

struct TranslationAIEditRequest: Equatable {
    let generation: Int
    let field: TranslationWorkbenchField
    let text: String
    let mode: TranslationFormattingMode
}

struct TranslationAIPairEditRequest: Equatable {
    let generation: Int
    let sourceText: String
    let translatedText: String
    let mode: TranslationFormattingMode
}

struct TranslationAIRequestIdentity: Equatable {
    let sequence: Int
    let historyID: String
}

struct TranslationAIRequestLifecycle {
    private var sequence = 0
    private var active: TranslationAIRequestIdentity?

    var hasCurrentRequest: Bool { active != nil }

    mutating func begin(historyID: String) -> TranslationAIRequestIdentity {
        sequence += 1
        let identity = TranslationAIRequestIdentity(sequence: sequence, historyID: historyID)
        active = identity
        return identity
    }

    mutating func invalidateAll() {
        sequence += 1
        active = nil
    }

    func isCurrent(_ identity: TranslationAIRequestIdentity) -> Bool {
        active == identity
    }

    @discardableResult
    mutating func finish(_ identity: TranslationAIRequestIdentity) -> Bool {
        guard active == identity else { return false }
        active = nil
        return true
    }
}

enum TranslationSpeechAction: Equatable {
    case start(TranslationSpeechRequest)
    case stopAndStart(TranslationWorkbenchField, TranslationSpeechRequest)
    case stop(TranslationWorkbenchField)
    case none
}

struct TranslationWorkbenchState {
    let historyID: String
    let originalSourceText: String
    private(set) var sourceText: String
    private(set) var translatedText: String
    private(set) var sourceLanguage: String
    private(set) var targetLanguage: String
    private(set) var targetMode: TranslationTargetMode
    private(set) var fixedTargetLanguage: String
    private(set) var formattingMode: TranslationFormattingMode
    private(set) var isRequestInFlight = false
    private(set) var aiFieldInFlight: TranslationWorkbenchField?
    private(set) var isPairAIProcessing = false
    private(set) var speakingField: TranslationWorkbenchField?
    private var translatedSourceText: String
    private var generation = 0
    private var aiGeneration = 0
    private var pairAIGeneration = 0

    var canRetranslate: Bool { !isRequestInFlight }
    var canChangeTargetLanguage: Bool { !isRequestInFlight }
    var canSwitchRecentResult: Bool { !isRequestInFlight }
    var isSourceDirty: Bool { sourceText != translatedSourceText }

    init(
        historyID: String,
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        targetMode: TranslationTargetMode = .fixed,
        fixedTargetLanguage: String? = nil,
        formattingMode: TranslationFormattingMode,
        originalSourceText: String? = nil
    ) {
        self.historyID = historyID
        self.originalSourceText = originalSourceText ?? sourceText
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.targetMode = targetMode
        self.fixedTargetLanguage = fixedTargetLanguage ?? targetLanguage
        self.formattingMode = formattingMode
        translatedSourceText = sourceText
    }

    mutating func editSource(_ text: String) {
        sourceText = text
        if targetMode == .automatic {
            targetLanguage = Self.automaticTargetLanguage(forText: text)
        }
        invalidateAIIfEditing(.source)
    }

    mutating func editTranslation(_ text: String) {
        translatedText = text
        invalidateAIIfEditing(.translation)
    }

    mutating func setTargetLanguage(_ language: String) {
        guard canChangeTargetLanguage else { return }
        if language.caseInsensitiveCompare("auto") == .orderedSame {
            targetMode = .automatic
            targetLanguage = Self.automaticTargetLanguage(for: sourceLanguage)
            return
        }
        targetLanguage = language
        targetMode = .fixed
        fixedTargetLanguage = language
    }

    mutating func setFormattingMode(_ mode: TranslationFormattingMode) {
        guard canChangeTargetLanguage else { return }
        formattingMode = mode
    }

    mutating func beginRetranslation() -> TranslationRetranslationRequest? {
        guard canRetranslate,
              !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if aiFieldInFlight != nil {
            cancelAIProcessing()
        }
        if isPairAIProcessing {
            cancelPairAIProcessing()
        }
        generation += 1
        isRequestInFlight = true
        return TranslationRetranslationRequest(
            generation: generation,
            sourceText: sourceText,
            targetLanguage: targetLanguage,
            formattingMode: formattingMode
        )
    }

    mutating func cancelRetranslation() {
        generation += 1
        isRequestInFlight = false
    }

    @discardableResult
    mutating func completeRetranslation(
        generation completedGeneration: Int,
        translatedText: String,
        detectedSourceLanguage: String?
    ) -> Bool {
        guard isRequestInFlight, completedGeneration == generation else { return false }
        self.translatedText = translatedText
        translatedSourceText = sourceText
        if let detectedSourceLanguage, !detectedSourceLanguage.isEmpty {
            sourceLanguage = detectedSourceLanguage
            if targetMode == .automatic {
                targetLanguage = Self.automaticTargetLanguage(for: detectedSourceLanguage)
            } else {
                targetLanguage = fixedTargetLanguage
            }
        }
        isRequestInFlight = false
        return true
    }

    mutating func failRetranslation(generation failedGeneration: Int) -> Bool {
        guard isRequestInFlight, failedGeneration == generation else { return false }
        isRequestInFlight = false
        return true
    }

    mutating func beginAIProcessing(
        field: TranslationWorkbenchField,
        mode: TranslationFormattingMode
    ) -> TranslationAIEditRequest? {
        guard mode != .strict,
              !isRequestInFlight,
              aiFieldInFlight == nil,
              !isPairAIProcessing else { return nil }
        let text = field == .source ? sourceText : translatedText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        aiGeneration += 1
        aiFieldInFlight = field
        return TranslationAIEditRequest(
            generation: aiGeneration,
            field: field,
            text: text,
            mode: mode
        )
    }

    @discardableResult
    mutating func completeAIProcessing(
        generation completedGeneration: Int,
        field: TranslationWorkbenchField,
        text: String
    ) -> Bool {
        guard completedGeneration == aiGeneration, aiFieldInFlight == field else { return false }
        if field == .source {
            sourceText = text
        } else {
            translatedText = text
        }
        aiFieldInFlight = nil
        return true
    }

    mutating func failAIProcessing(generation failedGeneration: Int) -> Bool {
        guard failedGeneration == aiGeneration, aiFieldInFlight != nil else { return false }
        aiFieldInFlight = nil
        return true
    }

    mutating func cancelAIProcessing() {
        aiGeneration += 1
        aiFieldInFlight = nil
    }

    mutating func beginPairAIProcessing(
        mode: TranslationFormattingMode
    ) -> TranslationAIPairEditRequest? {
        guard mode != .strict,
              !isRequestInFlight,
              aiFieldInFlight == nil,
              !isPairAIProcessing,
              !isSourceDirty,
              !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        pairAIGeneration += 1
        isPairAIProcessing = true
        return TranslationAIPairEditRequest(
            generation: pairAIGeneration,
            sourceText: sourceText,
            translatedText: translatedText,
            mode: mode
        )
    }

    @discardableResult
    mutating func completePairAIProcessing(
        generation completedGeneration: Int,
        sourceText: String,
        translatedText: String
    ) -> Bool {
        guard isPairAIProcessing, completedGeneration == pairAIGeneration else { return false }
        self.sourceText = sourceText
        self.translatedText = translatedText
        isPairAIProcessing = false
        return true
    }

    mutating func failPairAIProcessing(generation failedGeneration: Int) -> Bool {
        guard isPairAIProcessing, failedGeneration == pairAIGeneration else { return false }
        isPairAIProcessing = false
        return true
    }

    mutating func cancelPairAIProcessing() {
        pairAIGeneration += 1
        isPairAIProcessing = false
    }

    mutating func toggleSpeech(for field: TranslationWorkbenchField) -> TranslationSpeechAction {
        if speakingField == field {
            speakingField = nil
            return .stop(field)
        }
        let request = TranslationSpeechRequest(
            field: field,
            text: field == .source ? sourceText : translatedText,
            languageCode: field == .source ? sourceLanguage : targetLanguage
        )
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
        if let previous = speakingField {
            speakingField = field
            return .stopAndStart(previous, request)
        }
        speakingField = field
        return .start(request)
    }

    mutating func speechDidStop() { speakingField = nil }

    func makeHistoryEntry(completedAt: Date, menuSummary: String) -> RecentResultEntry {
        RecentResultEntry(
            id: historyID,
            kind: .translation,
            completedAt: completedAt,
            menuSummary: menuSummary,
            snapshot: .translation(sourceText: sourceText, resultText: translatedText)
        )
    }

    private static func automaticTargetLanguage(for detectedLanguage: String) -> String {
        detectedLanguage.lowercased().hasPrefix("zh") ? "en" : "zh-Hans"
    }

    private static func automaticTargetLanguage(forText text: String) -> String {
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

    private mutating func invalidateAIIfEditing(_ field: TranslationWorkbenchField) {
        if aiFieldInFlight == field {
            aiGeneration += 1
            aiFieldInFlight = nil
        }
        if isPairAIProcessing {
            pairAIGeneration += 1
            isPairAIProcessing = false
        }
    }
}

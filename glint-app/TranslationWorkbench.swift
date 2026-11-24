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
    private(set) var speakingField: TranslationWorkbenchField?
    private var generation = 0

    var canRetranslate: Bool { !isRequestInFlight }
    var canChangeTargetLanguage: Bool { !isRequestInFlight }
    var canSwitchRecentResult: Bool { !isRequestInFlight }

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
    }

    mutating func editSource(_ text: String) { sourceText = text }
    mutating func editTranslation(_ text: String) { translatedText = text }
    mutating func setTargetLanguage(_ language: String) {
        guard canChangeTargetLanguage else { return }
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
}

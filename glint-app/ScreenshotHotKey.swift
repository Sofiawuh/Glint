import Carbon
import Foundation

struct ScreenshotHotKey: Codable, Equatable {
    enum RecordingDecision: Equatable {
        case cancel
        case restoreDefault
        case waitForKey
        case invalid
        case commit(ScreenshotHotKey)
    }

    static let modifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    static let `default` = ScreenshotHotKey(
        keyCode: UInt32(kVK_ANSI_E),
        modifiers: UInt32(controlKey | optionKey)
    )

    let keyCode: UInt32
    let modifiers: UInt32

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt32.self, forKey: .keyCode),
            modifiers: try container.decode(UInt32.self, forKey: .modifiers)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers, forKey: .modifiers)
    }

    var isValid: Bool {
        !Self.reservedRecordingKeyCodes.contains(keyCode)
            && !Self.physicalModifierKeyCodes.contains(keyCode)
            && (modifiers != 0 || Self.unmodifiedAllowedKeyCodes.contains(keyCode))
    }

    var displayString: String {
        displayString(keyLabelTranslator: Self.translatedKeyLabel)
    }

    func displayString(keyLabelTranslator: (UInt32) -> String?) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyLabel(for: keyCode, keyLabelTranslator: keyLabelTranslator)
    }

    static func recordingDecision(keyCode: UInt32?, modifiers: UInt32) -> RecordingDecision {
        guard let keyCode else { return .waitForKey }
        if keyCode == UInt32(kVK_Escape) { return .cancel }
        if keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete) {
            return .restoreDefault
        }
        let candidate = ScreenshotHotKey(keyCode: keyCode, modifiers: modifiers)
        return candidate.isValid ? .commit(candidate) : .invalid
    }

    private static let reservedRecordingKeyCodes: Set<UInt32> = [
        UInt32(kVK_Escape),
        UInt32(kVK_Delete),
        UInt32(kVK_ForwardDelete)
    ]

    private static let physicalModifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command),
        UInt32(kVK_Shift),
        UInt32(kVK_Option),
        UInt32(kVK_Control),
        UInt32(kVK_RightCommand),
        UInt32(kVK_RightShift),
        UInt32(kVK_RightOption),
        UInt32(kVK_RightControl),
        UInt32(kVK_CapsLock),
        UInt32(kVK_Function)
    ]

    private static let unmodifiedAllowedKeyCodes: Set<UInt32> = [
        UInt32(kVK_ANSI_Grave),
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20)
    ]

    private static func keyLabel(
        for keyCode: UInt32,
        keyLabelTranslator: (UInt32) -> String?
    ) -> String {
        let special: [UInt32: String] = [
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_ANSI_KeypadEnter): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Home): "↖",
            UInt32(kVK_End): "↘",
            UInt32(kVK_PageUp): "⇞",
            UInt32(kVK_PageDown): "⇟",
            UInt32(kVK_Help): "Help",
            UInt32(kVK_ANSI_Grave): "`"
        ]
        if let label = special[keyCode] { return label }

        let functionKeys: [UInt32: String] = [
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
            UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
            UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20"
        ]
        if let label = functionKeys[keyCode] { return label }
        if let label = keypadKeyLabels[keyCode] { return label }
        if let translated = keyLabelTranslator(keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return fallbackKeyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static func translatedKeyLabel(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(property, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var actualLength = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &actualLength,
            &characters
        )
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: actualLength)
    }

    private static let keypadKeyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_Keypad0): "0",
        UInt32(kVK_ANSI_Keypad1): "1",
        UInt32(kVK_ANSI_Keypad2): "2",
        UInt32(kVK_ANSI_Keypad3): "3",
        UInt32(kVK_ANSI_Keypad4): "4",
        UInt32(kVK_ANSI_Keypad5): "5",
        UInt32(kVK_ANSI_Keypad6): "6",
        UInt32(kVK_ANSI_Keypad7): "7",
        UInt32(kVK_ANSI_Keypad8): "8",
        UInt32(kVK_ANSI_Keypad9): "9",
        UInt32(kVK_ANSI_KeypadDecimal): ".",
        UInt32(kVK_ANSI_KeypadMultiply): "×",
        UInt32(kVK_ANSI_KeypadPlus): "+",
        UInt32(kVK_ANSI_KeypadClear): "Clear",
        UInt32(kVK_ANSI_KeypadDivide): "÷",
        UInt32(kVK_ANSI_KeypadMinus): "-",
        UInt32(kVK_ANSI_KeypadEquals): "="
    ]

    private static let fallbackKeyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`"
    ]
}

enum HotKeyRecordingFeedback {
    static let invalidSingleKeyMessage = "可单独按 ` 或 F1–F20；其他按键需搭配修饰键"
    static let recordingInstructions = "单独按 ` 或 F1–F20；其他按键搭配修饰键；Esc 取消，Delete 恢复默认"

    static func status(
        after decision: ScreenshotHotKey.RecordingDecision,
        current: String
    ) -> String {
        switch decision {
        case .invalid:
            return invalidSingleKeyMessage
        case .waitForKey:
            return current
        case .cancel, .restoreDefault, .commit:
            return ""
        }
    }
}

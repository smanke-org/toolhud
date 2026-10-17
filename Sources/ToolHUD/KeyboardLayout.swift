import Carbon
import ToolHUDKit

/// Which key types a character on the current keyboard layout, so a keystroke button can
/// press the key behind each character typed in Settings (on AZERTY, "a" is a different
/// key than on US English).
enum KeyboardLayout {
    /// The key that types `character`, and whether Shift is needed for it.
    static func key(for character: Character) -> (keyCode: UInt16, shift: Bool)? {
        table()[String(character)]
    }

    /// Character → key, for every key on the main keyboard: unshifted first, so "1" is the
    /// 1 key rather than a keypad key or ⇧ of something else.
    private static func table() -> [String: (keyCode: UInt16, shift: Bool)] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var table: [String: (keyCode: UInt16, shift: Bool)] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for shift in [false, true] {
                let state = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
                // The keypad's codes (65–92) come after the main keys and are skipped, so
                // digits and symbols map to the main row.
                for code in UInt16(0)..<UInt16(128) where !(65...92).contains(code) {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), state, UInt32(LMGetKbdType()),
                                                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                    guard status == noErr, length > 0 else { continue }
                    let string = String(utf16CodeUnits: chars, count: length)
                    guard !string.isEmpty, string.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                          table[string] == nil else { continue }
                    table[string] = (code, shift)
                }
            }
        }
        return table
    }
}

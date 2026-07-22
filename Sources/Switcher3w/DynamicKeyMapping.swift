import Carbon
import Foundation

/// Dynamic keycode↔character mapping for any pair of layouts via UCKeyTranslate
enum DynamicKeyMapping {
    /// Mapping cache: key = "layoutID1→layoutID2"
    nonisolated(unsafe) private static var mapCache: [String: [Character: Character]] = [:]

    /// All keycodes for letters/signs (0-50 covers the main keyboard)
    private static let allKeycodes: [UInt16] = Array(0...50)

    // MARK: - Public API

    /// Get the character for a keycode in a specific layout
    static func characterForKeycode(_ keycode: UInt16, layout: TISInputSource) -> Character? {
        guard let layoutData = layoutDataForSource(layout) else { return nil }
        return translateKeycode(keycode, layoutData: layoutData, shift: false)
    }

    /// Checks whether a keycode is a "letter" in either of the two layouts
    static func isLetterKeycode(_ keycode: UInt16) -> Bool {
        let settings = SettingsManager.shared
        let layouts = LayoutSwitcher.installedLayouts()

        // Try with the configured layouts
        for layout in layouts {
            let id = LayoutSwitcher.sourceID(layout)
            if id == settings.layout1ID || id == settings.layout2ID || settings.layout1ID.isEmpty {
                if characterForKeycode(keycode, layout: layout) != nil {
                    return true
                }
            }
        }

        // Fallback to the static table
        return KeyMapping.keycodeToEN[keycode] != nil
    }

    /// Build a mapping between two layouts
    static func buildMap(from source: TISInputSource, to target: TISInputSource) -> [Character: Character] {
        let sourceID = LayoutSwitcher.sourceID(source)
        let targetID = LayoutSwitcher.sourceID(target)
        let cacheKey = "\(sourceID)→\(targetID)"

        if let cached = mapCache[cacheKey] {
            return cached
        }

        guard let sourceData = layoutDataForSource(source),
              let targetData = layoutDataForSource(target) else {
            return [:]
        }

        var map: [Character: Character] = [:]

        for keycode in allKeycodes {
            // Without shift
            if let sourceChar = translateKeycode(keycode, layoutData: sourceData, shift: false),
               let targetChar = translateKeycode(keycode, layoutData: targetData, shift: false),
               sourceChar != targetChar {
                map[sourceChar] = targetChar
            }
            // With shift
            if let sourceChar = translateKeycode(keycode, layoutData: sourceData, shift: true),
               let targetChar = translateKeycode(keycode, layoutData: targetData, shift: true),
               sourceChar != targetChar {
                map[sourceChar] = targetChar
            }
        }

        mapCache[cacheKey] = map
        return map
    }

    /// Clear the cache (when layouts change in settings)
    static func clearCache() {
        mapCache.removeAll()
    }

    /// Converts the typed keycodes into source- and target-layout strings —
    /// for the retype engine (we don't read the field, don't touch the clipboard).
    /// nil — if the layouts couldn't be determined (then the caller falls back to clipboard).
    static func convertKeys(_ keys: [TypedKey]) -> (original: String, converted: String)? {
        guard !keys.isEmpty else { return nil }
        // Remote desktop: characters are relayed through Screen Sharing (keyCode 0 + char). We
        // convert by the character itself — KeyMapping.convert decides the RU↔EN direction by
        // script (Cyrillic↔Latin), not by the local machine's layout. That way the office
        // instance correctly converts text typed on the Russian layout back to "hello"
        // regardless of which layout is active on it.
        if keys.allSatisfy({ $0.char != nil }) {
            let original = String(keys.compactMap { $0.char })
            return (original, KeyMapping.convert(original))
        }
        let settings = SettingsManager.shared
        let layouts = LayoutSwitcher.installedLayouts()
        let currentID = LayoutSwitcher.currentLayoutID()
        let layout1ID = settings.layout1ID.isEmpty ? LayoutSwitcher.autoDetectID1(from: layouts) : settings.layout1ID
        let layout2ID = settings.layout2ID.isEmpty ? LayoutSwitcher.autoDetectID2(from: layouts) : settings.layout2ID

        guard let source = layouts.first(where: { LayoutSwitcher.sourceID($0) == currentID }),
              let targetID = (currentID == layout1ID) ? layout2ID : layout1ID as String?,
              let target = layouts.first(where: { LayoutSwitcher.sourceID($0) == targetID }),
              let sourceData = layoutDataForSource(source),
              let targetData = layoutDataForSource(target) else {
            return nil
        }

        var original = "", converted = ""
        for k in keys {
            guard let sc = translateKeycode(k.keyCode, layoutData: sourceData, shift: k.shift, caps: k.caps),
                  let tc = translateKeycode(k.keyCode, layoutData: targetData, shift: k.shift, caps: k.caps) else {
                return nil
            }
            original.append(sc)
            converted.append(tc)
        }
        return (original, converted)
    }

    // Layout auto-detect lives in LayoutSwitcher (autoDetectID1/ID2).

    // MARK: - Private

    static func layoutDataForSource(_ source: TISInputSource) -> Data? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data
    }

    static func translateKeycode(_ keycode: UInt16, layoutData: Data, shift: Bool, caps: Bool = false) -> Character? {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        var modifierKeyState: UInt32 = shift ? (UInt32(shiftKey >> 8) & 0xFF) : 0
        if caps { modifierKeyState |= UInt32(alphaLock >> 8) & 0xFF }

        let result = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return -1
            }
            return UCKeyTranslate(
                ptr,
                keycode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard result == noErr, length > 0 else { return nil }

        guard let scalar = UnicodeScalar(chars[0]) else { return nil }
        let char = Character(scalar)

        // Filter out control characters
        if char.isNewline || char.asciiValue == 0 || chars[0] < 32 {
            return nil
        }

        return char
    }
}

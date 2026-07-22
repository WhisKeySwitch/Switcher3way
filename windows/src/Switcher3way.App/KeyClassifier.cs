namespace Switcher3way.App;

/// <summary>How a virtual key affects the word buffer. Graduated from the spike.</summary>
internal enum KeyKind
{
    Letter,     // A–Z: append
    Character,  // digits + OEM punctuation keys: also part of the token (',' is 'б' on ЙЦУКЕН, etc.)
    Boundary,   // space/enter/tab: word finished, evaluate
    Backspace,  // pop the last buffered key
    Modifier,   // shift/ctrl/alt/caps/win alone: keep the buffer
    Reset,      // arrows/home/end/page/ins/del, function keys, anything else: discard the buffer
}

internal static class KeyClassifier
{
    private const uint VK_BACK = 0x08, VK_TAB = 0x09, VK_RETURN = 0x0D;
    private const uint VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_CAPITAL = 0x14, VK_SPACE = 0x20;
    private const uint VK_PRIOR = 0x21, VK_NEXT = 0x22, VK_END = 0x23, VK_HOME = 0x24;
    private const uint VK_LEFT = 0x25, VK_UP = 0x26, VK_RIGHT = 0x27, VK_DOWN = 0x28;
    private const uint VK_INSERT = 0x2D, VK_DELETE = 0x2E, VK_LWIN = 0x5B, VK_RWIN = 0x5C;
    private const uint VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5;
    private const uint VK_OEM_1 = 0xBA, VK_OEM_3 = 0xC0, VK_OEM_4 = 0xDB, VK_OEM_8 = 0xDF, VK_OEM_102 = 0xE2;

    public static KeyKind Classify(uint vk) => vk switch
    {
        >= 'A' and <= 'Z' => KeyKind.Letter,
        >= '0' and <= '9' => KeyKind.Character,
        >= VK_OEM_1 and <= VK_OEM_3 => KeyKind.Character,   // ; = , - . / `
        >= VK_OEM_4 and <= VK_OEM_8 => KeyKind.Character,   // [ \ ] '  (+ OEM_8)
        VK_OEM_102 => KeyKind.Character,
        VK_SPACE or VK_RETURN or VK_TAB => KeyKind.Boundary,
        VK_BACK => KeyKind.Backspace,
        VK_SHIFT or VK_CONTROL or VK_MENU or VK_CAPITAL or VK_LWIN or VK_RWIN
            or VK_LSHIFT or VK_RSHIFT or VK_LCONTROL or VK_RCONTROL or VK_LMENU or VK_RMENU => KeyKind.Modifier,
        VK_LEFT or VK_UP or VK_RIGHT or VK_DOWN or VK_HOME or VK_END
            or VK_PRIOR or VK_NEXT or VK_INSERT or VK_DELETE => KeyKind.Reset,
        _ => KeyKind.Reset,
    };
}

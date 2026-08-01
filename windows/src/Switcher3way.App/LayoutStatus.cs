using System.Globalization;

namespace Switcher3way.App;

/// <summary>Foreground-layout helpers shared by the tray and the settings status card.</summary>
internal static class LayoutStatus
{
    /// <summary>The foreground app's current layout language (en/ru/uk…), per-thread on Windows.</summary>
    public static string CurrentLang()
    {
        var hwnd = Native.GetForegroundWindow();
        uint tid = Native.GetWindowThreadProcessId(hwnd, out _);
        int langId = (int)((long)Native.GetKeyboardLayout(tid) & 0xFFFF);
        try { return CultureInfo.GetCultureInfo(langId).TwoLetterISOLanguageName; }
        catch (CultureNotFoundException) { return "?"; }
    }

    /// <summary>English display name for a 2-letter code (for the status line).</summary>
    public static string LangName(string two) => two switch
    {
        "en" => "English",
        "uk" => "Ukrainian",
        "ru" => "Russian",
        "be" => "Belarusian",
        _ => two.ToUpperInvariant(),
    };
}

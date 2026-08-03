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

    /// <summary>
    /// Display name for a 2-letter code, in the interface language — it appears in the tray, the
    /// settings status card and the onboarding layout list, so it cannot stay English-only.
    /// Unknown codes fall back to the bare code.
    /// </summary>
    public static string LangName(string two) => two switch
    {
        "en" or "uk" or "ru" or "be" => Loc.T("lang." + two),
        _ => two.ToUpperInvariant(),
    };
}

namespace Switcher3way.App;

/// <summary>
/// Whether the focused control is a password field — auto/manual conversion must never rewrite in one.
///
/// TODO(windows-winui3 task 1.5): the previous implementation used WPF's
/// <c>System.Windows.Automation</c> (IsPassword), which was dropped with the WinForms/WPF app model.
/// Re-implement over COM UI Automation (<c>CUIAutomation</c> / <c>IUIAutomation</c>) before this branch
/// ships. Until then this returns false (no password-field guard) — acceptable ONLY on the migration
/// branch; `main` still ships the WinForms build with the real guard, preserved in git history.
/// </summary>
internal static class SecureField
{
    public static bool IsFocusedPassword() => false;
}

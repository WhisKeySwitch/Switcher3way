using System.Windows.Automation;

namespace Switcher3way.App;

/// <summary>
/// Detects whether the focused control is a password field (via UI Automation's <c>IsPassword</c>),
/// so auto/manual conversion never touches a password — including in-browser login fields that the
/// denied-apps list can't catch. Best-effort: any UIA hiccup returns false (fail-open on detection,
/// but the denied-apps list still guards password *managers*).
/// </summary>
internal static class SecureField
{
    public static bool IsFocusedPassword()
    {
        try
        {
            var el = AutomationElement.FocusedElement;
            if (el is null) return false;
            var v = el.GetCurrentPropertyValue(AutomationElement.IsPasswordProperty);
            return v is bool b && b;
        }
        catch
        {
            return false; // UIA can throw/timeout on some targets — don't block on it
        }
    }
}

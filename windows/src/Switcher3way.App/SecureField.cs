using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace Switcher3way.App;

/// <summary>
/// Whether the focused control is a password field — auto and manual conversion must never rewrite
/// in one, including in-browser login fields the denied-apps list can't catch.
///
/// Four checks, in the order of what actually catches what:
///   1. **UI Automation <c>IsPassword</c>** — a masked browser <c>&lt;input type="password"&gt;</c>.
///      Verified in Chrome and Edge on 5 Aug 2026 against a local test page: `uia=True` on the password
///      input, `False` on the plain text field beside it.
///   2. **UIA name/automation-id says "password"** — the same field while *un-masked*, which `IsPassword`
///      does not report. See <see cref="UiaLooksLikePasswordField"/>; this is what a real login form with a
///      show/hide toggle needs.
///   3. a classic Win32 edit control with the <c>ES_PASSWORD</c> style — Win32 dialogs.
///   4. the MSAA focused object carrying <c>STATE_SYSTEM_PROTECTED</c> — some non-Chromium hosts.
///
/// Run <c>Switcher3way.exe diagpw</c> to see all four for whatever has focus.
///
/// **History worth keeping.** The WinForms build used `System.Windows.Automation.IsPassword` and worked.
/// Dropping the WPF app model for WinUI took that assembly away, so this class was stubbed to `false`;
/// it was then "restored" with checks 2 and 3 only, on the assumption that Chromium marks password
/// inputs via MSAA. It does not — `accFocus` returns the document node (`accRole=15`) with the protected
/// bit clear — so from 0.2.0 to 0.2.3 the guard never fired once, and conversion happened inside browser
/// password fields. Proven by a user report and by zero `suppressed - password field` lines in a 275 KB
/// log. UIA is back, this time through the `Interop.UIAutomationClient` interop assembly, which works
/// without the WPF app model.
///
/// Best-effort by design: any failure returns false (the denied-apps list still guards password
/// *managers*), but a positive result always suppresses conversion. Detection must never throw into the
/// conversion path — but it must also never silently answer "not a password" because a query failed, so
/// failures are logged.
/// </summary>
internal static class SecureField
{
    public static bool IsFocusedPassword()
    {
        try
        {
            if (UiaIsPassword()) return true;               // browsers: masked password inputs
            if (UiaLooksLikePasswordField()) return true;   // …and un-masked ones, see below

            IntPtr focus = FocusedWindow();
            if (focus == IntPtr.Zero) return false;
            return HasPasswordStyle(focus) || MsaaProtected(focus);
        }
        catch (Exception ex)
        {
            Diagnostics.Log("secure: detection failed, treating as not-a-password: " + ex.Message);
            return false; // never let detection block or crash conversion
        }
    }

    // The UIA client object is expensive to create and safe to reuse, and this runs on every word.
    private static Interop.UIAutomationClient.IUIAutomation? _uia;
    private static bool _uiaBroken;

    /// <summary>
    /// UI Automation's <c>IsPassword</c> on the focused element. This is what recognises
    /// <c>&lt;input type="password"&gt;</c> in Chrome, Edge, Firefox and Electron apps.
    /// </summary>
    private static bool UiaIsPassword()
    {
        if (_uiaBroken) return false;
        try
        {
            _uia ??= new Interop.UIAutomationClient.CUIAutomation();
            var focused = _uia.GetFocusedElement();
            // The typed member, not GetCurrentPropertyValue with a literal id: the first attempt at this
            // passed 30097, which is not IsPassword (30019), so it read false for every field on earth
            // while looking perfectly reasonable.
            return focused is not null && focused.CurrentIsPassword != 0;
        }
        catch (Exception ex)
        {
            // Don't retry forever if the UIA client itself cannot be created — but say so once, because
            // the consequence is that browser password fields stop being recognised.
            _uiaBroken = true;
            Diagnostics.LogAlways("secure: UI Automation unavailable, browser password fields will NOT be " +
                                  "detected: " + ex.Message);
            return false;
        }
    }

    /// <summary>
    /// Each signal separately, for the `diagpw` diagnostic. The verdict alone is not enough to trust:
    /// knowing *which* check answered is what distinguishes a working guard from one that happens to be
    /// right for the wrong reason — which is how the browser case went unnoticed for four releases.
    /// </summary>
    internal static string Describe()
    {
        IntPtr focus = FocusedWindow();
        var cls = new StringBuilder(64);
        GetClassNameW(focus, cls, cls.Capacity);
        bool uia = UiaIsPassword();
        bool named = UiaLooksLikePasswordField();
        bool style = focus != IntPtr.Zero && HasPasswordStyle(focus);
        bool msaa = focus != IntPtr.Zero && MsaaProtected(focus);

        // What UIA thinks has focus — if this is the browser window rather than the input, the client is
        // not reaching web content and IsPassword can never be true.
        string uiaElement = "n/a";
        try
        {
            _uia ??= new Interop.UIAutomationClient.CUIAutomation();
            var el = _uia.GetFocusedElement();
            uiaElement = el is null ? "null"
                : $"name='{el.CurrentName}' type={el.CurrentControlType} class='{el.CurrentClassName}'";
        }
        catch (Exception ex) { uiaElement = "threw: " + ex.Message; }

        return $"password={uia || named || style || msaa}  " +
               $"(uia={uia} named={named} es_password={style} msaa={msaa})  " +
               $"focus=0x{focus:X} class={cls}  uiaFocused[{uiaElement}]";
    }

    /// <summary>
    /// A text field that is *labelled* as a password even though it is not currently masked.
    ///
    /// UIA's <c>IsPassword</c> reports masking, not intent. Any form with a "show password" toggle turns
    /// its input into a plain <c>type="text"</c> while revealed, and some forms never use
    /// <c>type="password"</c> at all and mask in JavaScript. Observed in the wild: a login field whose
    /// accessible name was <c>"Password Hide password"</c> with <c>IsPassword=false</c>, where conversion
    /// went ahead and rewrote what the user typed.
    ///
    /// So an edit control whose accessible name or automation id says "password" is treated as one. This
    /// deliberately over-blocks: the cost of a false positive is no auto-fix in a box labelled *password*,
    /// which is what the user wants there anyway; the cost of a false negative is rewriting a credential.
    /// </summary>
    private static bool UiaLooksLikePasswordField()
    {
        if (_uiaBroken) return false;
        try
        {
            _uia ??= new Interop.UIAutomationClient.CUIAutomation();
            var el = _uia.GetFocusedElement();
            if (el is null) return false;
            if (el.CurrentControlType != UiaEditControlType) return false;   // only text inputs
            return LooksLikePassword(el.CurrentName) || LooksLikePassword(el.CurrentAutomationId);
        }
        catch (Exception ex)
        {
            Diagnostics.Log("secure: UIA name check failed: " + ex.Message);
            return false;
        }
    }

    private const int UiaEditControlType = 50004;   // UIA_EditControlTypeId

    /// <summary>
    /// Password wording in the languages this app's users are most likely to meet — the interface language
    /// is irrelevant here, since the label comes from whatever page they are on.
    /// </summary>
    private static readonly string[] PasswordWords =
    {
        "password", "passwd", "passcode",
        "пароль",       // ru/uk/be
        "passwort",     // de
        "mot de passe", // fr
        "contraseña",   // es
        "senha",        // pt
        "hasło",        // pl
        "密码", "パスワード", "비밀번호",
    };

    internal static bool LooksLikePassword(string? label) =>
        !string.IsNullOrWhiteSpace(label) &&
        PasswordWords.Any(w => label.Contains(w, StringComparison.OrdinalIgnoreCase));

    /// <summary>The focused control of the foreground thread (falls back to the foreground window).</summary>
    private static IntPtr FocusedWindow()
    {
        var gti = new GUITHREADINFO { cbSize = (uint)Marshal.SizeOf<GUITHREADINFO>() };
        if (GetGUIThreadInfo(0, ref gti) && gti.hwndFocus != IntPtr.Zero) return gti.hwndFocus;
        return GetForegroundWindow();
    }

    /// <summary>A classic EDIT/RichEdit control created with ES_PASSWORD.</summary>
    private static bool HasPasswordStyle(IntPtr hwnd)
    {
        const int GWL_STYLE = -16, ES_PASSWORD = 0x0020;
        var cls = new StringBuilder(64);
        GetClassNameW(hwnd, cls, cls.Capacity);
        var name = cls.ToString();
        if (!name.Contains("Edit", StringComparison.OrdinalIgnoreCase)) return false;
        return (GetWindowLongW(hwnd, GWL_STYLE) & ES_PASSWORD) != 0;
    }

    /// <summary>The MSAA focused object reports STATE_SYSTEM_PROTECTED (browser password inputs).</summary>
    private static bool MsaaProtected(IntPtr hwnd)
    {
        const uint OBJID_CLIENT = 0xFFFFFFFC;
        const int STATE_SYSTEM_PROTECTED = 0x20000000;
        const int CHILDID_SELF = 0;

        var iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71"); // IID_IAccessible
        if (AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out object? acc) != 0 || acc is null)
            return false;

        // accFocus gives either a child id (int) or the focused IAccessible itself.
        object target = acc;
        object childId = CHILDID_SELF;
        var focused = Invoke(acc, "accFocus", null);
        if (focused is int id) childId = id;
        else if (focused is not null && Marshal.IsComObject(focused)) target = focused;

        var state = Invoke(target, "accState", new[] { childId });
        return state is int s && (s & STATE_SYSTEM_PROTECTED) != 0;
    }

    /// <summary>Call an IDispatch property by name — avoids needing an IAccessible interop type.</summary>
    private static object? Invoke(object com, string member, object?[]? args)
    {
        try
        {
            return com.GetType().InvokeMember(member, BindingFlags.GetProperty, null, com, args);
        }
        catch
        {
            return null; // not all providers implement every member
        }
    }

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO
    {
        public uint cbSize, flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }

    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO gti);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder cls, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetWindowLongPtrW")]
    private static extern int GetWindowLongW(IntPtr hWnd, int index);
    [DllImport("oleacc.dll")]
    private static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid,
        [MarshalAs(UnmanagedType.IUnknown)] out object? obj);
}

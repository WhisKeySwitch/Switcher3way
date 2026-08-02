using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace Switcher3way.App;

/// <summary>
/// Whether the focused control is a password field — auto and manual conversion must never rewrite
/// in one, including in-browser login fields the denied-apps list can't catch.
///
/// The WinForms/WPF build used <c>System.Windows.Automation</c>, which went away with the WPF app
/// model. This replacement uses two cheap, dependency-free checks on the focused window:
///   1. a classic Win32 edit control with the <c>ES_PASSWORD</c> style, and
///   2. the MSAA (oleacc) focused object carrying <c>STATE_SYSTEM_PROTECTED</c> — this is what
///      catches password &lt;input&gt;s in Chromium/Firefox/Electron, which mark them protected.
/// MSAA is reached through IDispatch by name, so no interop assembly is needed.
///
/// Best-effort by design: any failure returns false (the denied-apps list still guards password
/// *managers*), but a positive result always suppresses conversion.
/// </summary>
internal static class SecureField
{
    public static bool IsFocusedPassword()
    {
        try
        {
            IntPtr focus = FocusedWindow();
            if (focus == IntPtr.Zero) return false;
            return HasPasswordStyle(focus) || MsaaProtected(focus);
        }
        catch
        {
            return false; // never let detection block or crash conversion
        }
    }

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

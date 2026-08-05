using System.Reflection;
using System.Runtime.InteropServices;

namespace Switcher3way.App;

/// <summary>
/// Where the text cursor is, for apps that expose no classic Win32 caret — Chrome, Electron, VS Code,
/// WinUI text boxes. Those all publish an accessibility tree, so the caret can be read from it even
/// though <c>GetGUIThreadInfo</c> reports nothing.
///
/// This uses MSAA (<c>AccessibleObjectFromWindow</c> + late-bound IDispatch), the same approach
/// <see cref="SecureField"/> already relies on, rather than the UI Automation COM interfaces: it needs no
/// hand-written vtables and no extra dependency.
///
/// Measured on this machine: **VS Code** answers <c>OBJID_CARET</c> with a real rect (1x20 at the text
/// position) and **Chrome** exposes the caret object as well — the Chromium/Electron family the chip used
/// to mis-place. **WinUI** text boxes answer nothing, because WinUI is a pure UI Automation provider with
/// no MSAA server; those keep falling back to the window anchor, which is what the app's own Settings
/// window does. Reaching them would need real UIA interop.
///
/// Two levels, because providers vary in what they expose:
///   1. <c>OBJID_CARET</c> — the caret itself. Exact, when available.
///   2. the focused element's own rectangle — not the caret, but the right text field, which still puts
///      the chip against the text the user is looking at rather than in a window corner.
/// </summary>
internal static class AccessibleCaret
{
    private const uint OBJID_CARET = 0xFFFFFFF8;
    private const uint OBJID_CLIENT = 0xFFFFFFFC;
    private const int CHILDID_SELF = 0;
    private static readonly Guid IID_IAccessible = new("618736e0-3c3d-11cf-810c-00aa00389b71");

    /// <summary>Screen rectangle of the caret, or null when the app exposes none.</summary>
    public static (int X, int Y, int W, int H)? CaretRect(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        try
        {
            var iid = IID_IAccessible;
            if (AccessibleObjectFromWindow(hwnd, OBJID_CARET, ref iid, out object? acc) != 0 || acc is null)
                return null;
            var rect = Location(acc, CHILDID_SELF);
            // Providers answer with a caret object even when no text field has focus, reporting (0,0,0x0)
            // — measured in Chrome. A live caret has height and is not at the screen origin; VS Code, for
            // instance, reports a 1x20 rect at the text position.
            return rect is { H: > 0 } && (rect.Value.X != 0 || rect.Value.Y != 0) ? rect : null;
        }
        catch (Exception ex)
        {
            Diagnostics.Log("caret: MSAA caret query failed: " + ex.Message);
            return null;
        }
    }

    /// <summary>Screen rectangle of the focused element (the text field), or null.</summary>
    public static (int X, int Y, int W, int H)? FocusedRect(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        try
        {
            var iid = IID_IAccessible;
            if (AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out object? acc) != 0 || acc is null)
                return null;

            // accFocus returns either a child id or the focused object itself.
            object target = acc;
            object childId = CHILDID_SELF;
            var focused = Get(acc, "accFocus", null);
            if (focused is int id) childId = id;
            else if (focused is not null && Marshal.IsComObject(focused)) target = focused;

            var rect = Location(target, childId);
            return rect is { W: > 0, H: > 0 } ? rect : null;
        }
        catch (Exception ex)
        {
            Diagnostics.Log("caret: MSAA focus query failed: " + ex.Message);
            return null;
        }
    }

    /// <summary>
    /// <c>IAccessible::accLocation</c> through late binding. It returns four by-ref values, so the call
    /// needs a ParameterModifier — otherwise the outputs are silently dropped.
    /// </summary>
    private static (int X, int Y, int W, int H)? Location(object acc, object childId)
    {
        object?[] args = { 0, 0, 0, 0, childId };
        var byRef = new ParameterModifier(5);
        byRef[0] = byRef[1] = byRef[2] = byRef[3] = true;
        try
        {
            acc.GetType().InvokeMember("accLocation", BindingFlags.InvokeMethod, null, acc, args,
                                       new[] { byRef }, null, null);
        }
        catch
        {
            return null;   // provider does not implement it for this object
        }
        if (args[0] is not int x || args[1] is not int y || args[2] is not int w || args[3] is not int h)
            return null;
        return (x, y, w, h);
    }

    private static object? Get(object com, string member, object?[]? args)
    {
        try { return com.GetType().InvokeMember(member, BindingFlags.GetProperty, null, com, args); }
        catch { return null; }
    }

    [DllImport("oleacc.dll")]
    private static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid,
        [MarshalAs(UnmanagedType.IUnknown)] out object? obj);
}

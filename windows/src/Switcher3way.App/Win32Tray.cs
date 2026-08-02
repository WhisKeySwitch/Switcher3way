using System.Runtime.InteropServices;

namespace Switcher3way.App;

/// <summary>
/// System-tray icon + context menu implemented directly on Win32 (<c>Shell_NotifyIcon</c> +
/// <c>TrackPopupMenu</c>), owned by a hidden message window.
///
/// Why not a XAML flyout: H.NotifyIcon's WinUI flyout renders but its item clicks never route in an
/// unpackaged tray-only app (no reliable XamlRoot), in either ContextFlyout or PopupMenu mode. A
/// native popup menu is deterministic, needs no XamlRoot, and is what the WinForms build effectively
/// used. The menu is rebuilt on every open, so checkmarks are always live.
///
/// Must be constructed on the UI thread: the WinUI message pump dispatches this window's messages.
/// </summary>
internal sealed class Win32Tray : IDisposable
{
    /// <summary>One menu row. Text "-" is a separator; <see cref="Submenu"/> makes it a submenu.</summary>
    internal sealed record Row(string Text, Action? Action = null, bool? Checked = null,
                               Row[]? Submenu = null, bool Enabled = true)
    {
        public static Row Separator => new("-");
    }

    /// <summary>Set to show a custom (Fluent) menu instead of the native popup; return true if handled.</summary>
    public Func<bool>? CustomMenu { get; set; }

    private readonly Func<Row[]> _build;
    private readonly WndProcDelegate _proc;   // keep alive: the OS holds a raw pointer
    private readonly IntPtr _hwnd;
    private readonly List<Action?> _actions = new();
    private bool _added;
    private IntPtr _hIcon;

    public Win32Tray(Func<Row[]> menuBuilder)
    {
        _build = menuBuilder;
        _proc = WndProc;

        var cls = new WNDCLASSEXW
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_proc),
            hInstance = GetModuleHandleW(null),
            lpszClassName = "Switcher3wayTrayWnd",
        };
        RegisterClassExW(ref cls);

        // A real (never-shown) window rather than message-only: TrackPopupMenu/SetForegroundWindow
        // misbehave with HWND_MESSAGE owners.
        _hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, cls.lpszClassName, "Switcher3way", 0,
                                0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, cls.hInstance, IntPtr.Zero);
    }

    /// <summary>Set (or replace) the tray icon and its tooltip.</summary>
    public void SetIcon(IntPtr hIcon, string tooltip)
    {
        _hIcon = hIcon;
        var data = new NOTIFYICONDATAW
        {
            cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATAW>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP,
            uCallbackMessage = WM_TRAYICON,
            hIcon = hIcon,
            szTip = tooltip.Length > 127 ? tooltip[..127] : tooltip,
        };
        Shell_NotifyIconW(_added ? NIM_MODIFY : NIM_ADD, ref data);
        _added = true;
    }

    // ---- message handling -------------------------------------------------------------------
    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_TRAYICON)
        {
            uint ev = (uint)(lParam.ToInt64() & 0xFFFF);
            if (ev is WM_RBUTTONUP or WM_LBUTTONUP or WM_CONTEXTMENU) ShowMenu();
            return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        // Prefer the Fluent flyout; the native popup remains as a fallback.
        if (CustomMenu is not null && CustomMenu()) return;

        _actions.Clear();
        _actions.Add(null); // id 0 = "nothing chosen"
        IntPtr menu = CreatePopupMenu();
        try
        {
            Populate(menu, _build());

            // Required dance so the popup behaves like a real menu and dismisses correctly.
            SetForegroundWindow(_hwnd);
            GetCursorPos(out POINT pt);
            int cmd = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
                                       pt.x, pt.y, _hwnd, IntPtr.Zero);
            PostMessageW(_hwnd, WM_NULL, IntPtr.Zero, IntPtr.Zero);

            if (cmd > 0 && cmd < _actions.Count) _actions[cmd]?.Invoke();
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    /// <summary>Append rows to <paramref name="menu"/>, registering their actions by command id.</summary>
    private void Populate(IntPtr menu, Row[] rows)
    {
        foreach (var r in rows)
        {
            if (r.Text == "-") { AppendMenuW(menu, MF_SEPARATOR, UIntPtr.Zero, null); continue; }

            if (r.Submenu is { Length: > 0 })
            {
                IntPtr sub = CreatePopupMenu();
                Populate(sub, r.Submenu);
                AppendMenuW(menu, MF_STRING | MF_POPUP, (UIntPtr)(ulong)sub.ToInt64(), r.Text);
                continue;
            }

            _actions.Add(r.Action);
            uint flags = MF_STRING;
            if (r.Checked == true) flags |= MF_CHECKED;
            if (!r.Enabled) flags |= MF_GRAYED;
            AppendMenuW(menu, flags, (UIntPtr)(ulong)(_actions.Count - 1), r.Text);
        }
    }

    public void Dispose()
    {
        if (_added)
        {
            var data = new NOTIFYICONDATAW
            {
                cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATAW>(), hWnd = _hwnd, uID = 1,
            };
            Shell_NotifyIconW(NIM_DELETE, ref data);
            _added = false;
        }
        if (_hwnd != IntPtr.Zero) DestroyWindow(_hwnd);
    }

    // ---- P/Invoke ---------------------------------------------------------------------------
    private const int WM_APP = 0x8000;
    private const uint WM_TRAYICON = WM_APP + 1;
    private const uint WM_NULL = 0x0000;
    private const uint WM_LBUTTONUP = 0x0202;
    private const uint WM_RBUTTONUP = 0x0205;
    private const uint WM_CONTEXTMENU = 0x007B;

    private const uint NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2;
    private const uint NIF_MESSAGE = 0x01, NIF_ICON = 0x02, NIF_TIP = 0x04;

    private const uint MF_STRING = 0x0000, MF_POPUP = 0x0010, MF_SEPARATOR = 0x0800,
                       MF_CHECKED = 0x0008, MF_GRAYED = 0x0001;
    private const uint TPM_RETURNCMD = 0x0100, TPM_RIGHTBUTTON = 0x0002, TPM_NONOTIFY = 0x0080;
    private const int WS_EX_TOOLWINDOW = 0x00000080;

    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x, y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEXW
    {
        public uint cbSize, style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra, cbWndExtra;
        public IntPtr hInstance, hIcon, hCursor, hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID, uFlags, uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState, dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIconW(uint msg, ref NOTIFYICONDATAW data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern ushort RegisterClassExW(ref WNDCLASSEXW cls);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowExW(int exStyle, string cls, string name, uint style,
        int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr hMenu);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenuW(IntPtr hMenu, uint flags, UIntPtr id, string? item);
    [DllImport("user32.dll")]
    private static extern int TrackPopupMenuEx(IntPtr hMenu, uint flags, int x, int y, IntPtr hWnd, IntPtr lptpm);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandleW(string? name);
}

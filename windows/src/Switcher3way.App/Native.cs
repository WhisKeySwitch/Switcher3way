using System.Runtime.InteropServices;
using System.Text;

namespace Switcher3way.App;

/// <summary>Win32 P/Invoke surface for the live loop. Graduated from the proven spike.</summary>
internal static class Native
{
    // ---- Low-level keyboard hook -----------------------------------------------------------
    public const int WH_KEYBOARD_LL = 13;
    public const int WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, WM_SYSKEYDOWN = 0x0104, WM_SYSKEYUP = 0x0105;
    public const uint LLKHF_INJECTED = 0x00000010; // set on synthesized (SendInput) events

    /// <summary>
    /// Stamped into <c>dwExtraInfo</c> on every keystroke this app synthesizes, so the hook can ignore
    /// its own rewrites without ignoring everyone else's injected input.
    ///
    /// The hook used to skip anything carrying <c>LLKHF_INJECTED</c>, which also covers Remote Desktop,
    /// virtual machines, remote-support tools, keyboard remappers and the on-screen keyboard — so the app
    /// was inert wherever input did not come from a directly attached keyboard. The first three of those
    /// are the ones that matter: people type into them on real keyboards and make exactly the wrong-layout
    /// mistake this app fixes. Store certification failed on it twice, testing on a Surface Go 4.
    ///
    /// The cost, accepted: text expanders, macro tools and password-manager auto-type are now visible to
    /// the engine too. Windows offers no way to tell a remote session's keystrokes apart from an
    /// application injecting text, so it is accept-all or reject-all.
    /// </summary>
    public static readonly IntPtr OwnInputTag = new(0x53573357); // "SW3W"

    // ---- Low-level mouse hook (to reset the word buffer on clicks) --------------------------
    public const int WH_MOUSE_LL = 14;
    public const uint WM_LBUTTONDOWN = 0x0201, WM_RBUTTONDOWN = 0x0204, WM_MBUTTONDOWN = 0x0207, WM_XBUTTONDOWN = 0x020B;

    public const uint VK_SHIFT = 0x10, VK_CAPITAL = 0x14, VK_BACK = 0x08;
    public const uint VK_CONTROL = 0x11, VK_MENU = 0x12;

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT
    {
        public uint vkCode, scanCode, flags, time;
        public IntPtr dwExtraInfo;
    }

    public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr GetModuleHandle(string? lpModuleName);
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    // ---- Foreground-change event hook (per-app layout memory) ------------------------------
    public const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    public const uint WINEVENT_OUTOFCONTEXT = 0x0000;

    public delegate void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventProc lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    // ---- Message pump ----------------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int pt_x, pt_y; }
    [DllImport("user32.dll")] public static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG lpMsg);
    [DllImport("user32.dll")] public static extern IntPtr DispatchMessage(ref MSG lpMsg);
    [DllImport("user32.dll")] public static extern void PostQuitMessage(int nExitCode);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    public const int ATTACH_PARENT_PROCESS = -1;
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AttachConsole(int dwProcessId);

    // ---- Layout enumeration + rendering ----------------------------------------------------
    [DllImport("user32.dll")] public static extern int GetKeyboardLayoutList(int nBuff, [Out] IntPtr[]? lpList);
    [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint idThread);

    public const uint MAPVK_VK_TO_VSC = 0;
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyEx(uint uCode, uint uMapType, IntPtr dwhkl);

    [DllImport("user32.dll")]
    public static extern int ToUnicodeEx(uint wVirtKey, uint wScanCode, byte[] lpKeyState,
        [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pwszBuff, int cchBuff, uint wFlags, IntPtr dwhkl);

    // ---- Foreground app + switching --------------------------------------------------------
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr hWnd, System.Text.StringBuilder buf, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hWnd, System.Text.StringBuilder buf, int max);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    public const uint WM_INPUTLANGCHANGEREQUEST = 0x0050;
    public const uint KLF_SETFORPROCESS = 0x00000100;
    public static readonly IntPtr INPUTLANGCHANGE_FORWARD = (IntPtr)2;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern IntPtr ActivateKeyboardLayout(IntPtr hkl, uint Flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool QueryFullProcessImageName(IntPtr h, uint flags, StringBuilder exe, ref uint size);

    // ---- Text rewrite via SendInput --------------------------------------------------------
    public const int INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004;

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public int type; public KEYBDINPUT ki; public int _pad0, _pad1; }
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}

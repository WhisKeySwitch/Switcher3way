using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace Switcher3way.App;

/// <summary>
/// The conversion feedback chip (design 1f): a small dark pill that appears just under the corrected
/// word showing <c>ghbdsn → привіт</c> plus the undo hint, then fades away. Before this, a successful
/// fix produced no feedback at all.
///
/// It is a layered, click-through, never-activated topmost Win32 window drawn with GDI+ — a WinUI
/// window can't be click-through/no-focus, and this must never steal focus from typing. Rounded
/// corners come from a window region; the fade uses the layered-window alpha.
///
/// Create and drive on the UI thread.
/// </summary>
internal sealed class CaretChip : IDisposable
{
    private const int FadeInMs = 200, HoldMs = 1600, FadeOutMs = 120, TickMs = 15;

    private readonly IntPtr _hwnd;
    private readonly WndProc _proc;
    private readonly DispatcherQueueTimer _timer;

    private string _original = "", _converted = "", _trigger = "Ctrl Ctrl";
    private int _elapsed;
    private Phase _phase = Phase.Hidden;
    private enum Phase { Hidden, FadeIn, Hold, FadeOut }

    // Layout metrics (design 1f) at 100% scale; multiplied by the monitor's DPI scale.
    private const int BasePadX = 11, BasePadY = 7, BaseGap = 9, BaseRadius = 6;
    private float _scale = 1f;
    private int PadX => (int)(BasePadX * _scale);
    private int PadY => (int)(BasePadY * _scale);
    private int Gap => (int)(BaseGap * _scale);
    private int Radius => (int)(BaseRadius * _scale);

    public CaretChip()
    {
        _proc = WndProcImpl;
        var cls = new WNDCLASSEXW
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_proc),
            hInstance = GetModuleHandleW(null),
            lpszClassName = "Switcher3wayChip",
        };
        RegisterClassExW(ref cls);

        _hwnd = CreateWindowExW(
            WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
            cls.lpszClassName, "", WS_POPUP, 0, 0, 10, 10,
            IntPtr.Zero, IntPtr.Zero, cls.hInstance, IntPtr.Zero);

        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(TickMs);
        _timer.Tick += (_, _) => Tick();
    }

    /// <summary>Show the chip for one conversion. Re-showing while visible restarts it.</summary>
    public void Show(string original, string converted, string triggerLabel)
    {
        _original = original;
        _converted = converted;
        _trigger = triggerLabel;

        // Match the DPI of the monitor we're about to appear on (the app being typed into).
        IntPtr target = GetForegroundWindow();
        uint dpi = target != IntPtr.Zero ? GetDpiForWindow(target) : 96;
        _scale = dpi <= 0 ? 1f : dpi / 96f;

        var size = Measure();
        // The caret sits after the corrected word, so shift left by roughly the word's on-screen
        // width to sit under its start rather than trailing off to the right.
        var (x, y) = PositionFor(size, LeftShiftForWord());
        SetWindowPos(_hwnd, HWND_TOPMOST, x, y, size.Width, size.Height, SWP_NOACTIVATE);

        // Rounded corners via a window region (recreated when the size changes).
        IntPtr rgn = CreateRoundRectRgn(0, 0, size.Width + 1, size.Height + 1, Radius * 2, Radius * 2);
        SetWindowRgn(_hwnd, rgn, false); // the OS owns the region after this

        SetAlpha(0);
        ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
        InvalidateRect(_hwnd, IntPtr.Zero, true);

        _elapsed = 0;
        _phase = Phase.FadeIn;
        _timer.Start();
    }

    public void Hide()
    {
        _timer.Stop();
        _phase = Phase.Hidden;
        ShowWindow(_hwnd, SW_HIDE);
    }

    private void Tick()
    {
        _elapsed += TickMs;
        switch (_phase)
        {
            case Phase.FadeIn:
                if (_elapsed >= FadeInMs) { SetAlpha(255); _phase = Phase.Hold; _elapsed = 0; }
                else SetAlpha((byte)(255 * _elapsed / FadeInMs));
                break;
            case Phase.Hold:
                if (_elapsed >= HoldMs) { _phase = Phase.FadeOut; _elapsed = 0; }
                break;
            case Phase.FadeOut:
                if (_elapsed >= FadeOutMs) Hide();
                else SetAlpha((byte)(255 - 255 * _elapsed / FadeOutMs));
                break;
            default:
                Hide();
                break;
        }
    }

    private void SetAlpha(byte a) => SetLayeredWindowAttributes(_hwnd, 0, a, LWA_ALPHA);

    // ---- layout & drawing -------------------------------------------------------------------
    // Pixel-unit fonts scaled by the monitor DPI, so the chip is the designed physical size.
    private Font TextFont => new("Segoe UI", 13 * _scale, GraphicsUnit.Pixel);
    private Font MonoFont => new("Consolas", 13 * _scale, GraphicsUnit.Pixel);
    private Font MonoStrike => new("Consolas", 13 * _scale, FontStyle.Strikeout, GraphicsUnit.Pixel);
    private Font HintFont => new("Segoe UI", 11 * _scale, GraphicsUnit.Pixel);
    private Font KeyFont => new("Consolas", 11 * _scale, GraphicsUnit.Pixel);

    private Size Measure()
    {
        using var bmp = new Bitmap(1, 1);
        using var g = Graphics.FromImage(bmp);
        using var mono = MonoFont; using var hint = HintFont; using var key = KeyFont;

        int w = PadX
              + S(12) + Gap                                                 // tick
              + Ceil(g.MeasureString(_original, mono).Width) + Gap          // struck-through original
              + S(12) + Gap                                                 // arrow
              + Ceil(g.MeasureString(_converted, mono).Width) + Gap         // converted
              + S(1) + Gap                                                  // divider
              + Ceil(g.MeasureString(_trigger, key).Width) + S(12)          // keycap (+ padding)
              + Ceil(g.MeasureString(" undo", hint).Width)
              + PadX;
        int h = Ceil(g.MeasureString("Ay", mono).Height) + PadY * 2;
        return new Size(w, Math.Max(h, (int)(30 * _scale)));
    }

    private static int Ceil(float f) => (int)Math.Ceiling(f);
    /// <summary>Scale a design-pixel value to the current monitor's DPI.</summary>
    private int S(float v) => (int)Math.Round(v * _scale);

    /// <summary>
    /// How far left of the caret to start the chip: about the corrected word's on-screen width (the
    /// caret is just past it), measured in our own font as a proxy for the target app's, plus a
    /// little slack. Capped so a long word can't push the chip off to the left.
    /// </summary>
    private int LeftShiftForWord()
    {
        using var bmp = new Bitmap(1, 1);
        using var g = Graphics.FromImage(bmp);
        using var mono = MonoFont;
        int wordWidth = Ceil(g.MeasureString(_converted, mono).Width);
        return Math.Min(wordWidth + S(16), S(260));
    }

    /// <summary>
    /// Just below the caret, trying four sources in descending accuracy. The classic Win32 caret covers
    /// Notepad and Win32 edits; apps built on WinUI, Chromium or Electron expose none, so the caret comes
    /// from the accessibility tree instead; failing that the focused *field* still puts the chip against
    /// the right text; and only then does it fall back to a window corner.
    /// </summary>
    /// <summary>
    /// Diagnostics for the position chain (`diagcaret`): what the foreground window is, what each source
    /// answered, and where the chip would land. The chip only appears after a real conversion, and
    /// synthetic keystrokes are ignored by the hook, so this is the only way to test placement.
    /// </summary>
    /// <param name="target">
    /// Query this window instead of the foreground one. Needed to test the accessibility tiers when a
    /// window cannot be brought to the front — Windows refuses foreground changes from a background
    /// process, and <c>GetGUIThreadInfo(0)</c> always reads the foreground thread.
    /// </param>
    internal static void Probe(IntPtr target = default)
    {
        IntPtr fg = target != IntPtr.Zero ? target : GetForegroundWindow();
        var cls = new System.Text.StringBuilder(96);
        var title = new System.Text.StringBuilder(96);
        GetClassNameW(fg, cls, cls.Capacity);
        GetWindowTextW(fg, title, title.Capacity);

        var gti = new GUITHREADINFO { cbSize = (uint)Marshal.SizeOf<GUITHREADINFO>() };
        bool haveGti = GetGUIThreadInfo(0, ref gti);
        // Same handle production uses: the focused child. A WinUI window answers nothing at the top level
        // but returns a real rect for the child that has focus, so overriding this with a window handle
        // would test the wrong thing.
        IntPtr focus = haveGti && gti.hwndFocus != IntPtr.Zero ? gti.hwndFocus : fg;

        Diagnostics.LogAlways($"diagcaret: fg=0x{fg:X} class={cls} title=\"{title}\" gti={haveGti} " +
                              $"hwndFocus=0x{(haveGti ? gti.hwndFocus : IntPtr.Zero):X} hwndCaret=0x{(haveGti ? gti.hwndCaret : IntPtr.Zero):X}");
        // Log against the same handle PositionFor uses (the focused child), and the top-level window too —
        // they answer differently: a WinUI window returns nothing at the top level but a real rect for the
        // focused child.
        Diagnostics.LogAlways($"diagcaret:   focus=0x{focus:X} caret={Fmt(AccessibleCaret.CaretRect(focus))} " +
                              $"field={Fmt(AccessibleCaret.FocusedRect(focus))}");
        if (target != IntPtr.Zero && target != focus)
            Diagnostics.LogAlways($"diagcaret:   toplevel=0x{target:X} caret={Fmt(AccessibleCaret.CaretRect(target))} " +
                                  $"field={Fmt(AccessibleCaret.FocusedRect(target))}");
        var pos = PositionFor(new Size(200, 40), 60);
        Diagnostics.LogAlways($"diagcaret:   placed=({pos.X},{pos.Y})");

        static string Fmt((int X, int Y, int W, int H)? r) =>
            r is { } v ? $"({v.X},{v.Y},{v.W}x{v.H})" : "none";
    }

    internal static (int X, int Y) PositionFor(Size size, int leftShift)
    {
        var gti = new GUITHREADINFO { cbSize = (uint)Marshal.SizeOf<GUITHREADINFO>() };
        bool haveGti = GetGUIThreadInfo(0, ref gti);

        // 1. classic caret
        if (haveGti && gti.hwndCaret != IntPtr.Zero
            && (gti.rcCaret.right - gti.rcCaret.left) >= 0 && gti.rcCaret.bottom > 0)
        {
            var pt = new POINT { x = gti.rcCaret.left, y = gti.rcCaret.bottom };
            if (ClientToScreen(gti.hwndCaret, ref pt))
            {
                var placed = Clamp(pt.x - leftShift, pt.y + 6, size);
                Diagnostics.Log($"chip: caret screen=({pt.x},{pt.y}) rcCaret=({gti.rcCaret.left},{gti.rcCaret.top},{gti.rcCaret.right},{gti.rcCaret.bottom}) " +
                                $"shift={leftShift} size={size.Width}x{size.Height} placed=({placed.X},{placed.Y})");
                return placed;
            }
        }

        IntPtr focus = haveGti && gti.hwndFocus != IntPtr.Zero ? gti.hwndFocus : GetForegroundWindow();

        // 2. caret from the accessibility tree (Chrome, Electron, VS Code, WinUI text boxes)
        if (AccessibleCaret.CaretRect(focus) is { } c)
        {
            var placed = Clamp(c.X - leftShift, c.Y + c.H + 6, size);
            Diagnostics.Log($"chip: a11y caret=({c.X},{c.Y},{c.W}x{c.H}) shift={leftShift} placed=({placed.X},{placed.Y})");
            return placed;
        }

        // 3. the focused text field: not the caret, but the right control
        if (AccessibleCaret.FocusedRect(focus) is { } f)
        {
            var placed = Clamp(f.X + 4, f.Y + f.H + 6, size);
            Diagnostics.Log($"chip: a11y focused field=({f.X},{f.Y},{f.W}x{f.H}) placed=({placed.X},{placed.Y})");
            return placed;
        }

        // 4. the focused window
        IntPtr fg = GetForegroundWindow();
        if (fg != IntPtr.Zero && GetWindowRect(fg, out RECT wr))
        {
            Diagnostics.Log("chip: no caret and no accessible field — anchored to the focused window");
            return Clamp(wr.left + 24, wr.bottom - size.Height - 24, size);
        }

        Diagnostics.Log("chip: no caret or window — anchored bottom-right");
        return Clamp(GetSystemMetrics(SM_CXSCREEN) - size.Width - 24,
                     GetSystemMetrics(SM_CYSCREEN) - size.Height - 64, size);
    }

    /// <summary>Keep the chip on screen.</summary>
    private static (int X, int Y) Clamp(int x, int y, Size size)
    {
        int sw = GetSystemMetrics(SM_CXSCREEN), sh = GetSystemMetrics(SM_CYSCREEN);
        return (Math.Max(0, Math.Min(x, sw - size.Width)), Math.Max(0, Math.Min(y, sh - size.Height)));
    }

    private void Paint(IntPtr hdc, Rectangle bounds)
    {
        using var g = Graphics.FromHdc(hdc);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

        using var bg = new SolidBrush(Color.FromArgb(0x2C, 0x2C, 0x2C));
        g.FillRectangle(bg, bounds);

        using var mono = MonoFont; using var strike = MonoStrike;
        using var hint = HintFont; using var key = KeyFont;
        using var grayB = new SolidBrush(Color.FromArgb(0x9A, 0x9A, 0x9A));
        using var arrowB = new SolidBrush(Color.FromArgb(0x7A, 0x7A, 0x7A));
        using var whiteB = new SolidBrush(Color.White);
        using var hintB = new SolidBrush(Color.FromArgb(0xA0, 0xA0, 0xA0));
        using var keyB = new SolidBrush(Color.FromArgb(0xE0, 0xE0, 0xE0));

        float mid = bounds.Height / 2f;
        float x = PadX;

        // success tick
        float tick = S(12);
        using (var green = new SolidBrush(Color.FromArgb(0x6C, 0xCB, 0x5F)))
            g.FillEllipse(green, x, mid - tick / 2, tick, tick);
        using (var pen = new Pen(Color.FromArgb(0x14, 0x32, 0x0F), 1.6f * _scale))
        {
            g.DrawLines(pen, new[]
            {
                new PointF(x + tick * 0.27f, mid),
                new PointF(x + tick * 0.43f, mid + tick * 0.18f),
                new PointF(x + tick * 0.73f, mid - tick * 0.20f),
            });
        }
        x += tick + Gap;

        void Draw(string s, Font f, Brush b)
        {
            var sz = g.MeasureString(s, f);
            g.DrawString(s, f, b, x, mid - sz.Height / 2f);
            x += Ceil(sz.Width);
        }

        using var text = TextFont;
        Draw(_original, strike, grayB);
        x += Gap;
        Draw("→", text, arrowB);
        x += Gap;
        Draw(_converted, mono, whiteB);
        x += Gap;

        using (var div = new SolidBrush(Color.FromArgb(0x4A, 0x4A, 0x4A)))
            g.FillRectangle(div, x, mid - S(7), S(1), S(14));
        x += S(1) + Gap;

        // keycap for the configured trigger, then " undo"
        var keySize = g.MeasureString(_trigger, key);
        using (var cap = new SolidBrush(Color.FromArgb(0x3D, 0x3D, 0x3D)))
            FillRounded(g, cap, new RectangleF(x, mid - keySize.Height / 2f - S(2),
                                               keySize.Width + S(10), keySize.Height + S(4)), S(3));
        g.DrawString(_trigger, key, keyB, x + S(5), mid - keySize.Height / 2f);
        x += Ceil(keySize.Width) + S(12);
        Draw(" undo", hint, hintB);
    }

    private static void FillRounded(Graphics g, Brush b, RectangleF r, float radius)
    {
        using var path = new GraphicsPath();
        float d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(b, path);
    }

    private IntPtr WndProcImpl(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_PAINT)
        {
            IntPtr hdc = BeginPaint(hWnd, out PAINTSTRUCT ps);
            try
            {
                GetClientRect(hWnd, out RECT rc);
                Paint(hdc, new Rectangle(0, 0, rc.right - rc.left, rc.bottom - rc.top));
            }
            catch { /* never let painting crash the app */ }
            finally { EndPaint(hWnd, ref ps); }
            return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        _timer.Stop();
        if (_hwnd != IntPtr.Zero) DestroyWindow(_hwnd);
    }

    // ---- P/Invoke ---------------------------------------------------------------------------
    private const int WS_EX_LAYERED = 0x00080000, WS_EX_TRANSPARENT = 0x00000020,
                      WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x00000080,
                      WS_EX_TOPMOST = 0x00000008;
    private const uint WS_POPUP = 0x80000000;
    private const uint WM_PAINT = 0x000F;
    private const int SW_HIDE = 0, SW_SHOWNOACTIVATE = 4;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint LWA_ALPHA = 0x02;
    private const int SM_CXSCREEN = 0, SM_CYSCREEN = 1;
    private static readonly IntPtr HWND_TOPMOST = new(-1);

    private delegate IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct PAINTSTRUCT
    {
        public IntPtr hdc; public bool fErase; public RECT rcPaint;
        public bool fRestore, fIncUpdate;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] rgbReserved;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO
    {
        public uint cbSize, flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
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

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern ushort RegisterClassExW(ref WNDCLASSEXW c);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowExW(int ex, string cls, string name, uint style,
        int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
    [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr h, IntPtr rect, bool erase);
    [DllImport("user32.dll")] private static extern IntPtr BeginPaint(IntPtr h, out PAINTSTRUCT ps);
    [DllImport("user32.dll")] private static extern bool EndPaint(IntPtr h, ref PAINTSTRUCT ps);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO gti);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hWnd);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int l, int t, int r, int b, int w, int h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandleW(string? n);
}

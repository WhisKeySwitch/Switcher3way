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

    private string _original = "", _converted = "", _trigger = "F9";
    private int _elapsed;
    private Phase _phase = Phase.Hidden;
    private enum Phase { Hidden, FadeIn, Hold, FadeOut }

    // Layout metrics (design 1f).
    private const int PadX = 11, PadY = 7, Gap = 9, Radius = 6;

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

        var size = Measure();
        var (x, y) = PositionFor(size);
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
    private static Font TextFont => new("Segoe UI", 9.75f);                       // ~13px
    private static Font MonoFont => new("Consolas", 9.75f);
    private static Font MonoStrike => new("Consolas", 9.75f, FontStyle.Strikeout);
    private static Font HintFont => new("Segoe UI", 8.25f);                       // ~11px
    private static Font KeyFont => new("Consolas", 8.25f);

    private Size Measure()
    {
        using var bmp = new Bitmap(1, 1);
        using var g = Graphics.FromImage(bmp);
        using var mono = MonoFont; using var hint = HintFont; using var key = KeyFont;

        int w = PadX
              + 12 + Gap                                                   // tick
              + Ceil(g.MeasureString(_original, mono).Width) + Gap          // struck-through original
              + 10 + Gap                                                    // arrow
              + Ceil(g.MeasureString(_converted, mono).Width) + Gap         // converted
              + 1 + Gap                                                     // divider
              + Ceil(g.MeasureString(_trigger, key).Width) + 12             // keycap (+ padding)
              + Ceil(g.MeasureString(" undo", hint).Width)
              + PadX;
        int h = Ceil(g.MeasureString("Ay", mono).Height) + PadY * 2;
        return new Size(w, Math.Max(h, 30));
    }

    private static int Ceil(float f) => (int)Math.Ceiling(f);

    /// <summary>Just below the caret; falls back to the mouse pointer when no caret is exposed.</summary>
    private static (int X, int Y) PositionFor(Size size)
    {
        var gti = new GUITHREADINFO { cbSize = (uint)Marshal.SizeOf<GUITHREADINFO>() };
        if (GetGUIThreadInfo(0, ref gti) && gti.hwndCaret != IntPtr.Zero)
        {
            var pt = new POINT { x = gti.rcCaret.left, y = gti.rcCaret.bottom };
            if (ClientToScreen(gti.hwndCaret, ref pt)) return Clamp(pt.x, pt.y + 6, size);
        }
        GetCursorPos(out POINT cur);
        return Clamp(cur.x + 12, cur.y + 20, size);
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
        using (var green = new SolidBrush(Color.FromArgb(0x6C, 0xCB, 0x5F)))
            g.FillEllipse(green, x, mid - 6, 12, 12);
        using (var pen = new Pen(Color.FromArgb(0x14, 0x32, 0x0F), 1.6f))
        {
            g.DrawLines(pen, new[]
            {
                new PointF(x + 3.2f, mid),
                new PointF(x + 5.2f, mid + 2.2f),
                new PointF(x + 8.8f, mid - 2.4f),
            });
        }
        x += 12 + Gap;

        void Draw(string s, Font f, Brush b)
        {
            var sz = g.MeasureString(s, f);
            g.DrawString(s, f, b, x, mid - sz.Height / 2f);
            x += Ceil(sz.Width);
        }

        Draw(_original, strike, grayB);
        x += Gap;
        Draw("→", TextFontCached(), arrowB);
        x += Gap;
        Draw(_converted, mono, whiteB);
        x += Gap;

        using (var div = new SolidBrush(Color.FromArgb(0x4A, 0x4A, 0x4A)))
            g.FillRectangle(div, x, mid - 7, 1, 14);
        x += 1 + Gap;

        // keycap for the configured trigger, then " undo"
        var keySize = g.MeasureString(_trigger, key);
        using (var cap = new SolidBrush(Color.FromArgb(0x3D, 0x3D, 0x3D)))
            FillRounded(g, cap, new RectangleF(x, mid - keySize.Height / 2f - 2, keySize.Width + 10, keySize.Height + 4), 3);
        g.DrawString(_trigger, key, keyB, x + 5, mid - keySize.Height / 2f);
        x += Ceil(keySize.Width) + 12;
        Draw(" undo", hint, hintB);
    }

    private Font? _textFont;
    private Font TextFontCached() => _textFont ??= TextFont;

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
        _textFont?.Dispose();
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
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
    [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr h, IntPtr rect, bool erase);
    [DllImport("user32.dll")] private static extern IntPtr BeginPaint(IntPtr h, out PAINTSTRUCT ps);
    [DllImport("user32.dll")] private static extern bool EndPaint(IntPtr h, ref PAINTSTRUCT ps);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO gti);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int l, int t, int r, int b, int w, int h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandleW(string? n);
}

using System.Drawing;
using System.Drawing.Drawing2D;

namespace Switcher3way.App;

/// <summary>
/// Renders the tray flag icon (Ukraine/Russia bitmaps, an "EN"-style badge fallback) with the dimmed
/// + pause-bars treatment when conversion is off. Lifted from the WinForms TrayApp so the WinUI tray
/// reuses the exact rendering. Icons are cached by "lang:dim".
/// </summary>
internal static class FlagIcon
{
    private static readonly Dictionary<string, Icon> _cache = new();
    private static readonly Dictionary<string, Bitmap?> _images = new();

    public static Icon Make(string lang, bool dim)
    {
        var key = $"{lang}:{dim}";
        if (!_cache.TryGetValue(key, out var ic)) { ic = Build(lang, dim); _cache[key] = ic; }
        return ic;
    }

    private static Icon Build(string lang, bool dim)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            var r = new Rectangle(2, 6, 28, 20);

            var img = FlagImage(lang);
            if (img is not null)
            {
                g.DrawImage(img, r);
            }
            else // unknown language: a coloured badge with the 2-letter code
            {
                using var b = new SolidBrush(Color.FromArgb(0x2B, 0x36, 0x52));
                g.FillRectangle(b, r);
                var code = (lang.Length >= 2 ? lang[..2] : lang).ToUpperInvariant();
                using var f = new Font("Segoe UI", 12, FontStyle.Bold, GraphicsUnit.Pixel);
                using var fb = new SolidBrush(Color.White);
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString(code, f, fb, new RectangleF(r.X, r.Y, r.Width, r.Height), sf);
            }

            using (var pen = new Pen(Color.FromArgb(90, 0, 0, 0))) g.DrawRectangle(pen, r);

            if (dim)
            {
                using var ov = new SolidBrush(Color.FromArgb(150, 110, 110, 110));
                g.FillRectangle(ov, 0, 0, 32, 32);
                using var pb = new SolidBrush(Color.FromArgb(235, 40, 40, 40)); // pause bars
                g.FillRectangle(pb, 11, 10, 3, 12);
                g.FillRectangle(pb, 18, 10, 3, 12);
            }
        }
        IntPtr h = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(h).Clone();
        Native.DestroyIcon(h);
        return icon;
    }

    private static Bitmap? FlagImage(string lang)
    {
        if (_images.TryGetValue(lang, out var cached)) return cached;
        Bitmap? img = null;
        try
        {
            using var s = typeof(FlagIcon).Assembly.GetManifestResourceStream($"{lang}.png");
            if (s is not null) img = new Bitmap(s);
        }
        catch { /* no embedded flag for this language */ }
        _images[lang] = img;
        return img;
    }
}

using System.Diagnostics;
using System.IO;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;

namespace Switcher3way.App;

/// <summary>One running application eligible for the exceptions picker.</summary>
public sealed record RunningApp(string ExeName, string Path, string FriendlyName);

/// <summary>
/// Executable metadata for the exceptions UI: friendly names (from the file's FileDescription
/// version resource), icons extracted at runtime, and the list of running apps that own a visible
/// top-level window. Everything is best-effort — an unreadable process must never break the list.
/// </summary>
internal static class AppInfo
{
    private static readonly Dictionary<string, string> _names = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Dictionary<string, BitmapImage?> _icons = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Friendly name for an executable path (FileDescription, else the bare file name).</summary>
    public static string FriendlyName(string path)
    {
        if (_names.TryGetValue(path, out var cached)) return cached;
        string name = Path.GetFileNameWithoutExtension(path);
        try
        {
            var d = FileVersionInfo.GetVersionInfo(path).FileDescription;
            if (!string.IsNullOrWhiteSpace(d)) name = d.Trim();
        }
        catch { /* unreadable — keep the file name */ }
        _names[path] = name;
        return name;
    }

    /// <summary>
    /// The executable's icon as an image source, or null when it can't be extracted. The bitmap is
    /// returned immediately and fills in asynchronously, so callers can bind it straight away.
    /// </summary>
    public static BitmapImage? Icon(string path)
    {
        if (_icons.TryGetValue(path, out var cached)) return cached;
        BitmapImage? img = null;
        try
        {
            using var ico = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (ico is not null)
            {
                using var bmp = ico.ToBitmap();
                using var ms = new MemoryStream();
                bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                var bytes = ms.ToArray();

                img = new BitmapImage();
                var ras = new InMemoryRandomAccessStream();
                _ = FillAsync(ras, bytes, img); // fire-and-forget: the bitmap updates itself
            }
        }
        catch { /* no icon for this executable */ }
        _icons[path] = img;
        return img;
    }

    private static async Task FillAsync(InMemoryRandomAccessStream ras, byte[] bytes, BitmapImage img)
    {
        try
        {
            using var writer = new DataWriter(ras.GetOutputStreamAt(0));
            writer.WriteBytes(bytes);
            await writer.StoreAsync();
            ras.Seek(0);
            await img.SetSourceAsync(ras);
        }
        catch { /* leave the image blank */ }
    }

    /// <summary>Path of a running process with this exe name, if one is running (for icons/names).</summary>
    public static string? PathForExeName(string exeName)
    {
        var bare = Path.GetFileNameWithoutExtension(exeName);
        foreach (var p in Process.GetProcessesByName(bare))
        {
            try { var f = p.MainModule?.FileName; if (f is not null) return f; }
            catch { /* elevated/protected process — no access */ }
            finally { p.Dispose(); }
        }
        return null;
    }

    /// <summary>
    /// Running apps that own a visible top-level window, de-duplicated by executable, excluding
    /// <paramref name="exclude"/> exe names (already-listed apps) and this app itself.
    /// </summary>
    public static List<RunningApp> RunningApps(IEnumerable<string> exclude)
    {
        var skip = new HashSet<string>(exclude, StringComparer.OrdinalIgnoreCase);
        var self = Path.GetFileName(Environment.ProcessPath ?? "");
        var byExe = new Dictionary<string, RunningApp>(StringComparer.OrdinalIgnoreCase);

        foreach (var p in Process.GetProcesses())
        {
            try
            {
                if (p.MainWindowHandle == IntPtr.Zero) continue;      // no visible top-level window
                var path = p.MainModule?.FileName;
                if (path is null) continue;
                var exe = Path.GetFileName(path);
                if (exe.Equals(self, StringComparison.OrdinalIgnoreCase)) continue;
                if (skip.Contains(exe) || byExe.ContainsKey(exe)) continue;
                byExe[exe] = new RunningApp(exe, path, FriendlyName(path));
            }
            catch { /* access denied (elevated) — skip */ }
            finally { p.Dispose(); }
        }
        return byExe.Values.OrderBy(a => a.FriendlyName, StringComparer.CurrentCultureIgnoreCase).ToList();
    }
}

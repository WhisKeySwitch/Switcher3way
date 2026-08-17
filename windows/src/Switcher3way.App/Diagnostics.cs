using System.IO;

namespace Switcher3way.App;

/// <summary>
/// Opt-in rotating file log (like the macOS <c>rslog</c>): off by default, writes only when the
/// <c>DebugLog</c> setting is on. Rotates at 5 MB (keeps one <c>.1</c> backup). Thread-safe.
/// </summary>
internal static class Diagnostics
{
    private static readonly object Lock = new();
    private static SettingsManager? _settings;
    private const long MaxBytes = 5 * 1024 * 1024;

    public static void Configure(SettingsManager settings) => _settings = settings;

    /// <summary>
    /// `diagnochip` — suppress the on-screen chip. It exists to answer one question: the isolated
    /// rewrite (`diagrewrite`) does not corrupt at sizes where the real manual cycle does, and the
    /// difference is work this process does around the rewrite. The chip animates on a 15 ms timer for
    /// nearly two seconds, which spans the next rewrite in a cycle.
    /// </summary>
    public static bool NoChip { get; set; }

    public static string Dir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Switcher3way", "Logs");
    public static string FilePath => Path.Combine(Dir, "switcher3way.log");

    /// <summary>
    /// Write regardless of the debug-log setting. For failures a user would otherwise never be able
    /// to report — e.g. a XAML window refusing to open in a shipped build, where the app looks
    /// half-dead and the opt-in log isn't on.
    /// </summary>
    public static void LogAlways(string message) => Write(message);

    public static void Log(string message)
    {
        if (_settings is not { DebugLog: true }) return;
        Write(message);
    }

    private static void Write(string message)
    {
        try
        {
            lock (Lock)
            {
                Directory.CreateDirectory(Dir);
                if (File.Exists(FilePath) && new FileInfo(FilePath).Length > MaxBytes)
                {
                    var bak = FilePath + ".1";
                    if (File.Exists(bak)) File.Delete(bak);
                    File.Move(FilePath, bak);
                }
                File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  {message}{Environment.NewLine}");
            }
        }
        catch { /* logging must never crash the app */ }
    }
}

using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Switcher3way.App;

/// <summary>
/// Persisted user settings (JSON at <c>%AppData%\Switcher3way\settings.json</c>) + session-only
/// pause state. Mirrors the macOS master toggle / auto-fix / pause model.
/// </summary>
public sealed class SettingsManager
{
    public bool Enabled { get; set; } = true;
    public bool AutoFix { get; set; } = true;
    public bool PerAppMemory { get; set; } = true;
    public bool DebugLog { get; set; }
    /// <summary>Virtual-key code of the manual-conversion trigger (default F9 = 0x78).</summary>
    public int TriggerKey { get; set; } = 0x78;
    /// <summary>If true, trigger on a quick DOUBLE tap of <see cref="TriggerKey"/> (e.g. double Shift).</summary>
    public bool TriggerDoubleTap { get; set; }
    public DateTime? PausedUntil { get; set; }

    /// <summary>Apps (exe names) where auto-conversion is suppressed — terminals, password managers, RDP.</summary>
    public List<string> DeniedApps { get; set; } = new(DefaultDeniedApps);
    /// <summary>Words never to auto-convert (matched on either side of the pair, case-insensitive).</summary>
    public List<string> NeverConvertWords { get; set; } = new();
    /// <summary>Words to always convert (matched against the target/converted form).</summary>
    public List<string> AlwaysConvertWords { get; set; } = new();

    /// <summary>Password managers — always denied, non-removable in the UI (security).</summary>
    public static readonly string[] ProtectedApps =
    {
        "1password.exe", "bitwarden.exe", "keepass.exe", "keepassxc.exe", "lastpass.exe", "dashlane.exe",
    };

    /// <summary>Editable default denied apps (exe names, lower-case): terminals, RDP.</summary>
    public static readonly string[] DefaultDeniedApps =
    {
        "cmd.exe", "powershell.exe", "pwsh.exe", "windowsterminal.exe", "conhost.exe", "putty.exe", "mstsc.exe",
    };

    public static bool IsProtectedApp(string exe) =>
        ProtectedApps.Any(a => string.Equals(a, exe, StringComparison.OrdinalIgnoreCase));

    public bool IsDeniedApp(string? exe) =>
        exe is not null && (IsProtectedApp(exe) || DeniedApps.Any(a => string.Equals(a, exe, StringComparison.OrdinalIgnoreCase)));

    public bool IsNeverConvert(string typed, string converted)
    {
        if (NeverConvertWords.Count == 0) return false;
        var set = new HashSet<string>(NeverConvertWords.Select(w => w.ToLowerInvariant()));
        return set.Contains(typed.ToLowerInvariant()) || set.Contains(converted.ToLowerInvariant());
    }

    public bool IsAlwaysConvertWord(string converted) =>
        AlwaysConvertWords.Any(w => string.Equals(w, converted, StringComparison.OrdinalIgnoreCase));

    /// <summary>Session-only "pause until restart" (not persisted).</summary>
    [JsonIgnore] public bool PausedUntilRestart { get; set; }

    [JsonIgnore]
    public bool IsPaused => PausedUntilRestart || (PausedUntil is DateTime until && DateTime.Now < until);

    /// <summary>Master toggle AND not paused — the gate both auto and manual conversion check.</summary>
    [JsonIgnore] public bool EffectivelyEnabled => Enabled && !IsPaused;

    // ---- persistence -----------------------------------------------------------------------
    private static string Dir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Switcher3way");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public static SettingsManager Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<SettingsManager>(File.ReadAllText(FilePath)) ?? new SettingsManager();
        }
        catch { /* corrupt/unreadable → defaults */ }
        return new SettingsManager();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, JsonOpts));
        }
        catch { /* best-effort; a failed save must not crash the app */ }
    }

    /// <summary>Pause for a duration, or (null) until restart.</summary>
    public void Pause(TimeSpan? duration)
    {
        if (duration is TimeSpan d) { PausedUntil = DateTime.Now + d; PausedUntilRestart = false; }
        else { PausedUntilRestart = true; PausedUntil = null; }
        Save();
    }

    public void Resume()
    {
        PausedUntil = null;
        PausedUntilRestart = false;
        Save();
    }
}

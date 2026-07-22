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
    public DateTime? PausedUntil { get; set; }

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

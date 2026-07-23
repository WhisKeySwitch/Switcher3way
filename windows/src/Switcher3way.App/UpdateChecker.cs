using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Switcher3way.App;

/// <summary>A discovered Windows release worth offering.</summary>
internal sealed record UpdateInfo(string Version, string Notes, string MsiUrl, string? Sha256);

/// <summary>
/// Checks the fork's own public downloads repo for a newer <b>Windows</b> build and drives the
/// notify → one-click install flow. Mirrors the macOS <c>UpdateChecker</c>, with two differences:
/// Windows releases are <b>pre-releases</b> tagged <c>windows-v*</c> (so <c>/releases/latest</c>
/// can't be used — it lists releases and filters by tag), and integrity is verified by <b>SHA-256</b>
/// from the release notes (the MSI isn't code-signed yet) rather than a signature-equality gate.
/// </summary>
internal sealed class UpdateChecker
{
    private const string ReleasesApi = "https://api.github.com/repos/WhisKeySwitch/switcher3way-releases/releases";
    private const string TagPrefix = "windows-v";
    private static readonly TimeSpan Interval = TimeSpan.FromHours(24);

    private readonly SettingsManager _settings;
    private readonly SynchronizationContext _ui;
    private readonly Action _quit;
    private readonly System.Windows.Forms.Timer _timer;
    private bool _busy;

    /// <summary>Raised (on the UI thread) when the busy state changes, so the menu can relabel.</summary>
    public event Action? StateChanged;
    public bool IsBusy => _busy;

    public UpdateChecker(SettingsManager settings, SynchronizationContext ui, Action quit)
    {
        _settings = settings;
        _ui = ui;
        _quit = quit;
        _timer = new System.Windows.Forms.Timer { Interval = (int)Interval.TotalMilliseconds };
        _timer.Tick += (_, _) => Check(interactive: false);
    }

    /// <summary>First background check ~15 s after launch, then daily — gated on the setting.
    /// The manual menu check keeps working regardless.</summary>
    public void StartSchedule()
    {
        _timer.Stop();
        if (!_settings.CheckForUpdates) return;
        var delay = new System.Windows.Forms.Timer { Interval = 15000 };
        delay.Tick += (_, _) => { delay.Stop(); delay.Dispose(); if (_settings.CheckForUpdates) Check(interactive: false); };
        delay.Start();
        _timer.Start();
    }

    /// <summary>Menu-initiated check: reports every outcome and ignores a skipped version.</summary>
    public void CheckManually() => Check(interactive: true);

    private void Check(bool interactive)
    {
        if (_busy) return;
        if (!interactive && !_settings.CheckForUpdates) return;
        SetBusy(true);
        Task.Run(async () =>
        {
            try
            {
                var info = await FetchLatestAsync();
                _settings.LastUpdateCheck = DateTime.Now; _settings.Save();
                var current = CurrentVersion();
                if (info is null || !IsNewer(info.Version, current))
                {
                    Diagnostics.Log($"update: up to date (current {current}, latest {info?.Version ?? "none"})");
                    if (interactive) Post(() => ShowUpToDate(current));
                }
                else if (!interactive && _settings.SkippedVersion == info.Version)
                {
                    Diagnostics.Log($"update: {info.Version} available but skipped by user");
                }
                else
                {
                    Diagnostics.Log($"update: {info.Version} available (current {current})");
                    Post(() => Offer(info));
                }
            }
            catch (Exception ex)
            {
                Diagnostics.Log($"update: check failed — {ex.Message}");
                if (interactive) Post(() => ShowError(Loc.T("update.checkFailed.title"), ex.Message));
            }
            finally
            {
                Post(() => SetBusy(false));
            }
        });
    }

    // ---- offer & install -------------------------------------------------------------------

    private void Offer(UpdateInfo info)
    {
        var choice = UpdatePromptForm.Ask(info, CurrentVersion());
        switch (choice)
        {
            case UpdatePromptForm.Choice.Install:
                Install(info);
                break;
            case UpdatePromptForm.Choice.Skip:
                _settings.SkippedVersion = info.Version; _settings.Save();
                Diagnostics.Log($"update: user skipped {info.Version}");
                break;
            default:
                break; // Later — offered again next check
        }
    }

    private void Install(UpdateInfo info)
    {
        if (_busy) return;
        SetBusy(true);
        Task.Run(async () =>
        {
            try
            {
                await UpdateInstaller.InstallAsync(info);
                Diagnostics.Log($"update: installing {info.Version}, relaunching");
                Post(_quit); // the relauncher waits for us to exit, runs the MSI, then restarts the app
            }
            catch (Exception ex)
            {
                Diagnostics.Log($"update: install failed — {ex.Message}");
                Post(() => { SetBusy(false); ShowError(Loc.T("update.installFailed.title"), ex.Message); });
            }
        });
    }

    // ---- version helpers -------------------------------------------------------------------

    public static string CurrentVersion()
    {
        var v = typeof(UpdateChecker).Assembly.GetName().Version;
        return v is null ? "0" : $"{v.Major}.{v.Minor}.{v.Build}";
    }

    /// <summary>Numeric segment-wise semver compare ("1.10.0" > "1.9.9"; missing segments are 0).</summary>
    public static bool IsNewer(string candidate, string current)
    {
        static int[] Parts(string s) => s.Trim('v', 'V', ' ').Split('.')
            .Select(p => { var d = new string(p.TakeWhile(char.IsDigit).ToArray()); return int.TryParse(d, out var n) ? n : 0; })
            .ToArray();
        var a = Parts(candidate); var b = Parts(current);
        for (int i = 0; i < Math.Max(a.Length, b.Length); i++)
        {
            int x = i < a.Length ? a[i] : 0, y = i < b.Length ? b[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    // ---- GitHub API ------------------------------------------------------------------------

    private static async Task<UpdateInfo?> FetchLatestAsync()
    {
        using var http = new HttpClient();
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Switcher3way-Updater");
        http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        var json = await http.GetStringAsync(ReleasesApi);

        using var doc = JsonDocument.Parse(json);
        UpdateInfo? best = null;
        foreach (var rel in doc.RootElement.EnumerateArray())
        {
            var tag = rel.GetProperty("tag_name").GetString() ?? "";
            if (!tag.StartsWith(TagPrefix, StringComparison.OrdinalIgnoreCase)) continue;
            if (rel.TryGetProperty("draft", out var d) && d.GetBoolean()) continue;

            string? msiUrl = null;
            if (rel.TryGetProperty("assets", out var assets))
                foreach (var a in assets.EnumerateArray())
                {
                    var name = a.GetProperty("name").GetString() ?? "";
                    if (name.EndsWith(".msi", StringComparison.OrdinalIgnoreCase))
                    {
                        msiUrl = a.GetProperty("browser_download_url").GetString();
                        break;
                    }
                }
            if (msiUrl is null) continue;

            var body = rel.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";
            var version = tag[TagPrefix.Length..];
            var cand = new UpdateInfo(version, body, msiUrl, ParseSha256(body));
            if (best is null || IsNewer(cand.Version, best.Version)) best = cand;
        }
        return best;
    }

    /// <summary>First 64-hex-char run in the release body — the published MSI checksum.</summary>
    public static string? ParseSha256(string body)
    {
        var m = Regex.Match(body, "[0-9a-fA-F]{64}");
        return m.Success ? m.Value.ToLowerInvariant() : null;
    }

    // ---- UI plumbing -----------------------------------------------------------------------

    private void SetBusy(bool value) { _busy = value; StateChanged?.Invoke(); }
    private void Post(Action a) => _ui.Post(_ => a(), null);

    private static void ShowUpToDate(string current) =>
        MessageBox.Show(Loc.Tf("update.upToDate.text", current), Loc.T("update.upToDate.title"),
            MessageBoxButtons.OK, MessageBoxIcon.Information);

    private static void ShowError(string title, string message) =>
        MessageBox.Show(message, title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
}

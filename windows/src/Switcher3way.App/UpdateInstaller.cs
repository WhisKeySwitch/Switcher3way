using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;

namespace Switcher3way.App;

/// <summary>
/// Verified Windows update install: download the MSI → SHA-256 against the published checksum →
/// spawn a detached relauncher that waits for this process to exit, runs the MSI (per-machine
/// upgrade; UAC prompt), then restarts the app. The MSI's MajorUpgrade replaces the old version.
///
/// Note: the MSI is not code-signed yet, so integrity rests on HTTPS + the published SHA-256 —
/// there is no signature-equality gate like the macOS installer has. Add an Authenticode check
/// here once a signing certificate is in place.
/// </summary>
internal static class UpdateInstaller
{
    public static async Task InstallAsync(UpdateInfo info)
    {
        if (string.IsNullOrEmpty(info.Sha256))
            throw new Exception("No published checksum to verify the download against.");

        // 1. Download the MSI (streamed to a temp file).
        var msi = Path.Combine(Path.GetTempPath(), $"Switcher3way-{info.Version}-win-x64.msi");
        using (var http = new HttpClient())
        {
            http.DefaultRequestHeaders.UserAgent.ParseAdd("Switcher3way-Updater");
            using var resp = await http.GetAsync(info.MsiUrl, HttpCompletionOption.ResponseHeadersRead);
            resp.EnsureSuccessStatusCode();
            await using var fs = File.Create(msi);
            await resp.Content.CopyToAsync(fs);
        }

        // 2. Checksum gate.
        var actual = Sha256(msi);
        if (!actual.Equals(info.Sha256, StringComparison.OrdinalIgnoreCase))
        {
            try { File.Delete(msi); } catch { /* best-effort */ }
            Diagnostics.Log($"update: sha256 mismatch — expected {info.Sha256}, got {actual}");
            throw new Exception("The downloaded file failed checksum verification.");
        }

        // 3. Spawn the detached relauncher and return; the caller then quits the app.
        var exe = Environment.ProcessPath ?? throw new Exception("Cannot determine the running executable path.");
        var script = WriteRelauncher();
        Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{script}\" " +
                        $"-ProcId {Environment.ProcessId} -Msi \"{msi}\" -Exe \"{exe}\"",
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        });
    }

    private static string Sha256(string file)
    {
        using var stream = File.OpenRead(file);
        using var sha = SHA256.Create();
        return Convert.ToHexString(sha.ComputeHash(stream)).ToLowerInvariant();
    }

    /// <summary>Write the self-deleting relauncher script to a temp file and return its path.</summary>
    private static string WriteRelauncher()
    {
        var path = Path.Combine(Path.GetTempPath(), "switcher3way-update.ps1");
        // Wait for the app to exit (so the MSI can replace the in-use exe), run the installer with a
        // basic progress UI (UAC will prompt for the per-machine upgrade), relaunch, then clean up.
        const string ps = """
            param([int]$ProcId, [string]$Msi, [string]$Exe)
            try { Wait-Process -Id $ProcId -Timeout 120 -ErrorAction SilentlyContinue } catch {}
            Start-Sleep -Milliseconds 400
            Start-Process msiexec.exe -ArgumentList '/i', ('"' + $Msi + '"'), '/qb', '/norestart' -Wait
            Start-Sleep -Milliseconds 400
            if (Test-Path $Exe) { Start-Process $Exe }
            Remove-Item $Msi -Force -ErrorAction SilentlyContinue
            Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
            """;
        File.WriteAllText(path, ps);
        return path;
    }
}

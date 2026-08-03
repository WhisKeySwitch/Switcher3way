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
///
/// <b>Unpackaged builds only.</b> The csproj swaps this file out for <c>UpdateInstaller.Store.cs</c>
/// when <c>Packaged=true</c>, so a Store build's binary contains no reference to powershell.exe or
/// msiexec — the App Certification Kit reads the binary, and unreachable code still fails its
/// "Blocked executables" test. (A <c>#if</c> can't do the job here: in a skipped region the C# lexer
/// scans every line for directives, and the relauncher script's `#` comments read as malformed ones.)
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
                        $"-ProcId {Environment.ProcessId} -Msi \"{msi}\" -Exe \"{exe}\" -Log \"{Diagnostics.FilePath}\"",
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

    /// <summary>
    /// Write the self-deleting relauncher script and return its path. It waits for the app to exit (so
    /// the MSI can replace the in-use executable), installs, then restarts the app.
    ///
    /// <b>msiexec must be started with -Verb RunAs.</b> Our per-machine MSI cannot install from the
    /// app's unelevated token: msiexec fails with 1925 ("insufficient privileges"), and because the
    /// script then relaunched the *unchanged* app, the updater re-offered the same version on the next
    /// check — an endless update loop. RunAs raises the UAC prompt the upgrade actually needs.
    /// </summary>
    private static string WriteRelauncher()
    {
        var path = Path.Combine(Path.GetTempPath(), "switcher3way-update.ps1");
        const string ps = """
            param([int]$ProcId, [string]$Msi, [string]$Exe, [string]$Log)
            function Note($m) {
              try { Add-Content -Path $Log -Value ("{0}  update: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $m) } catch {}
            }
            try { Wait-Process -Id $ProcId -Timeout 120 -ErrorAction SilentlyContinue } catch {}
            Start-Sleep -Milliseconds 400
            $code = 1603
            try {
              # -Verb RunAs: a per-machine MSI needs elevation, or it fails with 1925 and nothing changes.
              $p = Start-Process msiexec.exe -ArgumentList '/i', ('"' + $Msi + '"'), '/qb', '/norestart' -Verb RunAs -PassThru -Wait
              $code = $p.ExitCode
            } catch {
              Note ("could not start the installer — " + $_.Exception.Message + " (UAC declined?)")
            }
            if ($code -eq 0 -or $code -eq 3010) { Note "installed successfully" }
            else { Note ("installer exited with $code — the previous version is still installed") }
            Start-Sleep -Milliseconds 400
            if (Test-Path $Exe) { Start-Process $Exe }
            Remove-Item $Msi -Force -ErrorAction SilentlyContinue
            Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
            """;
        File.WriteAllText(path, ps);
        return path;
    }
}

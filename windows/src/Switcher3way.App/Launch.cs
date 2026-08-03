namespace Switcher3way.App;

/// <summary>
/// Opens a URL or folder in the user's default handler.
///
/// Packaged (Store) builds go through <c>Windows.System.Launcher</c> — the sanctioned API for a
/// packaged app. Unpackaged builds use ShellExecute, which is all that's available to them.
///
/// The ShellExecute paths are compiled out of packaged builds (<c>PACKAGED</c>), not just skipped at
/// runtime: the App Certification Kit's "Blocked executables" test reads the binary, so a
/// <c>Process.Start</c> that a Store build can never reach still fails the test and invites a
/// question in review.
/// </summary>
internal static class Launch
{
    public static void Open(string target)
    {
        try
        {
#if PACKAGED
            if (Uri.TryCreate(target, UriKind.Absolute, out var uri)) _ = Windows.System.Launcher.LaunchUriAsync(uri);
            else Diagnostics.Log($"launch skipped, not an absolute URI: {target}");
#else
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target) { UseShellExecute = true });
#endif
        }
        catch (Exception ex)
        {
            Diagnostics.Log($"launch failed ({target}): {ex.Message}");
        }
    }

    /// <summary>Open a folder in File Explorer.</summary>
    public static void OpenFolder(string path)
    {
        try
        {
            System.IO.Directory.CreateDirectory(path);
#if PACKAGED
            var folder = Windows.Storage.StorageFolder.GetFolderFromPathAsync(path).GetAwaiter().GetResult();
            _ = Windows.System.Launcher.LaunchFolderAsync(folder);
#else
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
#endif
        }
        catch (Exception ex)
        {
            Diagnostics.Log($"open folder failed ({path}): {ex.Message}");
        }
    }
}

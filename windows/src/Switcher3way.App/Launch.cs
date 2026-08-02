namespace Switcher3way.App;

/// <summary>
/// Opens a URL or folder in the user's default handler.
///
/// Packaged (Store) builds go through <c>Windows.System.Launcher</c> — the sanctioned API for a
/// packaged app, and it avoids the process-launch references the Windows App Certification Kit
/// flags. Unpackaged builds use ShellExecute, which is all that's available to them.
/// </summary>
internal static class Launch
{
    public static void Open(string target)
    {
        try
        {
            if (PackageInfo.IsPackaged && Uri.TryCreate(target, UriKind.Absolute, out var uri))
            {
                _ = Windows.System.Launcher.LaunchUriAsync(uri);
                return;
            }
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target) { UseShellExecute = true });
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
            if (PackageInfo.IsPackaged)
            {
                var folder = Windows.Storage.StorageFolder.GetFolderFromPathAsync(path).GetAwaiter().GetResult();
                _ = Windows.System.Launcher.LaunchFolderAsync(folder);
                return;
            }
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Diagnostics.Log($"open folder failed ({path}): {ex.Message}");
        }
    }
}

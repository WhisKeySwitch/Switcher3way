using System.IO;

namespace Switcher3way.App;

/// <summary>
/// "Start with Windows". Unpackaged (MSI) builds use a shortcut in the user's Startup folder;
/// packaged (Store) builds use the package's declared StartupTask, which is the only mechanism
/// that works inside MSIX — a Startup-folder shortcut to a packaged app is not reliable, and the
/// user can also disable the task from Windows' Startup apps settings.
/// </summary>
internal static class StartupShortcut
{
    /// <summary>Must match the TaskId in Package.appxmanifest.</summary>
    private const string TaskId = "Switcher3wayStartup";

    private static string LinkPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Switcher3way.lnk");

    public static bool IsEnabled => PackageInfo.IsPackaged ? TaskEnabled() : File.Exists(LinkPath);

    public static void Set(bool on)
    {
        if (PackageInfo.IsPackaged) { SetTask(on); return; }
        try
        {
            if (on)
            {
                var exe = Environment.ProcessPath;
                if (exe is null) return;
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")!)!;
                dynamic sc = shell.CreateShortcut(LinkPath);
                sc.TargetPath = exe;
                sc.WorkingDirectory = Path.GetDirectoryName(exe);
                sc.Description = "Switcher3way";
                sc.Save();
            }
            else if (File.Exists(LinkPath))
            {
                File.Delete(LinkPath);
            }
        }
        catch { /* best-effort */ }
    }

    // ---- packaged (MSIX) StartupTask ---------------------------------------------------------
    private static bool TaskEnabled()
    {
        try
        {
            var task = Windows.ApplicationModel.StartupTask.GetAsync(TaskId).GetAwaiter().GetResult();
            return task.State is Windows.ApplicationModel.StartupTaskState.Enabled
                              or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
        }
        catch (Exception ex)
        {
            Diagnostics.Log("startup task query failed: " + ex.Message);
            return false;
        }
    }

    private static void SetTask(bool on)
    {
        try
        {
            var task = Windows.ApplicationModel.StartupTask.GetAsync(TaskId).GetAwaiter().GetResult();
            if (on)
            {
                var state = task.RequestEnableAsync().GetAwaiter().GetResult();
                // DisabledByUser can only be undone in Windows' Startup apps settings.
                if (state is Windows.ApplicationModel.StartupTaskState.DisabledByUser)
                    Diagnostics.Log("startup task: disabled by the user in Windows settings");
            }
            else task.Disable();
        }
        catch (Exception ex)
        {
            Diagnostics.Log("startup task change failed: " + ex.Message);
        }
    }
}

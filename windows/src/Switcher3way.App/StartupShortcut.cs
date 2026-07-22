using System.IO;

namespace Switcher3way.App;

/// <summary>Manages the "start at login" shortcut in the user's Startup folder.</summary>
internal static class StartupShortcut
{
    private static string LinkPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Switcher3way.lnk");

    public static bool IsEnabled => File.Exists(LinkPath);

    public static void Set(bool on)
    {
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
}

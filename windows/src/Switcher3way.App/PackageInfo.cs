using System.Runtime.InteropServices;
using System.Text;

namespace Switcher3way.App;

/// <summary>
/// Whether this process is running from an MSIX package (the Store build) or unpackaged (the MSI
/// build). The two differ in ways the app must respect:
///   • packaged apps must not update themselves — the Store does that, and self-updating breaks policy;
///   • "start with Windows" uses the package's StartupTask instead of a Startup-folder shortcut;
///   • settings live in the package's redirected app data.
/// </summary>
internal static class PackageInfo
{
    private static bool? _packaged;

    /// <summary>True when running from an MSIX package.</summary>
    public static bool IsPackaged
    {
        get
        {
            if (_packaged is bool known) return known;
            bool result;
            try
            {
                int length = 0;
                // APPMODEL_ERROR_NO_PACKAGE (15700) → unpackaged. Anything else means we have identity.
                result = GetCurrentPackageFullName(ref length, null) != 15700;
            }
            catch
            {
                result = false; // pre-Win8 API missing — treat as unpackaged
            }
            _packaged = result;
            return result;
        }
    }

    /// <summary>Where updates come from, for logs and the About tab.</summary>
    public static string DistributionChannel => IsPackaged ? "Microsoft Store" : "direct download";

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(ref int packageFullNameLength, StringBuilder? packageFullName);
}

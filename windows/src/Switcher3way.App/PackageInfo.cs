using System.Runtime.InteropServices;
using System.Text;

namespace Switcher3way.App;

/// <summary>
/// Whether this process is running from an MSIX package (the Store build) or unpackaged (the MSI
/// build). The two differ in ways the app must respect:
///   • packaged apps must not update themselves — the Store does that, and self-updating breaks policy;
///   • "start with Windows" uses the package's StartupTask instead of a Startup-folder shortcut;
///   • the bootstrapper API must not be called — the runtime comes from the framework dependency.
///
/// Settings are NOT redirected: a full-trust packaged build reads and writes the same
/// <c>%APPDATA%\Switcher3way</c> as the MSI build (verified on Windows 11 26200), so switching between
/// the two channels keeps the user's settings. Don't rely on per-package isolation here.
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

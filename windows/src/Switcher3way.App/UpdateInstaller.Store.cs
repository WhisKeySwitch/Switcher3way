namespace Switcher3way.App;

/// <summary>
/// The packaged (Microsoft Store) stand-in for <c>UpdateInstaller</c>: the Store services updates for
/// packaged builds, and self-updating one is against policy. <see cref="UpdateChecker"/> returns early
/// on <c>PackageInfo.IsPackaged</c>, so this is never called.
///
/// It exists as a separate file rather than a runtime branch so that a Store build's binary carries no
/// reference to powershell.exe, msiexec or <c>Process.Start</c> — the App Certification Kit inspects
/// the binary, and code a Store build can never reach still fails its "Blocked executables" test and
/// would need explaining in review. The csproj includes exactly one of the two files.
/// </summary>
internal static class UpdateInstaller
{
    public static Task InstallAsync(UpdateInfo info) =>
        throw new NotSupportedException("packaged builds are updated by the Microsoft Store");
}

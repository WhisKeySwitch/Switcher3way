using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.ApplicationModel.DynamicDependency;
using Switcher3way.App;
using Switcher3way.Core;
using Switcher3way.Dictionaries;

internal static class Program
{
    // Switcher3way (Windows), WinUI 3.
    //   (no args)  Tray app (WinUI). Auto-fixes finished words; manual trigger; settings.
    //   selftest   Non-interactive: real layout enumeration + Win32 render + Hunspell + resolver.
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length > 0 && args[0].Equals("selftest", StringComparison.OrdinalIgnoreCase))
        {
            Native.AttachConsole(Native.ATTACH_PARENT_PROCESS); // WinExe has no console; reuse the launching terminal
            SelfTest.Run();
            return;
        }

        // Locate the (framework-dependent) Windows App SDK runtime before any WinUI type loads.
        // Unpackaged builds depend on it being installed; without this check the process would just
        // vanish, which is what happened before the runtime was present on this machine.
        //
        // A PACKAGED build must not do this. The bootstrapper exists to find a runtime for apps with no
        // package identity; inside MSIX the runtime arrives through the manifest's framework dependency
        // and the API fails — which made the Store build show "Windows App Runtime 1.6 isn't installed"
        // and quit, on a machine where it plainly was installed.
        bool packaged = PackageInfo.IsPackaged;
        if (!packaged && !Bootstrap.TryInitialize(0x00010006, out _)) // 1.6.x
        {
            MessageBoxW(IntPtr.Zero,
                "Switcher3way needs the Windows App Runtime 1.6, which isn't installed.\n\n" +
                "Install \"Windows App Runtime 1.6\" from Microsoft (or get Switcher3way from the " +
                "Microsoft Store, which installs it for you), then start Switcher3way again.",
                "Switcher3way", MB_ICONERROR);
            return;
        }

        // Single instance — two copies would install two hooks and double-convert.
        //
        // This has to be AppInstance rather than a named mutex, because clicking a button on one of our
        // notifications makes Windows *launch the exe again* to deliver the activation. A mutex made that
        // second process exit before handing anything over, so the button silently did nothing. Redirecting
        // the activation to the running instance is what makes it arrive at NotificationInvoked.
        // AppInstance is a Windows App SDK API, so it must come after the bootstrapper above.
        var primary = Microsoft.Windows.AppLifecycle.AppInstance.FindOrRegisterForKey("Switcher3way.Main");
        if (!primary.IsCurrent)
        {
            var activation = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
            primary.RedirectActivationToAsync(activation).AsTask().GetAwaiter().GetResult();
            if (!packaged) Bootstrap.Shutdown();
            return;
        }

        try
        {
            Application.Start(p =>
            {
                var ctx = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                System.Threading.SynchronizationContext.SetSynchronizationContext(ctx);
                _ = new App();
            });
            Diagnostics.Log("main: Application.Start returned — the message loop ended");
        }
        finally
        {
            if (!packaged) Bootstrap.Shutdown();
        }
    }

    private const uint MB_ICONERROR = 0x00000010;
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
}

internal static class SelfTest
{
    public static void Run()
    {
        Console.WriteLine("=== Switcher3way (Windows) — SELF TEST (no hook) ===\n");

        var catalog = new Win32LayoutCatalog();
        var dict = new HunspellDictionaryValidator();
        var resolver = new NWayResolver(catalog, dict, new EmptyAlwaysConvert());

        var layouts = catalog.InstalledLayouts();
        Console.WriteLine($"Installed layouts ({layouts.Count}):");
        foreach (var l in layouts)
            Console.WriteLine($"  id={l.Id,-16} lang={l.Lang ?? "?",-4} dict={(l.Lang is not null && dict.IsAvailable(l.Lang) ? "yes" : "no")}");

        var keys = new[] { 'G', 'H', 'B', 'D', 'T', 'N' }
            .Select(c => new TypedKey((int)c, Shift: false, Caps: false)).ToList();
        Console.WriteLine("\nWin32 render of G,H,B,D,T,N through each layout:");
        foreach (var l in layouts)
            Console.WriteLine($"  {l.Lang ?? "?",-4} => \"{catalog.Render(keys, l)}\"");

        // Probe: the 's' key is where ru ('ы') and uk ('і') usually differ.
        var keys2 = new[] { 'G', 'H', 'B', 'D', 'S', 'N' }
            .Select(c => new TypedKey((int)c, Shift: false, Caps: false)).ToList();
        Console.WriteLine("\nWin32 render of G,H,B,D,S,N (ghbdsn) through each layout:");
        foreach (var l in layouts)
            Console.WriteLine($"  {l.Lang ?? "?",-4} => \"{catalog.Render(keys2, l)}\"");

        Console.WriteLine($"\nCurrent layout id: {catalog.CurrentLayoutId()}");
        var d = resolver.Resolve(keys, capsLock: false);
        Console.WriteLine(d is null
            ? "resolve: (no conversion for the current layout)"
            : $"resolve: -> [{d.TargetLayoutId}] \"{d.Original}\" => \"{d.Converted}\"");

        Console.WriteLine("\nSelf test complete. Run without args for the tray app.");
    }
}

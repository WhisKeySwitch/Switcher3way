using System.Windows.Forms;
using Switcher3way.App;
using Switcher3way.Core;
using Switcher3way.Dictionaries;

internal static class Program
{
    // Switcher3way (Windows).
    //   (no args)  Tray app: auto-fixes finished words; F9 = manual convert/cycle; menu = enable /
    //              auto-fix / pause / quit.
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

        // Single instance — two copies would install two hooks and double-convert.
        using var mutex = new System.Threading.Mutex(initiallyOwned: true, "Switcher3way.SingleInstance", out bool createdNew);
        if (!createdNew) return;

        ApplicationConfiguration.Initialize();
        using var tray = new TrayApp();
        Application.Run();
    }
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

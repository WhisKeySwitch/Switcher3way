using Switcher3way.App;
using Switcher3way.Core;
using Switcher3way.Dictionaries;

// dotnet run -- selftest   Non-interactive: real layout enumeration + Win32 render + real Hunspell
//                          + NWayResolver. Safe to run headless (no hook, no input synthesis).
// dotnet run               Interactive live loop: global hook auto-fixes finished words; F9 = manual
//                          convert/cycle; End = quit. Needs a real desktop.

if (args.Length > 0 && args[0].Equals("selftest", StringComparison.OrdinalIgnoreCase))
{
    SelfTest.Run();
    return;
}

new Engine().RunInteractive();

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

        // Physical keys G,H,B,D,T,N — "ghbdtn" (en) / "привет" (ru/uk-as-rendered).
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

        Console.WriteLine("\nSelf test complete. Interactive auto/manual require `dotnet run` at a real keyboard.");
    }
}

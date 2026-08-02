using System.Globalization;
using System.Text;
using Switcher3way.Core;

namespace Switcher3way.App;

/// <summary>
/// <see cref="ILayoutCatalog"/> over Win32: enumerates installed layouts (<c>GetKeyboardLayoutList</c>),
/// resolves each layout's language from its <c>HKL</c> LANGID, and renders keystrokes through a
/// layout with a dead-key-safe <c>ToUnicodeEx</c> sequence (graduated from the spike). A layout's
/// <c>Id</c> is the hex of its <c>HKL</c>, so it round-trips back to the handle for rendering/switching.
/// </summary>
public sealed class Win32LayoutCatalog : ILayoutCatalog
{
    public IReadOnlyList<Layout> InstalledLayouts()
    {
        int n = Native.GetKeyboardLayoutList(0, null);
        var buf = new IntPtr[Math.Max(n, 1)];
        n = Native.GetKeyboardLayoutList(buf.Length, buf);
        var result = new List<Layout>(n);
        for (int i = 0; i < n; i++)
            result.Add(new Layout(HklToId(buf[i]), LangOf(buf[i])));
        return result;
    }

    public string CurrentLayoutId()
    {
        var hwnd = Native.GetForegroundWindow();
        uint tid = Native.GetWindowThreadProcessId(hwnd, out _);
        return HklToId(Native.GetKeyboardLayout(tid));
    }

    public string? Render(IReadOnlyList<TypedKey> keys, Layout layout)
    {
        if (!TryParseId(layout.Id, out var hkl)) return null;
        var keyState = new byte[256];
        var sb = new StringBuilder(keys.Count + 4);
        foreach (var k in keys)
        {
            if (k.Char is char forwarded) { sb.Append(forwarded); continue; }
            keyState[Native.VK_SHIFT] = (byte)(k.Shift ? 0x80 : 0x00);
            keyState[Native.VK_CAPITAL] = (byte)(k.Caps ? 0x01 : 0x00);
            uint scan = Native.MapVirtualKeyEx((uint)k.KeyCode, Native.MAPVK_VK_TO_VSC, hkl);
            sb.Append(RenderKey((uint)k.KeyCode, scan, hkl, keyState));
        }
        FlushDeadKey(hkl, keyState);          // leave the layout's dead-key buffer clean
        return sb.ToString();
    }

    // ---- Reverse mapping (character → keystroke) --------------------------------------------
    private static readonly Dictionary<string, Dictionary<char, TypedKey>> _reverse = new();

    /// <summary>
    /// Character → the keystroke that produces it in this layout: the inverse of
    /// <see cref="Render"/>. Needed for the manual trigger's selection path, where we start from
    /// text on screen rather than from recorded keystrokes. Cached per layout.
    /// </summary>
    public IReadOnlyDictionary<char, TypedKey> ReverseMap(Layout layout)
    {
        if (_reverse.TryGetValue(layout.Id, out var cached)) return cached;
        var map = new Dictionary<char, TypedKey>();
        if (TryParseId(layout.Id, out var hkl))
        {
            // Unshifted first so the simplest keystroke wins for characters reachable both ways.
            foreach (bool shift in new[] { false, true })
                foreach (uint vk in CandidateVks())
                {
                    var keyState = new byte[256];
                    keyState[Native.VK_SHIFT] = (byte)(shift ? 0x80 : 0x00);
                    uint scan = Native.MapVirtualKeyEx(vk, Native.MAPVK_VK_TO_VSC, hkl);
                    var s = RenderKey(vk, scan, hkl, keyState);
                    FlushDeadKey(hkl, keyState);
                    if (s.Length == 1 && !map.ContainsKey(s[0]))
                        map[s[0]] = new TypedKey((int)vk, shift, Caps: false);
                }
        }
        _reverse[layout.Id] = map;
        return map;
    }

    /// <summary>The printable keys a word can be typed with: digits, letters, OEM punctuation, space.</summary>
    private static IEnumerable<uint> CandidateVks()
    {
        yield return 0x20;                                   // space
        for (uint vk = 0x30; vk <= 0x39; vk++) yield return vk;  // 0-9
        for (uint vk = 0x41; vk <= 0x5A; vk++) yield return vk;  // A-Z
        foreach (uint vk in new uint[] { 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0,
                                         0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE2 })
            yield return vk;                                 // ;=,-./` [\]' and friends
    }

    // ---- HKL <-> id ------------------------------------------------------------------------
    internal static string HklToId(IntPtr hkl) => ((ulong)(long)hkl).ToString("X");
    internal static bool TryParseId(string id, out IntPtr hkl)
    {
        hkl = IntPtr.Zero;
        if (!ulong.TryParse(id, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var v)) return false;
        hkl = (IntPtr)(long)v;
        return true;
    }

    private static string? LangOf(IntPtr hkl)
    {
        int langId = (int)((long)hkl & 0xFFFF);
        try { return CultureInfo.GetCultureInfo(langId).TwoLetterISOLanguageName; }
        catch (CultureNotFoundException) { return null; }
    }

    // ---- Dead-key-safe rendering (from the spike) ------------------------------------------
    private static string RenderKey(uint vk, uint scan, IntPtr hkl, byte[] keyState)
    {
        FlushDeadKey(hkl, keyState);                       // drain any pending dead key first
        var sb = new StringBuilder(8);
        int rc = Native.ToUnicodeEx(vk, scan, keyState, sb, sb.Capacity, 0, hkl);
        string produced = rc > 0 ? sb.ToString(0, rc) : "";
        if (rc == -1) FlushDeadKey(hkl, keyState);         // this key was itself a dead key → flush it
        return produced;
    }

    private static void FlushDeadKey(IntPtr hkl, byte[] keyState)
    {
        const uint VK_SPACE = 0x20;
        uint spaceScan = Native.MapVirtualKeyEx(VK_SPACE, Native.MAPVK_VK_TO_VSC, hkl);
        var junk = new StringBuilder(8);
        Native.ToUnicodeEx(VK_SPACE, spaceScan, keyState, junk, junk.Capacity, 0, hkl);
        Native.ToUnicodeEx(VK_SPACE, spaceScan, keyState, junk, junk.Capacity, 0, hkl);
    }
}

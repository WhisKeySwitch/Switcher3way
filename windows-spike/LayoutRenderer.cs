using System.Globalization;
using System.Text;

namespace Switcher3wSpike;

/// <summary>
/// D4/R3: enumerate installed layouts and render buffered keystrokes through each, without
/// corrupting the kernel dead-key buffer. This is the riskiest thing the spike must prove.
/// </summary>
internal static class LayoutRenderer
{
    public readonly record struct Layout(IntPtr Hkl, int LangId, string LangTag);

    /// <summary>One buffered keystroke: virtual key, the real hardware scancode from the hook
    /// (0 = derive via MapVirtualKeyEx), and whether Shift was physically down at capture time.</summary>
    public readonly record struct BufferedKey(uint Vk, uint Scan, bool Shift);

    /// <summary>Enumerate installed keyboard layouts (task 3.1).</summary>
    public static List<Layout> InstalledLayouts()
    {
        int count = Native.GetKeyboardLayoutList(0, null);
        var buf = new IntPtr[Math.Max(count, 1)];
        count = Native.GetKeyboardLayoutList(buf.Length, buf);

        var result = new List<Layout>();
        for (int i = 0; i < count; i++)
        {
            IntPtr hkl = buf[i];
            // The low word of the HKL is the language identifier (LANGID).
            int langId = (int)((long)hkl & 0xFFFF);
            string tag;
            try
            {
                tag = CultureInfo.GetCultureInfo(langId).Name; // e.g. "en-US", "uk-UA", "ru-RU"
            }
            catch (CultureNotFoundException)
            {
                tag = $"0x{langId:X4}";
            }
            result.Add(new Layout(hkl, langId, tag));
        }
        return result;
    }

    /// <summary>Ignore layouts that don't map to a usable language (spec: exclude unusable).</summary>
    public static bool HasUsableLanguage(Layout l) => !l.LangTag.StartsWith("0x", StringComparison.Ordinal);

    /// <summary>
    /// Render one virtual key through a specific layout, using the clear-then-translate-then-flush
    /// dead-key pattern (S3). We translate a benign key (VK_SPACE) twice around the real
    /// translation to drain any pending dead-key state so live typing is not corrupted (R3).
    /// </summary>
    private static string RenderKey(uint vk, uint scan, IntPtr hkl, byte[] keyState)
    {
        const uint VK_SPACE = 0x20;
        var sb = new StringBuilder(8);

        // Drain any dead key currently pending in this layout's kernel buffer.
        FlushDeadKey(hkl, keyState);

        int rc = Native.ToUnicodeEx(vk, scan, keyState, sb, sb.Capacity, 0, hkl);
        string produced = rc switch
        {
            > 0 => sb.ToString(0, rc),
            -1 => "",          // dead key: consumed, will combine with next; treat as pending
            _ => "",           // 0: no translation for this key in this layout
        };

        // If the key we just translated was itself a dead key (rc == -1), flush it so it does not
        // leak into the next real keystroke the user types.
        if (rc == -1) FlushDeadKey(hkl, keyState);
        _ = VK_SPACE;
        return produced;
    }

    /// <summary>Translate a spare key to consume/clear any pending dead-key state, discarding output.</summary>
    private static void FlushDeadKey(IntPtr hkl, byte[] keyState)
    {
        const uint VK_SPACE = 0x20;
        uint spaceScan = Native.MapVirtualKeyEx(VK_SPACE, Native.MAPVK_VK_TO_VSC, hkl);
        var junk = new StringBuilder(8);
        // Call twice: a pending dead key + space yields the combined char (drains state); a second
        // call then returns cleanly.
        Native.ToUnicodeEx(VK_SPACE, spaceScan, keyState, junk, junk.Capacity, 0, hkl);
        Native.ToUnicodeEx(VK_SPACE, spaceScan, keyState, junk, junk.Capacity, 0, hkl);
    }

    /// <summary>
    /// Render a whole buffered word through a layout, honoring per-key shift state and the real
    /// hardware scancode (task 3.2).
    /// </summary>
    public static string RenderWord(IReadOnlyList<BufferedKey> keys, IntPtr hkl)
    {
        var keyState = new byte[256];
        var sb = new StringBuilder(keys.Count + 4);
        foreach (var k in keys)
        {
            keyState[Native.VK_SHIFT] = (byte)(k.Shift ? 0x80 : 0x00);
            uint scan = k.Scan != 0 ? k.Scan : Native.MapVirtualKeyEx(k.Vk, Native.MAPVK_VK_TO_VSC, hkl);
            sb.Append(RenderKey(k.Vk, scan, hkl, keyState));
        }
        // Leave the layout's dead-key buffer clean for the user's live typing.
        FlushDeadKey(hkl, keyState);
        return sb.ToString();
    }

    /// <summary>Convenience overload for synthetic input: unshifted, scancode derived per layout.</summary>
    public static string RenderWord(IReadOnlyList<uint> vks, IntPtr hkl)
        => RenderWord(vks.Select(v => new BufferedKey(v, 0, false)).ToList(), hkl);

    /// <summary>Render a buffered word through every usable installed layout.</summary>
    public static IEnumerable<(Layout layout, string text)> RenderAll(IReadOnlyList<BufferedKey> keys)
    {
        foreach (var l in InstalledLayouts())
        {
            if (!HasUsableLanguage(l)) continue;
            yield return (l, RenderWord(keys, l.Hkl));
        }
    }

    /// <summary>Convenience overload for synthetic (unshifted) virtual-key input.</summary>
    public static IEnumerable<(Layout layout, string text)> RenderAll(IReadOnlyList<uint> vks)
        => RenderAll(vks.Select(v => new BufferedKey(v, 0, false)).ToList());
}

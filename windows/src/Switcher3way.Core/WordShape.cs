namespace Switcher3way.Core;

/// <summary>
/// Judges whether a string is shaped like a word of a language — not whether it IS one.
///
/// The dictionaries answer "is this a word"; nothing answers "could this be one". Jargon,
/// loanwords and names live exactly in that gap (<c>апка</c>, <c>айді</c>, <c>Kyiv</c>), and the
/// rescue path in <see cref="NWayResolver"/> needs both sides of it: the typed rendering must be
/// <em>gibberish</em> in the typed language while a candidate rendering is <em>plausible</em> in
/// its own, or no rescue happens.
///
/// The signals are structural and cheap:
/// vowels (a word of these languages carries at least one, and never runs more than a few
/// consonants together — <c>fgrf</c>, <c>ljpdjktyt</c> and <c>Лншм</c> all fail here); English
/// onsets (some letter pairs begin no English word — <c>nt</c>, <c>rf</c>, <c>fq</c>, <c>xt</c> —
/// and a Cyrillic word read through the Latin layout starts with one strikingly often, which is
/// how <c>ntyfyne</c>/тенанту and <c>rfibh</c>/Кашир fail despite carrying vowels); and known
/// tokens (vowel-less tech vocabulary typed daily that means itself — <c>ctrl</c>, <c>http</c> —
/// which structure alone cannot tell from wrong-layout gibberish, so it is named, not inferred).
///
/// Vowel sets arrive by injection (<see cref="IDictionaryValidator.Vowels"/>) like the near-miss
/// alphabet does, and an empty set switches the check — and with it the rescue — off, the same
/// fail-open convention as <see cref="IDictionaryValidator.Alphabet"/>.
///
/// A port of the macOS <c>WordShape</c>, deliberately line-for-line comparable with it. Measured,
/// not asserted: <c>RescueQualityTests</c> scores this file against a fixture of must-keep and
/// must-rescue tokens; the constants below are what that measurement settled on.
/// </summary>
public static class WordShape
{
    /// <summary>
    /// The longest run of consonants a plausible word may carry. Ukrainian and Russian tolerate
    /// longer clusters than English (<c>взгляд</c>, <c>здійсн-</c>), and 4 clears both while
    /// <c>ljpdjktyt</c> (дозволене, no vowel in nine letters) fails by a mile.
    /// </summary>
    public const int MaxConsonantRun = 4;

    /// <summary>
    /// Letter pairs that begin no English word. Consulted only for English — the language this
    /// list was measured against; other languages judge by vowels alone. Deliberately
    /// conservative: pairs that begin real words or likely names stay out (<c>kn</c>, <c>gn</c>,
    /// <c>ps</c>, <c>pt</c>, <c>sq</c>, <c>wr</c>, <c>mn</c> — mnemonic, <c>ky</c> — Kyiv/Kyle,
    /// <c>sr</c> — Sri).
    /// </summary>
    private static readonly HashSet<string> ImpossibleEnglishOnsets = new()
    {
        "bb", "bc", "bd", "bf", "bg", "bj", "bk", "bm", "bn", "bp", "bq", "bs", "bt", "bv", "bw", "bz",
        "cb", "cd", "cf", "cg", "cj", "ck", "cm", "cn", "cp", "cq", "cs", "ct", "cv", "cw", "cx",
        "db", "dc", "dd", "df", "dg", "dh", "dk", "dl", "dm", "dn", "dp", "dq", "dt", "dv",
        "fb", "fc", "fd", "ff", "fg", "fh", "fk", "fm", "fn", "fp", "fq", "fs", "ft", "fv", "fw", "fz",
        "gb", "gc", "gd", "gf", "gg", "gj", "gk", "gm", "gp", "gq", "gs", "gt", "gv", "gz",
        "hb", "hc", "hd", "hf", "hg", "hh", "hj", "hk", "hl", "hm", "hn", "hp", "hq", "hr", "hs", "ht", "hv", "hw", "hz",
        "jb", "jc", "jd", "jf", "jg", "jh", "jj", "jk", "jl", "jm", "jn", "jp", "jq", "jr", "js", "jt", "jv", "jw", "jz",
        "kb", "kc", "kd", "kf", "kg", "kj", "kk", "km", "kp", "kq", "kt", "kz",
        "lb", "lc", "ld", "lf", "lg", "lh", "lj", "lk", "lm", "ln", "lp", "lr", "ls", "lt", "lv", "lw",
        "mb", "mc", "md", "mf", "mg", "mh", "mj", "mk", "ml", "mp", "mr", "ms", "mt", "mv", "mw",
        "nb", "nf", "ng", "nk", "nl", "nm", "np", "nr", "ns", "nt", "nv", "nw", "nz",
        "pb", "pc", "pd", "pg", "pj", "pk", "pm", "pp", "pq", "pv", "pw", "pz",
        "qb", "qc", "qd", "qf", "qg", "qh", "qj", "qk", "ql", "qm", "qn", "qp", "qq", "qr", "qs", "qt", "qv", "qw", "qx", "qy", "qz",
        "rb", "rc", "rd", "rf", "rg", "rj", "rk", "rl", "rm", "rn", "rp", "rr", "rs", "rt", "rv", "rw",
        "sb", "sd", "sg", "sj", "ss", "sv", "sz",
        "tb", "tc", "td", "tf", "tg", "tj", "tk", "tl", "tm", "tn", "tp", "tq", "tv",
        "vb", "vc", "vd", "vf", "vg", "vh", "vj", "vk", "vl", "vm", "vn", "vp", "vq", "vr", "vs", "vt", "vv", "vw", "vz",
        "wb", "wc", "wd", "wf", "wg", "wj", "wk", "wl", "wm", "wn", "wp", "wq", "ws", "wt", "wv", "ww", "wz",
        "xb", "xc", "xd", "xf", "xg", "xh", "xj", "xk", "xl", "xm", "xn", "xp", "xq", "xr", "xs", "xt", "xv", "xw", "xz",
        "zb", "zc", "zd", "zf", "zg", "zj", "zk", "zl", "zm", "zn", "zp", "zq", "zr", "zs", "zt", "zv", "zw",
    };

    /// <summary>
    /// Vowel-less English tech vocabulary long enough to reach the rescue floor. These are typed
    /// as themselves every day; treating them as gibberish would convert them into Cyrillic noise
    /// (<c>ctrl</c> renders as <c>секд</c>). A structural test cannot know this — a list can.
    /// </summary>
    private static readonly HashSet<string> KnownEnglishTokens = new()
    {
        "ctrl", "http", "https", "html", "xhtml", "xml", "smtp", "sftp", "ftps",
        "grpc", "nginx", "systemd", "npm", "pnpm", "wysiwyg",
    };

    /// <summary>
    /// Is <paramref name="word"/> (lower-cased letter core) shaped like a word of the language
    /// whose vowels these are? An empty vowel set means the language's shape is unknown — the
    /// answer is then false ("cannot vouch for it"), and callers must treat that as "do not act",
    /// never as gibberish.
    /// </summary>
    public static bool IsPlausible(string word, string vowels, string lang)
    {
        if (vowels.Length == 0) return false;
        if (lang == "en" && KnownEnglishTokens.Contains(word)) return true;

        var vowelSet = new HashSet<char>(vowels.ToLowerInvariant());
        var sawVowel = false;
        var run = 0;
        foreach (var ch in word)
        {
            if (!char.IsLetter(ch)) continue;
            if (vowelSet.Contains(ch)) { sawVowel = true; run = 0; }
            else if (++run > MaxConsonantRun) return false;
        }
        if (!sawVowel) return false;

        if (lang == "en" && word.Length >= 2 && ImpossibleEnglishOnsets.Contains(word[..2]))
            return false;
        return true;
    }
}

import Foundation

/// Judges whether a string is shaped like a word of a language — not whether it IS one.
///
/// The dictionaries answer "is this a word"; nothing answers "could this be one". Jargon,
/// loanwords and names live exactly in that gap (`апка`, `айді`, `Kyiv`), and the rescue path in
/// `NWayResolver` needs both sides of it: the typed rendering must be *gibberish* in the typed
/// language while a candidate rendering is *plausible* in its own, or no rescue happens.
///
/// The signals are structural and cheap:
/// - vowels: a word of these languages carries at least one, and never runs more than a few
///   consonants together. `fgrf`, `ljpdjktyt` and `Лншм` all fail here.
/// - onsets (English side): some letter pairs begin no English word (`nt`, `rf`, `fq`, `xt` …),
///   and a Cyrillic word read through the Latin layout starts with one strikingly often — the two
///   alphabets' key positions don't line up with English phonotactics. `ntyfyne` (тенанту) and
///   `rfibh` (Кашир) fail here despite carrying vowels.
/// - known tokens (English side): vowel-less tech vocabulary that is typed daily and means itself
///   (`ctrl`, `http`, `html`). Structure alone cannot tell these from wrong-layout gibberish —
///   their Cyrillic renderings can look plausible — so they are named, not inferred.
///
/// The vowel sets arrive by injection (`DictionaryValidating.vowels(_:)`) like the near-miss
/// alphabet does, and an empty set switches the check — and with it the rescue — off, the same
/// fail-open convention as `alphabet(_:)`.
///
/// Measured, not asserted: `RescueQualityTests` scores this file against a fixture of must-keep
/// and must-rescue tokens; the constants below are what that measurement settled on.
public enum WordShape {

    /// The longest run of consonants a plausible word may carry. Ukrainian and Russian tolerate
    /// longer clusters than English (`взгляд`, `здійсн-`), and 4 clears both while `ljpdjktyt`
    /// (дозволене, no vowel in nine letters) fails by a mile.
    public static let maxConsonantRun = 4

    /// The longest run a word may END on — stricter than the interior cap, because word-final
    /// clusters are where the languages differ from keyboard noise: `взгляд` needs its 4-run at the
    /// START, but essentially nothing in en/uk/ru ends in four consonants, while wrong-layout
    /// renderings do constantly. Added after a field miss: `Шкудфтв` (Ireland on RussianWin) has a
    /// vowel and its `дфтв` tail sat exactly at the interior cap, so it read as "plausible ru" and
    /// the rescue declined.
    public static let maxTrailingConsonantRun = 3

    /// Letter pairs that begin no English word. Consulted only for English — the language this
    /// list was measured against; other languages judge by vowels alone. Deliberately conservative:
    /// pairs that begin real words or likely names stay out (`kn`, `gn`, `ps`, `pt`, `sq`, `wr`,
    /// `mn` — mnemonic, `ky` — Kyiv/Kyle, `sr` — Sri).
    static let impossibleEnglishOnsets: Set<String> = [
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
    ]

    /// Vowel-less English tech vocabulary long enough to reach the rescue floor. These are typed
    /// as themselves every day; treating them as gibberish would convert them into Cyrillic noise
    /// (`ctrl` renders as `секд`). A structural test cannot know this — a list can.
    static let knownEnglishTokens: Set<String> = [
        "ctrl", "http", "https", "html", "xhtml", "xml", "smtp", "sftp", "ftps",
        "grpc", "nginx", "systemd", "npm", "pnpm", "wysiwyg",
    ]

    /// Is `word` (lower-cased letter core) shaped like a word of the language whose vowels these
    /// are? An empty vowel set means the language's shape is unknown — the answer is then `false`
    /// ("cannot vouch for it"), and callers must treat that as "do not act", never as gibberish.
    public static func isPlausible(_ word: String, vowels: String, lang: String) -> Bool {
        guard !vowels.isEmpty else { return false }
        if lang == "en", knownEnglishTokens.contains(word) { return true }

        let vowelSet = Set(vowels.lowercased())
        var sawVowel = false
        var run = 0
        for ch in word where ch.isLetter {
            if vowelSet.contains(ch) {
                sawVowel = true
                run = 0
            } else {
                run += 1
                if run > maxConsonantRun { return false }
            }
        }
        guard sawVowel else { return false }
        // After the loop, `run` is the word's trailing consonant run.
        guard run <= maxTrailingConsonantRun else { return false }

        if lang == "en", word.count >= 2,
           impossibleEnglishOnsets.contains(String(word.prefix(2))) {
            return false
        }
        return true
    }
}

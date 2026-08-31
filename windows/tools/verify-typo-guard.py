"""
Drives the typo scenario against the *running, installed* app and lets the app's own log answer.

    python windows/tools/verify-typo-guard.py

Why this exists: the precision guard's whole job is to leave text alone, so a working guard and an
app that is not running produce the same screen. Reading the decision out of the log is the only
honest way to check it, and doing that by hand is how the wrong build got tested once already.

Three traps, all of which cost a run here before being fixed:

  * SendInput validates cbSize against the real INPUT, sized by its largest union member — 40 bytes
    on x64. A union holding only KEYBDINPUT gives 32, and every call is silently rejected while the
    script cheerfully reports success. Check the return value.
  * WM_INPUTLANGCHANGEREQUEST is a request. Verify the foreground layout actually changed instead of
    sleeping and hoping, or you will test the wrong layout and misread the results.
  * A rewrite aborts the moment a real keystroke arrives mid-flight, and injected input is real as
    far as the app is concerned. Type the next word too soon and you do not race the conversion, you
    cancel it.

Injected input is deliberately accepted by Switcher3way (only its own dwExtraInfo-tagged events are
ignored), so the whole thing is scriptable: type a Ukrainian sentence with the exact typos that used
to be converted, then type a Ukrainian word with the English layout active to prove the app has not
merely been switched off.

Keys are sent as virtual key codes, not as Unicode, so the app's hook sees the same thing it sees
from a person's hands.
"""
import ctypes, ctypes.wintypes as w, time, sys, subprocess, pathlib, os
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

u32 = ctypes.WinDLL("user32", use_last_error=True)
u32.GetKeyboardLayoutList.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)]
# LPARAM is pointer-sized: an enhanced-layout HKL does not fit ctypes' default int arg.
u32.PostMessageW.argtypes = [ctypes.c_void_p, ctypes.c_uint,
                             ctypes.wintypes.WPARAM, ctypes.wintypes.LPARAM]

# ---- SendInput plumbing
ULONG_PTR = ctypes.wintypes.WPARAM   # pointer-sized, which is what dwExtraInfo really is

class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", w.WORD), ("wScan", w.WORD), ("dwFlags", w.DWORD),
                ("time", w.DWORD), ("dwExtraInfo", ULONG_PTR)]
class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", w.LONG), ("dy", w.LONG), ("mouseData", w.DWORD), ("dwFlags", w.DWORD),
                ("time", w.DWORD), ("dwExtraInfo", ULONG_PTR)]
class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [("uMsg", w.DWORD), ("wParamL", w.WORD), ("wParamH", w.WORD)]
class _U(ctypes.Union):
    # All three members must be present: SendInput validates cbSize against the real INPUT, which is
    # sized by its largest member. A union holding only KEYBDINPUT gives 32 bytes instead of 40 and
    # every call is silently rejected — which is exactly how the first run of this script "typed"
    # nothing while reporting success.
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT), ("hi", HARDWAREINPUT)]
class INPUT(ctypes.Structure):
    _fields_ = [("type", w.DWORD), ("u", _U)]

assert ctypes.sizeof(INPUT) == 40, f"INPUT is {ctypes.sizeof(INPUT)} bytes, expected 40"

KEYEVENTF_KEYUP = 0x0002

def tap(vk, hold=0.012):
    for flags in (0, KEYEVENTF_KEYUP):
        i = INPUT(type=1, u=_U(ki=KEYBDINPUT(wVk=vk, wScan=0, dwFlags=flags, time=0, dwExtraInfo=0)))
        n = u32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT))
        if n != 1:
            raise OSError(f"SendInput rejected vk={vk:#x}: {ctypes.get_last_error()}")
        time.sleep(hold)

# ---- the ЙЦУКЕН mapping, so a Ukrainian word becomes the keys that produce it
KEYS = "qwertyuiop[]asdfghjkl;'zxcvbnm,."
UK   = "йцукенгшщзхїфівапролджєячсмитьбю"
UK2KEY = {UK[i]: KEYS[i] for i in range(len(KEYS))}
OEM = {"[": 0xDB, "]": 0xDD, ";": 0xBA, "'": 0xDE, ",": 0xBC, ".": 0xBE}

def vk_for(ch):
    return OEM[ch] if ch in OEM else ord(ch.upper())

def type_word(word, cyrillic=True, gap=0.06):
    for ch in word:
        k = UK2KEY[ch] if cyrillic else ch
        tap(vk_for(k))
        time.sleep(gap)

def space():
    # A rewrite erases and retypes at roughly 15 ms per character and aborts the moment a real
    # keystroke arrives mid-flight — so typing the next word too soon does not just race the rewrite,
    # it cancels it. The first run of this script lost its opening conversion exactly that way.
    tap(0x20); time.sleep(2.5)

# ---- layout control
def current_layout():
    """The layout the foreground window is actually using — asked, not assumed."""
    hwnd = u32.GetForegroundWindow()
    tid = u32.GetWindowThreadProcessId(hwnd, None)
    return u32.GetKeyboardLayout(tid) & 0xFFFF

def loaded_layouts():
    """The keyboard layouts actually loaded, as real HKL handles."""
    arr = (ctypes.c_void_p * 32)()
    n = u32.GetKeyboardLayoutList(32, arr)
    return [arr[i] for i in range(n)]


def set_layout(klid, tries=10):
    """Switch the foreground window to the layout whose language matches `klid`.

    Ask the system which layouts are loaded rather than trusting `LoadKeyboardLayout` to hand back the
    installed one. Ukrainian is commonly installed as the *enhanced* variant, whose HKL is
    `FFFFFFFFF0A80422` — a different handle from what loading "00020422" returns, so posting the
    latter changed nothing and the switch silently failed.
    """
    want = int(klid[-4:], 16)
    hkls = [h for h in loaded_layouts() if (h & 0xFFFF) == want]
    if not hkls:
        hkls = [u32.LoadKeyboardLayoutW(klid, 1)]
    for _ in range(tries):
        hwnd = u32.GetForegroundWindow()
        for hkl in hkls:
            u32.PostMessageW(hwnd, 0x0050, 1, hkl)   # WM_INPUTLANGCHANGEREQUEST, SYSCHARSET
        time.sleep(0.6)
        if current_layout() == want:
            print(f"    layout is now {klid}")
            return
    raise SystemExit(f"could not switch to {klid}; foreground layout is {current_layout():#06x}")

LOG = pathlib.Path(os.environ["APPDATA"]) / "Switcher3way" / "Logs" / "switcher3way.log"

def log_size():
    return LOG.stat().st_size if LOG.exists() else 0

def foreground():
    """Class and title of the window that will actually receive the keystrokes."""
    h = u32.GetForegroundWindow()
    cls = ctypes.create_unicode_buffer(128); u32.GetClassNameW(h, cls, 128)
    title = ctypes.create_unicode_buffer(256); u32.GetWindowTextW(h, title, 256)
    return cls.value, title.value


def require_target(*allowed):
    """Refuse to type unless the intended window has focus.

    Not a nicety. Synthesized keystrokes go wherever focus happens to be, and during development this
    script's ad-hoc cousins twice typed test words into a real chat window because Notepad had not
    come to the front. Aborting costs a re-run; not aborting costs someone else's data.
    """
    cls, title = foreground()
    if not any(a.lower() in cls.lower() for a in allowed):
        raise SystemExit(f"ABORTED — foreground is {cls!r} ({title!r}), not {allowed}")
    print(f"    target: {cls} [{title[:40]}]")


def shifted(vk):
    """One keystroke with Shift held — for the capitals the soft gates key off."""
    send_raw(0x10, False); tap(vk); send_raw(0x10, True); time.sleep(0.06)


def send_raw(vk, up):
    i = INPUT(type=1, u=_U(ki=KEYBDINPUT(wVk=vk, wScan=0,
                                         dwFlags=(KEYEVENTF_KEYUP if up else 0),
                                         time=0, dwExtraInfo=0)))
    if u32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT)) != 1:
        raise OSError("SendInput rejected")
    time.sleep(0.02)


def type_latin(word, gap=0.07):
    """Literal keys, honouring capitals — `PeopleOps` must arrive as camelCase, not `peopleops`."""
    for ch in word:
        (shifted if ch.isupper() else tap)(vk_for(ch.upper() if ch.isalpha() else ch))
        time.sleep(gap)


def activate(hwnd):
    """Force a window to the foreground.

    SetForegroundWindow alone is refused unless the caller already owns the foreground, so a freshly
    launched Notepad can sit behind whatever the user was doing. Attaching to the current foreground
    thread first is the documented way round it.
    """
    fg = u32.GetForegroundWindow()
    t1 = u32.GetWindowThreadProcessId(fg, None)
    t2 = ctypes.WinDLL("kernel32").GetCurrentThreadId()
    u32.AttachThreadInput(t2, t1, True)
    u32.ShowWindow(hwnd, 9); u32.BringWindowToTop(hwnd); u32.SetForegroundWindow(hwnd)
    u32.AttachThreadInput(t2, t1, False)
    time.sleep(0.5)


# ---- run
subprocess.Popen(["notepad.exe"])
time.sleep(3)
for _ in range(8):
    h = u32.FindWindowW("Notepad", None)
    if h: activate(h)
    if any(k in foreground()[0] for k in ("Notepad", "RichEdit")): break
    time.sleep(1)
require_target("Notepad", "RichEdit")
mark = log_size()

print("phase 1: Ukrainian typed in the Ukrainian layout, with the typos that used to convert")
set_layout("00020422")
# сьогодні я рукую текст ае даже ща помиляюся
#           ^^^^^ друкую minus д -> reads "here." in English
#                       ^^ не mistyped  ^^^^ адже transposed = a real Russian word
#                                            ^^ що mistyped -> reads "of"
for wd in ["сьогодні", "рукую", "текст", "ае", "даже", "ща", "помиляюся"]:
    type_word(wd); space()

time.sleep(1.5)
print("phase 2: a Ukrainian word typed with the English layout still active — must still convert")
set_layout("00000409")
type_word("ghbdsn", cyrillic=False); space()      # привіт
type_word("cnjkbwz", cyrillic=False); space()     # столиця
time.sleep(2.0)

# ---- phase 3: the gibberish rescue, both directions, plus the words it must NOT touch.
#
# Rescue acts where no dictionary knows the word, so it cannot be checked with dictionary words at
# all. The two halves matter equally: jargon and names must convert, and the look-alikes that are
# meant to stay — an English name typed deliberately in English, camelCase, all-caps, a vowel-less
# Cyrillic abbreviation — must not. A rescue that also grabs `SSO` is worse than no rescue.
print("phase 3: jargon and names no dictionary knows")
set_layout("00000409")

print("  must rescue:")
# All from one real user log. `fgrf` is `апка` on ЙЦУКЕН; `nj fqls ntyfyne` is `то айді тенанту`.
# The layout is forced back before each word deliberately. Left alone, the first conversion switches
# to Ukrainian and every later word is then typed *correctly* and rightly kept — which is the real
# behaviour, and which tests nothing about the words after the first.
for word in ("fgrf", "nj", "fqls", "ntyfyne"):
    set_layout("00000409")
    type_latin(word); space()
# Converting switches the layout to Ukrainian, which is exactly the state needed for the other
# direction: K,y,i,v now render as `Лншм`, and only English fits that shape.
type_latin("Kyiv"); space()

print("  must keep (Cyrillic side):")
set_layout("00020422")
type_latin("[p"); space()          # `хз` — a vowel-less Cyrillic abbreviation, must not be rescued

print("  must keep (Latin side):")
set_layout("00000409")
for word in ("Kyiv", "PeopleOps", "SSO", "npm"):   # a name typed on purpose, camelCase, all-caps, a tool
    type_latin(word); space()

# ---- report what the app decided
text = LOG.read_text(encoding="utf-8", errors="replace")[mark:]
print("\n===== app log for this run =====")
for line in text.splitlines():
    if any(t in line for t in ("auto:", "rewrite:", "layout")):
        print("  " + line.split("  ", 1)[-1] if "  " in line else "  " + line)

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

def set_layout(klid, tries=8):
    want = int(klid[-4:], 16)
    hkl = u32.LoadKeyboardLayoutW(klid, 1)
    for _ in range(tries):
        hwnd = u32.GetForegroundWindow()
        u32.PostMessageW(hwnd, 0x0050, 1, hkl)   # WM_INPUTLANGCHANGEREQUEST, INPUTLANGCHANGE_SYSCHARSET
        time.sleep(0.6)
        if current_layout() == want:
            print(f"    layout is now {klid}")
            return
    raise SystemExit(f"could not switch to {klid}; foreground layout is {current_layout():#06x}")

LOG = pathlib.Path(os.environ["APPDATA"]) / "Switcher3way" / "Logs" / "switcher3way.log"

def log_size():
    return LOG.stat().st_size if LOG.exists() else 0

# ---- run
subprocess.Popen(["notepad.exe"])
time.sleep(2.5)
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

# ---- report what the app decided
text = LOG.read_text(encoding="utf-8", errors="replace")[mark:]
print("\n===== app log for this run =====")
for line in text.splitlines():
    if any(t in line for t in ("auto:", "rewrite:", "layout")):
        print("  " + line.split("  ", 1)[-1] if "  " in line else "  " + line)

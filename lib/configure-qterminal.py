#!/usr/bin/env python3
"""Pin QTerminal's copy/paste shortcuts to the chords SUPER+C / SUPER+V send.

Copy, paste and undo live on SUPER (see the CLIPBOARD section of
config/hypr/omarchy4.lua). A compositor binding cannot copy anything itself --
the application owns the selection -- so SUPER+C and SUPER+V forward
CTRL+SHIFT+C and CTRL+SHIFT+V to a focused terminal. That only works if the
terminal is listening for exactly those chords, which is what this sets.

WHAT CHANGED, AND WHY
---------------------
This script used to move Paste onto Ctrl+V, on the reasoning that Ctrl+V in a
terminal is only "quoted insert" and almost nobody uses it. The GUI chords are
off the terminal entirely now: Ctrl+C is SIGINT, Ctrl+V is quoted insert and
Ctrl+Z is SIGTSTP, with nothing overloading any of them. A box configured by
the older version of this script still has Paste on Ctrl+V, so this moves it
back -- leaving it would mean SUPER+V doing nothing in the box's default
terminal.

Both values are qterminal's own defaults. They are written out anyway, because
the compositor binding depends on them and a default that moves would break
SUPER+C / SUPER+V silently.

Idempotent. Backs up qterminal.ini before the first change.
"""
import configparser
import pathlib
import shutil
import sys
import time

INI = pathlib.Path.home() / ".config/qterminal.org/qterminal.ini"

if not INI.exists():
    sys.exit(f"not found: {INI} — start qterminal once to create it")

# qterminal.ini uses percent-encoded keys ("Paste%20Clipboard"); configparser
# preserves them verbatim as long as we don't lowercase.
cp = configparser.RawConfigParser()
cp.optionxform = str
cp.read(INI, encoding="utf-8")

section = "Shortcuts"
if not cp.has_section(section):
    sys.exit(f"no [{section}] section in {INI}")

want = {
    "Copy%20Selection": "Ctrl+Shift+C",
    "Paste%20Clipboard": "Ctrl+Shift+V",
}
changes = {k: v for k, v in want.items()
           if cp.get(section, k, fallback=None) != v}

if not changes:
    print("qterminal already configured")
    sys.exit(0)

backup = INI.with_suffix(f".ini.bak-{time.strftime('%Y%m%d-%H%M%S')}")
shutil.copy2(INI, backup)
print(f"backed up -> {backup.name}")

for k, v in changes.items():
    old = cp.get(section, k, fallback="(unset)")
    cp.set(section, k, v)
    print(f"  {k}: {old} -> {v}")

with INI.open("w", encoding="utf-8") as fh:
    cp.write(fh, space_around_delimiters=False)

print("Ctrl+C is SIGINT again; copy/paste are SUPER+C / SUPER+V.")
print("Running qterminal windows keep the old shortcuts until restarted.")

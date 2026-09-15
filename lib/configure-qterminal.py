#!/usr/bin/env python3
"""Point QTerminal's paste shortcut at Ctrl+V, keeping Ctrl+Shift+V too.

WHY NOT Ctrl+C FOR COPY HERE
----------------------------
kitty has `copy_or_interrupt`: copy when there IS a selection, SIGINT when
there is not. QTerminal has no such smart action — its Copy shortcut is a
single static binding, so moving it to Ctrl+C would take SIGINT away from every
shell running in QTerminal. On a box that runs long scans that is a bad trade,
so Copy stays on Ctrl+Shift+C here and kitty (SUPER+K) is the terminal to use
when you want full GUI-style bindings.

Paste is different: Ctrl+V in a terminal is only "quoted insert", which almost
nobody uses, so moving paste onto it costs nothing.

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

want = {"Paste%20Clipboard": "Ctrl+V"}
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

print("Copy stays on Ctrl+Shift+C so Ctrl+C keeps sending SIGINT.")

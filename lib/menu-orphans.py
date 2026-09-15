#!/usr/bin/env python3
"""Validate the Kali menu extension against the MERGED menu.

The Omarchy menu is two JSONC files merged by dotted id: Omarchy's default and
our extension. A row in the extension may legitimately parent onto a submenu
that only exists in the default (install.gaming, setup.default.agent, ...), so
orphan detection has to consider both — checking the extension alone reports
false orphans for every such row.
"""
import json
import os
import pathlib
import re
import sys


def load(path):
    raw = pathlib.Path(path).read_text()
    s = re.sub(r"^[ \t]*//[^\n]*(\n|$)", "", raw, flags=re.M)
    s = re.sub(r",(\s*[}\]])", r"\1", s)
    return json.loads(s)


ext = pathlib.Path.home() / ".config/omarchy/extensions/omarchy-menu.jsonc"
omarchy = pathlib.Path(os.environ.get("OMARCHY_PATH",
                       pathlib.Path.home() / ".local/share/omarchy"))
default = omarchy / "default/omarchy/omarchy-menu.jsonc"

try:
    ours = load(ext)
except json.JSONDecodeError as exc:
    print(f"FAIL extension does not parse: {exc}")
    sys.exit(1)

merged = {}
if default.is_file():
    try:
        merged.update(load(default))
    except json.JSONDecodeError as exc:
        print(f"FAIL Omarchy default menu does not parse: {exc}")
        sys.exit(1)
merged.update(ours)

orphans = [
    (k, k.rsplit(".", 1)[0])
    for k in merged
    if "." in k and k.rsplit(".", 1)[0] not in merged
]

subs = sum(1 for v in ours.values() if "action" not in v and "target" not in v)
print(f"OK {len(ours)} extension items, {subs} submenus; {len(merged)} merged")
if orphans:
    print(f"FAIL {len(orphans)} orphan parent(s): {orphans[:5]}")
    sys.exit(1)
print("OK no orphan parents in the merged menu")

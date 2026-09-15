#!/usr/bin/env python3
"""Print the total bytes of runtime when/checked guards in a menu JSONC.

Omarchy batches every visible row's `when` and `checked` into ONE `bash -lc`
script. A generated Kali menu that put a dpkg-query guard on all 917 tools
produced a script so large the process failed to start and the menu came up
empty. Installation is therefore resolved at generation time; this number is
how we keep that from regressing.
"""
import json
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else None
if not path:
    sys.exit("usage: menu-guard-bytes.py <menu.jsonc>")

raw = open(path).read()
s = re.sub(r"^[ \t]*//[^\n]*(\n|$)", "", raw, flags=re.M)
s = re.sub(r",(\s*[}\]])", r"\1", s)
d = json.loads(s)
print(sum(len(v.get("when", "")) + len(v.get("checked", "")) for v in d.values()))

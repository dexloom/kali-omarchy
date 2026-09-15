#!/usr/bin/env python3
"""Comment out walker/appmenu launcher binds that Omarchy 4 supersedes.

Handles multi-line hl.bind(...) calls: the whole call is collected first, and
the walker/appmenu test runs against the JOINED block, not just its first line
(the target command often sits on a continuation line).

Idempotent: an already-commented block is skipped.
"""
import re, sys, pathlib

MARK = "-- [omarchy4 retired]"
path = pathlib.Path.home() / ".config/hypr/hyprland.lua"
lines = path.read_text().split("\n")

out, i, retired = [], 0, 0
while i < len(lines):
    line = lines[i]
    if re.match(r'^\s*hl\.bind\(', line):
        block = [line]
        depth = line.count("(") - line.count(")")
        while depth > 0 and i + 1 < len(lines):
            i += 1
            block.append(lines[i])
            depth += lines[i].count("(") - lines[i].count(")")
        joined = "\n".join(block)
        if re.search(r'walker|appmenu', joined):
            out.extend("-- " + b for b in block)
            out.append(f"{MARK} superseded by the Omarchy menu (SUPER+SPACE)")
            retired += len(block)
        else:
            out.extend(block)
    else:
        out.append(line)
    i += 1

path.write_text("\n".join(out))
print(f"retired {retired} line(s)")

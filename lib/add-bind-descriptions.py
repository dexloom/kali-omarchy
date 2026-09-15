#!/usr/bin/env python3
"""Add `description` to every hl.bind in ~/.config/hypr/hyprland.lua.

WHY THIS IS NOT COSMETIC
------------------------
Hyprland reports binds defined in Lua with the opaque dispatcher `__lua`.
omarchy-menu-keybindings contains:

    [[ -z $description && $dispatcher == "__lua" ]] && continue

so a Lua bind with no description is dropped from the keybindings menu
entirely. Without this pass the menu lists only the Omarchy binds and none of
the window-management or media keys.

The description strings deliberately reuse Omarchy's own vocabulary
("Terminal", "Close window", "Toggle window floating", ...) because
omarchy-menu-keybindings sorts rows by matching those exact words in
prioritize_entries().

Idempotent: a bind that already has a description is left untouched.
"""
import re
import sys
import pathlib

CONFIG = pathlib.Path.home() / ".config/hypr/hyprland.lua"

# Matched against the bind's source text; first hit wins, so order matters.
RULES = [
    (r'"\s*\+\s*Q"',                       "Terminal"),
    (r'window\.close\(\)',                 "Close window"),
    (r'hyprshutdown',                      "Exit Hyprland"),
    (r'exec_cmd\(fileManager\)',           "File manager"),
    (r'window\.float\(',                   "Toggle window floating"),
    (r'exec_cmd\(menu\)',                  "Run launcher"),
    (r'window\.pseudo\(\)',                "Toggle window pseudotile"),
    (r'layout\("togglesplit"\)',           "Toggle window split"),
    (r'direction\s*=\s*"left"',            "Focus left"),
    (r'direction\s*=\s*"right"',           "Focus right"),
    (r'direction\s*=\s*"up"',              "Focus up"),
    (r'direction\s*=\s*"down"',            "Focus down"),
    (r'workspace\s*=\s*"e\+1"',            "Next workspace"),
    (r'workspace\s*=\s*"e-1"',             "Previous workspace"),
    (r'toggle_special\("magic"\)',         "Toggle scratchpad"),
    (r'workspace\s*=\s*"special:magic"',   "Move window to scratchpad"),
    (r'focus\(\{\s*workspace\s*=\s*i\}?',  'Switch to workspace " .. i .. "'),
    (r'window\.move\(\{\s*workspace\s*=\s*i\s*\}',
                                           'Move window to workspace " .. i .. "'),
    (r'window\.drag\(\)',                  "Move window"),
    (r'window\.resize\(\)',                "Resize window"),
    (r'window\.resize\(\{[^}]*x\s*=\s*-',  "Shrink window"),
    (r'window\.resize\(\{',                "Expand window"),
    (r'AudioRaiseVolume',                  "Volume up"),
    (r'AudioLowerVolume',                  "Volume down"),
    (r'AudioMicMute',                      "Mute microphone"),
    (r'AudioMute',                         "Mute audio"),
    (r'MonBrightnessUp',                   "Brightness up"),
    (r'MonBrightnessDown',                 "Brightness down"),
    (r'AudioNext',                         "Next track"),
    (r'AudioPause',                        "Play/pause"),
    (r'AudioPlay',                         "Play/pause"),
    (r'AudioPrev',                         "Previous track"),
]


def describe(text):
    for pattern, desc in RULES:
        if re.search(pattern, text):
            return desc
    return None


def add_description(block, desc):
    """Insert description into the bind's opts table, creating one if needed."""
    if "description" in block:
        return block, False

    # Find the closing paren of the hl.bind(...) call.
    depth, end = 0, None
    for i, ch in enumerate(block):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None:
        return block, False

    head, tail = block[:end], block[end:]

    # Does the call already end in an opts table, e.g. `{ locked = true }`?
    m = re.search(r',\s*\{([^{}]*)\}\s*$', head)
    if m:
        inner = m.group(1).strip().rstrip(",")
        new = f', {{ {inner}, description = "{desc}" }}'
        head = head[:m.start()] + new
    else:
        head = head.rstrip() + f', {{ description = "{desc}" }}'

    # A rule may end in a concat (`... " .. i .. "`), which leaves a trailing
    # `.. ""`. Valid Lua, but noise in a config people read.
    head = head.replace(' .. ""', "")

    return head + tail, True


def main():
    src = CONFIG.read_text()
    lines = src.split("\n")
    out, i, added, skipped = [], 0, 0, 0

    while i < len(lines):
        line = lines[i]
        if re.match(r'^\s*(local\s+\w+\s*=\s*)?hl\.bind\(', line):
            block = [line]
            depth = line.count("(") - line.count(")")
            while depth > 0 and i + 1 < len(lines):
                i += 1
                block.append(lines[i])
                depth += lines[i].count("(") - lines[i].count(")")

            joined = "\n".join(block)

            # Already described (hand-written, or a previous run) — nothing to
            # do, and no rule needs to exist for it.
            if "description" in joined:
                skipped += 1
                out.extend(block)
                i += 1
                continue

            desc = describe(joined)
            if desc:
                new, changed = add_description(joined, desc)
                if changed:
                    added += 1
                else:
                    skipped += 1
                out.extend(new.split("\n"))
            else:
                skipped += 1
                print(f"  no rule matched: {block[0].strip()[:70]}", file=sys.stderr)
                out.extend(block)
        else:
            out.append(line)
        i += 1

    CONFIG.write_text("\n".join(out))
    print(f"descriptions added: {added}, left alone: {skipped}")


if __name__ == "__main__":
    main()

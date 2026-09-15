---
name: kali-omarchy-hyprland
version: 0.2.0
description: "Omarchy Hyprland session: Lua config, binds, window rules, reload safety."
author: kali-omarchy
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hyprland, wayland, omarchy, lua, keybinds, window-rules]
    related_skills: [kali-omarchy-system]
---

# Hyprland (Omarchy Lua Config) Management

Manages the Hyprland Wayland session as configured by Omarchy 4: Lua config
under `~/.config/hypr/`, the `hl.*` API for binds, rules and dispatchers, and
reload safety. For packages and general OS work load `kali-omarchy-system`.

## When to Use

- Add or change keybinds, window rules, autostart entries, monitor layout,
  animations, gestures or workspace behaviour.
- Diagnose "my keybind stopped working", "this window tiles when it should
  float", or "my edit had no effect".
- Don't use for: package installs, or anything owned by the Quickshell desktop
  (bar, menu, panels) — that is `~/.config/omarchy/` and `kali-omarchy-system`.

## The one fact that matters most

**Lua only. Never create `hyprland.conf`.**

Hyprland looks for `hyprland.conf` *before* `hyprland.lua`. A single stray
`.conf` silently shadows the entire Lua configuration — every edit stops having
any effect, with no error anywhere. Config tools and blog posts will happily
write one.

The corollary: almost every Hyprland example online uses the classic
`bind = SUPER, Q, exec, ...` syntax. Translate it; never paste it.

## Environment Facts

- `~/.config/hypr/hyprland.lua` — the entrypoint. It `require`s the Omarchy
  wiring (`omarchy4.lua`) and holds local binds and settings.
- `~/.config/hypr/omarchy4.lua` — Omarchy integration: window rules, gestures,
  environment, session handoff.
- A few genuine `.conf` files are fine and expected: `hyprlock.conf`,
  `hyprpaper.conf`, `hyprsunset.conf`, `xdph.conf`. These configure *other
  binaries*, not Hyprland. Only `hyprland.conf` is the trap.
- Quickshell (bar, menu, panels) lives in `~/.config/omarchy/` — check there
  before assuming Hyprland owns a visual element.

## The Lua API

```lua
hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"), { description = "Terminal" })
hl.window_rule({ name = "float-dialogs", match = { class = "^pavucontrol$" }, float = true })
hl.gesture({ fingers = 2, direction = "horizontal", action = "resize", mods = "SUPER" })
hl.env("LIBVA_DRIVER_NAME", "iHD")
hl.config.general.resize_on_border = true
```

- Dispatchers are **method calls, not strings**: `hl.dsp.exec_cmd(cmd)`,
  `hl.dsp.window.close()`, `hl.dsp.workspace.move(n)`. Read the existing config
  for the exact vocabulary before inventing a call; `hl.dsp` is not documented
  anywhere else.
- **Every bind MUST carry `description = "..."`.** Hyprland reports Lua binds
  with the opaque dispatcher `__lua`, and `omarchy-menu-keybindings` drops any
  `__lua` bind without a description. No description means an invisible keybind.
- One `hl.window_rule` per property. `float`, `center` and `size` are three
  separate rules over the same match, not one rule with three fields.

## Window rules match on app_id — which some terminals cannot set

Rules matching `class` match the Wayland `app_id`. Check that the application
can actually set one before writing a rule against it:

```bash
hyprctl clients | grep -A2 class      # what the window actually reports
```

QTerminal, for example, has no flag for it and hardcodes its application name,
so every QTerminal window is `class=qterminal` and no per-window rule can
distinguish them. The workaround is to attach rules at spawn time instead:

```bash
hyprctl dispatch 'hl.dsp.exec_cmd("[float;center;size 875 600] <command>")'
```

which is terminal-agnostic and survives the `uwsm-app` handoff.

## Procedure

1. Read the target file first — they are small and commented. Completion: you
   know which file owns the setting you are changing.
2. Edit, preserving the comment-banner conventions. Completion: the diff shows
   only your change.
3. Reload: `terminal(command="hyprctl reload", timeout=30)`. Completion: output
   is `ok` with no error lines.
4. Verify against the compositor, not against the file:
   - `hyprctl binds` — your key is listed (dispatcher `__lua`) and fires.
   - `hyprctl clients` — float state, size and position for a rule change.
   - `hyprctl monitors` — outputs after a monitor change.
   Completion: observable state matches the edit.

## Reload and recovery

- `hyprctl reload` re-reads the config live; no logout needed.
- A Lua syntax error can leave binds dead. Every tool here writes
  `hyprland.lua.bak-<timestamp>` first:

```bash
ls -t ~/.config/hypr/hyprland.lua.bak-* | head -1
```

- `omarchy-refresh-config hypr/hyprland.lua` restores the Omarchy default (with
  a `.bak-*` of yours). Re-apply custom edits afterwards.
- If the session is unusable — black screen, no input — switch to a TTY
  (`Ctrl+Alt+F2`), restore the newest backup, and log back in.

## Talking to the compositor from outside the session

Over SSH, or from any process that did not inherit the session environment:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-1
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
```

Resolve the signature by mtime every time. Hyprland leaves previous instances'
socket directories behind, and a stale signature addresses a compositor that no
longer exists — `hyprctl` then reports confidently about nothing.

## Pitfalls

- Pasting `.conf` syntax into a Lua file, or creating `hyprland.conf` at all.
- Omitting `description =` on a bind, making it invisible to the menu.
- Writing a class rule for an application that cannot set an app_id.
- Assuming a rule applied because the file says so. Check `hyprctl clients`.
- `omarchy-refresh-*` overwriting customised config (it does keep a `.bak-*`).
- Trusting an inherited `HYPRLAND_INSTANCE_SIGNATURE`.

## Verification

- `hyprctl reload` returns `ok` with no error lines.
- `hyprctl binds` lists the bind, and pressing it does the thing.
- `hyprctl clients -j` shows the expected `floating`, `at` and `size`.

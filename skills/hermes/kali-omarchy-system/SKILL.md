---
name: kali-omarchy-system
version: 0.2.0
description: "Manage a Kali box running the Omarchy 4 desktop: apt, the Omarchy command suite, session services."
author: kali-omarchy
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [kali, debian, omarchy, hyprland, apt, wayland, quickshell]
    related_skills: [kali-omarchy-hyprland]
---

# Kali + Omarchy System Management

Manages a Kali Linux Rolling workstation running the Omarchy 4 desktop
(Hyprland + Quickshell). Covers package management, the Omarchy command suite,
and session services. For Hyprland config and keybinds load
`kali-omarchy-hyprland`.

## When to Use

- Install, update or remove packages; check system or service state.
- Anything touching `$OMARCHY_PATH`, Omarchy themes, or the Quickshell desktop.
- Diagnosing a menu row, panel or notification that does not work.
- Don't use for: Hyprland config edits and keybinds (use
  `kali-omarchy-hyprland`).

## The one fact that matters most

**This is Debian, not Arch.** Omarchy is an Arch project; its documentation,
its own scripts and every blog post about it assume `pacman` and `yay`. None of
that exists here. Package management is **apt**.

This is the single most common way an agent goes wrong on this machine, because
the desktop looks exactly like the Arch one it read about. When an Omarchy
document says `pacman -S x`, the equivalent here is `sudo apt install x`, and
when an Omarchy *command* wraps pacman it simply cannot work — see below.

## Environment Facts

- OS: Kali GNU/Linux Rolling (Debian-based). Packages: `apt` / `dpkg`.
- Desktop: Hyprland (Wayland) + Quickshell, Omarchy 4 layout.
- Omarchy home: `~/.local/share/omarchy`, exported as `$OMARCHY_PATH`.
- Omarchy commands: `~/.local/share/omarchy/bin/`, on PATH via `~/.profile`.
- The whole shell — bar, main menu, polkit prompt, wifi/audio/bluetooth panels,
  lock screen — is **one `quickshell` process**, not separate daemons.
- `sudo` needs a password. Ask the user to run sudo commands; do not attempt to
  supply a password.
- The session runs under uwsm as a systemd user session, so session-scoped
  units are `systemctl --user`.

## Omarchy commands: which ones work here

Safe — no package manager involved:

- `omarchy-restart-shell` — restart Quickshell (bar, menu, panels, polkit, lock).
- `omarchy-notification-send` — notifications. Use this, not `notify-send`.
- `omarchy-menu`, `omarchy-menu-keybindings` — the menus.
- `omarchy-cmd-present <cmd>` / `omarchy-cmd-missing <cmd>` — exit-code presence
  checks; used as menu `when:` predicates.
- `omarchy-refresh-*` — re-copy an Omarchy default over the user's copy. These
  **overwrite local customisation** (keeping a timestamped `.bak-*`). Check what
  is customised before running one.
- `omarchy-launch-floating-terminal-with-presentation <cmd>` — run a command in
  the branded centred terminal. Every privileged menu row goes through this.

Do **not** work — they wrap pacman/yay:

- `omarchy-pkg-add`, `omarchy-pkg-drop`, `omarchy-pkg-present`
- `omarchy-update`, `omarchy-update-status` (release-channel switching)
- Roughly 40 of Omarchy's menu rows, which is why the deploy hides them behind
  `"when": "omarchy-cmd-present pacman"` — false on Debian.

## Package Management (apt)

```bash
apt-cache policy <pkg>            # installed version and candidate
apt-cache search --names-only <re>
sudo apt install <pkg>
sudo apt purge <pkg>
sudo apt update && sudo apt full-upgrade     # Kali is rolling; use full-upgrade
dpkg -S <path>                    # which package owns a file
dpkg -L <pkg>                     # what a package installed
apt-file search <cmd>             # which package provides a missing command
```

The menu's apt rows are wrappers around these, in `~/.local/bin/`:
`kali-apt-install-prompt`, `kali-apt-remove-prompt`, `kali-metapackage-prompt`.
Prefer reading them over reinventing their logic — they already handle the
"package does not exist, here are close matches" case.

## How to Run

Frame invocations through the `terminal` tool, e.g.
`terminal(command="apt-cache policy quickshell", timeout=60)`. Anything with
`sudo` needs the user; tell them the exact command rather than running it.

## Procedure

1. Check state before acting: `apt-cache policy <pkg>`, `command -v <tool>`,
   `systemctl --user is-active <unit>`. Completion: you know installed vs
   missing before changing anything.
2. Make the change. Package work via apt; desktop/session work via the Omarchy
   command that owns it rather than hand-rolled systemctl or dbus calls.
   Completion: the matching presence or status check reflects the new state.
3. If the repo is present, re-run its verifier — `12-omarchy4-verify.sh`, no
   sudo, changes nothing — and read the tail. Completion: the pass/fail counts
   are what they were before your change, or better.

## Pitfalls

- Reaching for `pacman`. It is not installed and never was.
- Calling `notify-send` directly — notifications go through Quickshell's
  notification service; use `omarchy-notification-send`.
- Assuming a failed menu row is broken configuration. Check first whether it is
  one of the Arch-only rows: run its command by hand and look for `pacman`.
- Running `omarchy-refresh-*` on a file with local customisation. It keeps a
  `.bak-*`, but the live file is replaced by the Omarchy default.
- `~/.local/bin` and `~/.local/share/omarchy/bin` are on PATH via `~/.profile`,
  which only a **login** shell reads. A non-login shell, a systemd unit or a
  `bash -c` from another process may not have them — export PATH explicitly in
  scripts rather than assuming.
- Killing processes with `pkill -f`. The pattern matches the agent's own command
  line as readily as the target's. Use `pgrep -x` and kill by PID.

## Verification

- `apt-cache policy <pkg>` shows the expected installed version.
- `pgrep -a quickshell` shows one process after `omarchy-restart-shell`.
- `systemctl --user is-active <unit>` for session units you touched.
- `12-omarchy4-verify.sh` if the setup repo is on the box.

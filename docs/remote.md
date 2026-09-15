# Remote transformation

The agent runs on your workstation. The Kali box is reached over SSH and never
runs the agent itself.

This is the path this repo was built on, and the one to prefer for a first
conversion. The transformation rebuilds the graphical session; an agent that
lives outside that session cannot be killed by it.

## Preconditions

On the box:

- Kali Rolling, `openssh-server` running
- A user with sudo (the password will be needed twice, by you, not the agent)

On your workstation:

- An SSH key, and an entry in `~/.ssh/config` so the box has a short name

```bash
ssh-keygen -t ed25519 -f ~/.ssh/kali -C "kali-omarchy"
ssh-copy-id -i ~/.ssh/kali.pub <user>@<box-ip>
```

```sshconfig
# ~/.ssh/config
Host kali
    HostName <box-ip>
    User <user>
    IdentityFile ~/.ssh/kali
    ServerAliveInterval 30
```

`ServerAliveInterval` matters more than it looks: several steps restart network
and session units, and without it a stalled connection is indistinguishable from
a hung command.

Confirm with `ssh kali true` before starting. The agent should treat a failure
here as a stop condition, not something to work around.

## Getting the repo onto the box

The scripts resolve their own directory, so the repo can live anywhere:

```bash
rsync -a --exclude .git ./ kali:~/kali-omarchy/
```

Keep using `rsync` for every subsequent change rather than editing on the box
and losing track of which copy is authoritative. If you *do* work on the box —
which is often faster — sync back explicitly and commit from the workstation:

```bash
rsync -rc --delete --exclude .git kali:kali-omarchy/ ./
```

`-c` compares checksums rather than timestamps, so an SSH round trip does not
show up as a change.

## The run

```bash
ssh kali 'sudo ~/kali-omarchy/10-omarchy4-packages.sh'   # you, interactively
ssh kali '~/kali-omarchy/13-omarchy4-fonts.sh'
ssh kali '~/kali-omarchy/11-omarchy4-deploy.sh'
ssh kali '~/kali-omarchy/12-omarchy4-verify.sh'
```

Step 10 needs a password on a TTY. An agent cannot supply it and **should not
try** — no `echo password | sudo -S`, no NOPASSWD edit to `/etc/sudoers`. The
correct behaviour is to stop and tell you which command to run.

Then start Hyprland on the box (`start-hyprland` from a TTY, or pick the session
at the display manager) and re-run step 12 — the live-session assertions only
mean something once a compositor is up.

## Talking to a running session over SSH

An SSH session is not the graphical session, so none of the Wayland environment
is inherited. Every command that touches the compositor needs this preamble:

```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-1
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
```

The last line is not optional and not cosmetic. Hyprland leaves the socket
directories of **previous** instances behind, so a hardcoded or stale signature
will address a compositor that no longer exists and every `hyprctl` call will
either fail or silently report the wrong thing. Always resolve it by mtime.
`12-omarchy4-verify.sh` does this for you; ad-hoc commands must do it themselves.

With that set, the usual tools work over SSH:

```bash
hyprctl clients      # windows, classes, float state, geometry
hyprctl binds        # every bind; Lua binds report dispatcher __lua
hyprctl monitors     # outputs and which GPU drives them
hyprctl reload       # re-read the Lua config; prints errors, returns "ok"
```

## Verifying without a screen

`hyprctl -j clients` is more reliable than a screenshot for anything
structural — position, size, floating state, class, title — and it is what
proved the centred-prompt work in this repo.

For the visual half, `grim` captures the compositor's output:

```bash
ssh kali 'grim /tmp/shot.png' && scp kali:/tmp/shot.png .
```

Two traps: a **locked** screen captures as a blank image, and so does a display
that DPMS has turned off. Check `pgrep hyprlock` before concluding that
something rendered wrong — a blank capture usually means the screen is locked,
not that the UI is broken.

## Restarting things

```bash
omarchy-restart-shell         # Quickshell: bar, menu, panels, polkit, lock
hyprctl reload                # Hyprland config only
systemctl --user restart <unit>
```

Prefer these to killing processes. If a process really must be killed, kill it
**by PID**, never with `pkill -f`. See
[agent-safety.md](agent-safety.md#never-pkill--f) for what that costs.

## When the desktop breaks

Nothing about a broken Hyprland session affects your SSH access, which is the
whole reason to work this way. Recovery is ordinary file work:

```bash
ls -t ~/.config/hypr/hyprland.lua.bak-* | head -1   # newest backup
```

Every script in this repo backs up before it overwrites, so there is always one.
Restore it, `hyprctl reload`, and the session comes back without a logout.

If the compositor itself is gone, start it again from a TTY on the box — that
does need physical or console access, which is the one thing SSH cannot give
you. It is also the only step in the entire process that does.

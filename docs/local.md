# Local transformation

The agent runs on the Kali box itself and has sudo. Nothing is done over SSH.

This removes the second machine and lets the agent complete the root steps
unattended. It also puts the agent inside the thing it is rebuilding, which is
the entire difficulty.

## Where to run the agent from

**Not from the Hyprland session being converted.** The deploy masks units,
restarts the shell and reloads the compositor; a terminal window inside that
session can vanish mid-command, taking the agent's context with it.

In order of preference:

1. **A TTY** — `Ctrl+Alt+F2`, log in, run the agent there. Fully outside the
   graphical session, survives everything the transformation does.
2. **`tmux` on a TTY** — same, plus the agent survives your logging out, and
   you can reattach from anywhere.
3. **SSH from a phone or tablet into the box** — technically the remote path
   with the box as its own client; works fine.

Running the agent from the graphical session is the one arrangement to avoid,
and it is also the most tempting one, because that is where you already are.

## Giving the agent sudo

Only two scripts need root: `10-omarchy4-packages.sh` and `17-lock-pam.sh`
(plus `15-nvidia-offload.sh` if you want the NVIDIA driver). Three options,
worst to best:

**Blanket NOPASSWD.** Don't. It makes every later mistake a root mistake, and it
outlives the transformation.

**A cached credential.** Run `sudo -v` yourself, then let the agent work inside
the 15-minute window. Simple, temporary, and it fails closed — but it will
expire mid-run and the agent will block on a prompt it cannot answer.

**A scoped sudoers drop-in.** Grant NOPASSWD for exactly the scripts involved,
then remove it:

```bash
sudo install -m 0440 /dev/stdin /etc/sudoers.d/kali-omarchy <<'EOF'
<user> ALL=(root) NOPASSWD: /opt/kali-omarchy/10-omarchy4-packages.sh, /opt/kali-omarchy/17-lock-pam.sh
EOF
```

```bash
sudo rm /etc/sudoers.d/kali-omarchy     # when the transformation is done
```

Be clear-eyed about what that buys. It is a **convenience boundary, not a
security one** — unless the scripts are owned by root and not writable by the
agent's user, anyone who can edit them and run them NOPASSWD already has root:

```bash
sudo mkdir -p /opt/kali-omarchy
sudo rsync -a --chown=root:root --exclude .git ./ /opt/kali-omarchy/
sudo chmod -R go-w /opt/kali-omarchy
```

Run from `/opt/kali-omarchy` and the drop-in is a real restriction. Run from a
copy in `$HOME` and it is decoration. Either is defensible for a single-user
laptop; only one of them is honest about what it is.

## The run

```bash
sudo /opt/kali-omarchy/10-omarchy4-packages.sh
/opt/kali-omarchy/13-omarchy4-fonts.sh
/opt/kali-omarchy/11-omarchy4-deploy.sh
/opt/kali-omarchy/12-omarchy4-verify.sh
```

Steps 13, 11 and 12 must run as **your** user, not root — they write to
`~/.config`, `~/.local/share` and `~/.local/bin`. Running the deploy under sudo
puts the entire configuration in `/root` and leaves your session untouched,
which looks like success and is not. The scripts do not guard against this;
`12-omarchy4-verify.sh` will fail loudly afterwards, which is the next best
thing.

Then start Hyprland and re-run step 12.

## Recovery

The failure mode the remote path does not have: the agent's own terminal is gone
and there is no second machine.

- `Ctrl+Alt+F2` reaches a TTY from a broken graphical session in almost every
  case, including a black screen with no input.
- From there, restore the newest backup — every script writes one:

```bash
ls -t ~/.config/hypr/hyprland.lua.bak-* | head -1
```

- If Hyprland will not start at all, the display manager still offers other
  sessions. Kali's default desktop is untouched by any of this and remains a
  working way back in.

Deciding on the escape route *before* starting is the difference between a
five-minute recovery and a reinstall. An agent working locally should confirm a
TTY is reachable as its first action, not its last.

## After the transformation

This is where the local path becomes the better one. Day-to-day management —
adding a keybind, installing a tool, changing a window rule — is ordinary work
that wants to happen on the machine, and the
[Hermes skills](../skills/hermes/README.md) exist so an agent does it with the
right facts instead of rediscovering them:

```bash
mkdir -p ~/.hermes/skills/devops
cp -r skills/hermes/kali-omarchy-* ~/.hermes/skills/devops/
```

The single most valuable thing they encode is that **this box is Debian**. Every
Omarchy document, command example and blog post assumes Arch and pacman. An
agent that reads those and acts on them will reach for `pacman -S` on a machine
that has never had it, and the failure is confusing rather than obvious.

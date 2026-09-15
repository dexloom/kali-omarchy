# kali-omarchy

Turn a raw **Kali Linux Rolling** install into the **Omarchy 4** desktop —
Hyprland + Quickshell, with Kali's full toolset as a structured menu — and do it
by handing the job to a coding agent instead of following a wiki page by hand.

Built and verified against **Omarchy v4.0.3** (`omacom/omarchy`, branch
`quattro`) on Kali Rolling 2026.3.

> There is no Omarchy "4.5". The 4.x line is 4.0.0 … 4.0.3, and the project
> moved from `basecamp/omarchy` to `omacom/omarchy`.

Omarchy targets Arch. Kali is Debian. Most of this repo is the difference
between those two facts: apt instead of pacman, Debian's PAM stack instead of
Arch's, a Nerd Font repack that is missing half its glyphs, a terminal that
cannot set a Wayland `app_id`. Each one is documented where it bites.

## What you end up with

| Surface | Comes from | Key |
|---|---|---|
| Main menu | `omarchy.menu` plugin | `SUPER+SPACE` |
| Kali menu | generated from Kali's own package metadata | `SUPER+SHIFT+K` |
| Keybindings menu | `omarchy-menu-keybindings` | `SUPER+K` |
| Root password prompt | centred floating terminal | automatic |
| Wifi / Bluetooth / Audio | Quickshell bar panels | `SUPER+CTRL+W` / `+B` / `+A` |
| Lock screen | `omarchy.lock` plugin | `SUPER+ESCAPE` |
| Voice dictation | Voxtype + waveform OSD | via the menu |

The Kali menu is **generated**, not hand-written: `lib/generate-kali-menu.py`
reads Kali's own metadata and produces ~66 categories over ~996 tools, so it
stays correct as Kali's package set moves.

## Two ways to run the transformation

Both end at the same place. They differ in where the agent lives, and therefore
in what breaks it.

| | [**Remote**](docs/remote.md) | [**Local**](docs/local.md) |
|---|---|---|
| Agent runs on | your workstation | the Kali box |
| Reaches the box via | SSH | directly |
| sudo | the human runs the two root scripts | the agent runs them |
| If the desktop breaks | agent is unaffected, keeps working | agent may lose its own terminal |
| Needs on the box | `sshd`, a key, nothing else | an agent runtime + credentials |
| Best for | first-time conversion, remote/headless boxes | ongoing management, no second machine |

**Start with remote if you have a second machine.** The whole point of the
transformation is that it rebuilds the graphical session, and an agent whose
only channel *is* that graphical session can cut its own connection halfway
through. Over SSH it cannot.

The local path becomes the better one *after* the box is converted, for
day-to-day management — which is what the [Hermes skills](#hermes-skills) are
for.

### Quickstart — remote

On your workstation, with the repo cloned and `ssh kali` reaching the box:

```bash
scp -r . kali:~/kali-omarchy
```

Then hand the agent [`docs/remote.md`](docs/remote.md). It runs everything
except the two root steps, which it will stop and ask you to run:

```bash
sudo ~/kali-omarchy/10-omarchy4-packages.sh
sudo ~/kali-omarchy/17-lock-pam.sh
```

### Quickstart — local

On the Kali box, with an agent that has a terminal tool:

```bash
git clone <this repo> ~/kali-omarchy
```

Then hand the agent [`docs/local.md`](docs/local.md). Run the agent from a TTY
or inside `tmux`, never from the Hyprland session it is about to replace.

## The scripts

Numbered, ordered, and individually re-runnable. Every one is idempotent: they
back up what they overwrite to `<file>.bak-<timestamp>` and can be run again
safely.

| Step | sudo | Does |
|---|---|---|
| `10-omarchy4-packages.sh` | **yes** | quickshell, uwsm, lua5.4, inotify-tools, QtQuick.Effects, fonts, VA-API, ffmpeg, pipewire-alsa, libxcb-cursor0 |
| `13-omarchy4-fonts.sh` | no | upstream Symbols Nerd Font + Omarchy's own icon font |
| `11-omarchy4-deploy.sh` | no | generates the Kali menu, patches the Omarchy checkout, installs config, adds bind descriptions, masks conflicting units, dedups the Apps list |
| `12-omarchy4-verify.sh` | no | 52 assertions; changes nothing |
| `14-omarchy4-extras.sh` | part | Voxtype + OSD (no root), LocalSend `.deb` (root) |
| `15-nvidia-offload.sh` | **yes** | proprietary NVIDIA driver for compute, then **reboot** |
| `16-voxtype-gpu.sh` | no | swaps Voxtype to the Vulkan (or `--cuda`) build; `--pin-device N` pins the GPU |
| `17-lock-pam.sh` | **yes** | Debian PAM stack for the lock screen |

Minimum viable order is `10 → 13 → 11 → 12`. Steps 14–17 are optional;
15 and 16 are hardware-specific (see [Hardware](#hardware)).

Nothing under `config/` is applied by hand. Every shipped file is installed by
one of these steps and asserted by `12-omarchy4-verify.sh`, so a file that is
shipped but never installed is a bug, not a convention.

`12-omarchy4-verify.sh` is the contract. It needs no sudo, changes nothing, and
is the single instruction that tells an agent whether it is done. **An agent
should run it after every change**, and report its tail verbatim rather than
summarising.

## Rules an agent must follow

Read [`docs/agent-safety.md`](docs/agent-safety.md) before driving this
unattended. It is short, and every rule in it is there because it was learned
the expensive way. The ones that cost the most time:

- **Never `pkill -f <pattern>`** when the pattern also matches the agent's own
  command line. It kills the agent, not the target. This happened twice.
- **Never launch a VPN client directly** over a remote session — it reconfigures
  routing and drops the connection.
- **Hyprland is configured in Lua only.** Adding a `hyprland.conf` silently
  shadows `hyprland.lua`, because Hyprland prefers `.conf`.
- **Keep an escape route.** A TTY (`Ctrl+Alt+F2`) for local, a second SSH
  session for remote.
- **Don't test the lock screen** until everything else is verified — you can
  lock yourself out of your own visual verification.

## Hermes skills

`skills/hermes/` holds two [Hermes](https://github.com/hermes-agent) management
skills for the box *after* it is converted. They encode the environment facts an
agent otherwise has to rediscover — which is where a general-purpose agent
usually goes wrong on this system, since it looks like Arch documentation but is
Debian underneath.

| Skill | Covers |
|---|---|
| `kali-omarchy-system` | apt, the Omarchy command suite, services, system state |
| `kali-omarchy-hyprland` | the Lua config API, binds, window rules, reload safety |

Install:

```bash
mkdir -p ~/.hermes/skills/devops
cp -r skills/hermes/kali-omarchy-* ~/.hermes/skills/devops/
```

See [`skills/hermes/README.md`](skills/hermes/README.md) for how they load and
how to adapt them to another agent runtime — they are plain Markdown with YAML
frontmatter and port to Claude Code skills or a system prompt with no changes
beyond the frontmatter.

## Hardware

Everything in steps 10–14 and 17 is hardware-independent.

Steps **15** and **16** are not. They were written for a laptop with an Intel
iGPU driving the display and an NVIDIA MX350 available for compute only, and
they carry that machine's measurements in their comments:

- `LIBVA_DRIVER_NAME=iHD` — correct for Intel, wrong for AMD
- The Vulkan device index is machine-specific — `16-voxtype-gpu.sh --pin-device N`,
  never a shipped default
- Voxtype model choice assumes 2 GB of VRAM (`small` fits; `large-v3-turbo` OOMs)

Read those two scripts before running them. Skip both if you have no discrete
GPU; nothing else depends on them.

## Repo layout

```
10..17-*.sh            the transformation, in order
config/                everything that gets installed onto the box
  hypr/                hyprland.lua + omarchy4.lua  (Lua only — never .conf)
  omarchy/             Quickshell shell.json, bar scripts, menu extras
                       (extensions/ is generated by the deploy, not shipped)
  bin/                 interactive menu helpers (apt install, nmap, searchsploit…)
  systemd/             user units and drop-ins
lib/                   generators and audit tools the deploy calls
patches/               applied to the Omarchy checkout; idempotent, self-describing
docs/
  remote.md            agent on a workstation, box over SSH
  local.md             agent on the box, with sudo
  agent-safety.md      the rules, and why each one exists
  reference.md         deep per-subsystem reference (~900 lines)
  omarchy-4-architecture.md   how Omarchy 4 is put together
skills/hermes/         post-conversion management skills
```

## A note on the name `kali-hyprland`

Files installed onto the box carry `kali-hyprland` provenance comments, and the
NVIDIA step writes `/etc/modprobe.d/nvidia-kali-hyprland.conf`. That was this
project's earlier name, and those strings are **load-bearing**: the deploy greps
for them to stay idempotent, and `lib/hide-kali-from-apps.py --restore` finds
its own files by them. Renaming them would make the deploy re-append its PATH
lines on every run and orphan the modprobe file on already-configured machines.
They are left alone deliberately.

## Status

Verified end to end on one machine: Kali Rolling 2026.3, Intel Iris Plus +
NVIDIA MX350, LightDM, QTerminal. `12-omarchy4-verify.sh` reports **52 passed,
0 failed**.

Known not to work: Omarchy's screensaver, which needs `ttfx` — an AUR package
with no Debian equivalent. It exits 1 by design. The lock screen is separate and
works.

## License

MIT. See [LICENSE](LICENSE).

Omarchy itself is a separate project with its own license; this repo configures
it, vendors none of it, and patches a checkout you obtain yourself.

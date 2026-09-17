# Reference

Deep, per-subsystem notes on the converted box: what each piece does, why it is
built the way it is, and what broke on the way there. Start at the
[README](../README.md) for the transformation itself; come here when you need to
know why something is the way it is.

Turn a raw **Kali Linux Rolling** install into the Omarchy 4 desktop —
Hyprland + Quickshell, with the full Kali toolset as a structured menu.

Built against **Omarchy v4.0.3** (`omacom/omarchy`, branch `quattro`).

> There is no Omarchy "4.5". The 4.x line is 4.0.0 … 4.0.3, and the repo moved
> from `basecamp/omarchy` to `omacom/omarchy`.

## What you get

| Surface | Where it comes from | Key |
|---|---|---|
| Main menu | `omarchy.menu` plugin | `SUPER+SPACE` |
| Kali menu | generated from Kali's own metadata | `SUPER+SHIFT+K` |
| Keybindings menu | `omarchy-menu-keybindings` | `SUPER+K` |
| Root password modal | `omarchy.polkit` service plugin | automatic |
| Wifi / Bluetooth / Audio | bar panels | `SUPER+CTRL+W` / `+B` / `+A` |
| Window resize | Hyprland | `SUPER`+scroll |
| Install Kali tools | `install.kali` branch | via the menu |

## Install

```bash
sudo ./10-omarchy4-packages.sh   # packages — the only step needing your password
./13-omarchy4-fonts.sh           # icon fonts, downloads ~2.3 MB
./11-omarchy4-deploy.sh          # config — idempotent, safe to re-run
./12-omarchy4-verify.sh          # 68 assertions, changes nothing
```

Then start Hyprland (`start-hyprland` from a TTY, or pick it at the display
manager).

| Stage | sudo | Does |
|---|---|---|
| `10-omarchy4-packages` | **yes** | quickshell, uwsm, lua5.4, inotify-tools, QtQuick.Effects, fonts, VA-API, ffmpeg, pipewire-alsa, libxcb-cursor0 |
| `13-omarchy4-fonts` | no | upstream Symbols Nerd Font + Omarchy's own icon font |
| `11-omarchy4-deploy` | no | generates the Kali menu, patches the Omarchy checkout, installs/links config, adds bind descriptions, masks conflicting units, hides Kali tools from Apps |
| `12-omarchy4-verify` | no | asserts the whole setup; changes nothing |
| `14-omarchy4-extras` | part | Voxtype + its OSD (no root), LocalSend `.deb` (root) |
| `15-nvidia-offload` | **yes** | proprietary NVIDIA driver + CUDA, then **reboot** |
| `16-voxtype-gpu` | no | swaps voxtype to the Vulkan (or `--cuda`) build |

`11-omarchy4-deploy.sh` works on a **raw** box (it installs `hyprland.lua` when
none exists) and on an existing one (it patches in place, backing up first).
Re-run it any time — it is idempotent.

`13-omarchy4-fonts.sh` is deliberately separate because it downloads from the
internet; the deploy detects missing glyphs and points at it.

## Keymap

| Keys | Action |
|---|---|
| `SUPER+SPACE` | Omarchy menu |
| `SUPER+ALT+SPACE` | Apps |
| `SUPER+SHIFT+K` | Kali tools menu |
| `SUPER+CTRL+I` | Install Kali tools |
| `SUPER+K` | Keybindings menu |
| `SUPER+ESCAPE` | System menu |
| `SUPER+Q` | Terminal — qterminal (via `xdg-terminals.list`) |
| `SUPER+T` | Terminal — kitty |
| `SUPER+B` | Browser — Chromium (focuses an existing window) |
| `SUPER+C` / `SUPER+V` | Close window / toggle floating |
| `SUPER+L` | **Toggle workspace layout: dwindle ⇄ scrolling** |
| `SUPER+J` | Toggle split direction |
| `SUPER`+scroll | Resize focused window |
| `SUPER+SHIFT`+scroll | Resize vertically |
| `SUPER+ALT`+scroll | Previous / next workspace |
| `SUPER` + `-` / `=` | Resize width (±100) |
| `SUPER+SHIFT` + `-` / `=` | Resize height (±100) |
| `SUPER+ALT` + `-` / `=` | Resize a little (±25) |
| `SUPER+CTRL` + `-` / `=` | Resize a lot (±300) |
| `SUPER+CTRL+W` / `+B` / `+A` / `+P` | Wifi / Bluetooth / Audio / Power panel |

### Mouse move and resize

| Gesture | Effect |
|---|---|
| **Drag a window edge** | Resize — **no modifier** |
| `SUPER` + **left**-drag | **Move** the window |
| `SUPER` + **right**-drag | Resize |
| `SUPER+SHIFT` + **left**-drag | Resize |

The left/right split is Omarchy's own default and the usual tiling convention:
**left moves, right resizes**. Holding `SUPER` and dragging an edge with the
LEFT button gives you *move*, because that bind wins over border-resize — use
the right button, or `SUPER+SHIFT`+left, or drop `SUPER` entirely and just drag
the edge.

Two settings make this behave:

- `binds:drag_threshold = 10` — Hyprland defaults to **0**, meaning a click
  becomes a drag after zero pixels of movement, so `SUPER`+click grabbed the
  window into move mode the instant the button went down. 10px means a click
  stays a click.
- `general:resize_on_border = true` with `extend_border_grab_area = 15` —
  off by default in Hyprland and Omarchy, which is why grabbing an edge did
  nothing. Borders are 2px, so the 15px grab zone is what makes them catchable;
  `hover_icon_on_border` shows the resize cursor there.

All of it works on tiled *and* floating windows.

### Layout

```
10-omarchy4-packages.sh      apt packages (sudo)
11-omarchy4-deploy.sh        generate + patch + deploy config
12-omarchy4-verify.sh        68 assertions, changes nothing
13-omarchy4-fonts.sh         icon fonts (downloads)
14-omarchy4-extras.sh        Voxtype + OSD, LocalSend
15-nvidia-offload.sh         NVIDIA driver + CUDA (sudo, reboot)
16-voxtype-gpu.sh            voxtype Vulkan / CUDA build

lib/
  generate-kali-menu.py      builds the Kali menu from Kali's own metadata
  hide-kali-from-apps.py     Apps dedup (reversible)
  add-bind-descriptions.py   keeps binds visible in the keybindings menu
  retire-launchers.py        retires walker/appmenu binds when upgrading
  configure-qterminal.py     QTerminal paste shortcut
  menu-guard-bytes.py        guard-payload check used by verify
  audit-voxtype-menu.py      checks the Setup > Voxtype menu rows

config/
  omarchy/shell.json                  bar layout
  omarchy/kali-menu-extras.jsonc      hand-written menu rows
  omarchy/extensions/*.jsonc          GENERATED menu — do not edit
  omarchy/bar/scripts/                VPN + monitor-mode bar modules
  bin/kali-*-prompt                   interactive menu helpers
  bin/hypr-clipkey                    forced copy/paste re-emit helper
  hypr/hyprland.lua                   working Hyprland config
  hypr/omarchy4.lua                   all Omarchy wiring (one require to disable)
  kitty/kitty.conf                    ctrl+c = copy_or_interrupt
  systemd/hyprland-session.target     pulls up graphical-session.target
  systemd/voxtype.service.d/10-gpu.conf   pins voxtype's Vulkan device
  etc/chromium.d-vaapi                Chromium VA-API flags (install to /etc)

patches/                              applied to the Omarchy checkout by the deploy
docs/omarchy-4-architecture.md        how Omarchy 4 is put together
docs/voxtype-submap.conf.reference    inert hyprlang voxtype wrote; kept for reference
```

## Packages with non-obvious reasons

Most of the package list is self-explanatory. These are not, and each cost real
debugging time:

| Package | Without it |
|---|---|
| `lua5.4` | the keybindings menu **lists** binds but cannot **run** them |
| `pipewire-alsa` | voxtype records **pure silence** — ALSA `default` never reaches PipeWire (measured: `pw-record` peak 32767 vs `arecord -D default` peak 0) |
| `libxcb-cursor0` | Qt 6.5+ apps bundling their own Qt (AmneziaVPN) cannot load the `xcb` plugin and refuse to start |
| `ffmpeg` | voxtype has no audio conversion |
| `inotify-tools` | the shell's plugin watcher fails to start |
| `qml6-module-qtquick-effects` | the shell's image-picker plugin fails to load |
| `intel-media-va-driver`, `mesa-va-drivers` | no hardware video decode/encode |
| `fonts-nerd-symbols` | **not sufficient on its own** — see Icons |

`gum` is *not* installed and is optional: Omarchy's presentation-terminal
helpers use it for styling, so some menu actions look plainer than upstream
intends. `sudo apt install gum` if you want them as designed.

## Touchpad: scroll binds do NOT work — use gestures

`mouse_up` / `mouse_down` binds fire **only for a physical mouse wheel**.
Touchpad scrolling never reaches Hyprland's keybind system at all.

Verified two ways: a probe bound exclusively to `SUPER+CTRL`+scroll logged
nothing while two-finger scrolling (the probe script itself worked when called
directly), and upstream
[hyprwm/Hyprland discussion #12942](https://github.com/hyprwm/Hyprland/discussions/12942)
answers the request for generalised `scroll_*` binds by pointing at the gesture
system instead.

So the touchpad is handled by `hl.gesture()`, not `hl.bind()`:

```lua
hl.gesture({ fingers = 2, direction = "horizontal", action = "resize", mods = "SUPER" })
hl.gesture({ fingers = 2, direction = "vertical",   action = "resize", mods = "SUPER" })
hl.gesture({ fingers = 3, direction = "horizontal", action = "move",   mods = "SUPER" })
```

| Gesture | Action |
|---|---|
| `SUPER` + **two-finger** swipe | Resize the focused window |
| `SUPER` + **three-finger** swipe | Move the focused window |
| two-finger swipe (no modifier) | Normal scrolling, untouched |

`mods` is what keeps plain scrolling working — the gesture only engages while
SUPER is held. Hyprland refuses to register a gesture that would be shadowed by
an existing one, so re-running a duplicate is a safe no-op.

Two settings were also wrong and are fixed, which matter for an actual wheel:
`binds:scroll_event_delay` was 300 ms (now `0`) and
`input:emulate_discrete_scroll` was `1` (now `2`).

## Copy / paste — the honest version

Wayland has no X11-style global key grabber. A compositor bind fires **first**,
so binding `CTRL+C` there would take SIGINT away from every terminal on the
box. That is not done here.

| Context | Ctrl+C | Ctrl+V | Ctrl+Z |
|---|---|---|---|
| GUI apps | copy (native) | paste (native) | undo (native) |
| **kitty** | `copy_or_interrupt` — copies when there is a selection, SIGINT when there is not | paste | suspend (job control) |
| **qterminal** | SIGINT (unchanged) | paste | suspend |

`Ctrl+Shift+C` / `Ctrl+Shift+V` keep working in both terminals.

kitty is the one that gets true GUI-style behaviour, because it has a
`copy_or_interrupt` action. QTerminal's Copy shortcut is a single static
binding with no smart mode, so moving it to `Ctrl+C` would cost SIGINT
outright — `lib/configure-qterminal.py` therefore moves only Paste.

`config/bin/hypr-clipkey` remains available for a forced re-emit into the
focused window (`hypr-clipkey copy|paste|undo`); it is installed but not bound,
since `SUPER+C`/`SUPER+V` are close-window and toggle-floating.

## Patching the Omarchy checkout

Omarchy assumes Arch and its own defaults; several of those assumptions do not
hold here. Patches in `patches/` are applied to `~/.local/share/omarchy` by the
deploy, are idempotent, and report if upstream has fixed the issue.

- `0001-notifications-transient-reserved-word.patch` — Omarchy v4.0.3 targets
  Quickshell 0.3.1; Debian ships 0.3.0. `Service.qml` declares `var transient`,
  a reserved word in this Qt's QML grammar. The whole notifications service
  failed to load, so `notify-send` and every `omarchy-notification-send` call
  errored.
- `0002-centre-presentation-terminals-without-app-id.patch` — upstream centres
  privileged prompts by giving the terminal the app_id `org.omarchy.terminal`.
  QTerminal cannot set one, so the launcher asks Hyprland to float and centre
  the window at spawn time instead. See
  [The centred admin-password prompt](#the-centred-admin-password-prompt).
- `0003-screensaver-without-ttfx.patch` — Omarchy's screensaver needs `ttfx`
  (AUR, no Debian equivalent) and a terminal that can be handed a window class.
  Points the launcher at this repo's renderer and at a terminal that is
  installed. See [The screensaver](../README.md#the-screensaver).
- `0004-browser-retint-without-a-root-policy-writer.patch` — tinting the
  Chromium window frame to the theme colour means writing a managed policy
  under `/etc` as root, which upstream reaches through a packaged binary and a
  passwordless sudoers rule. A checkout has neither and this box's `sudo` asks
  for a password, so enabling it would put a password prompt inside every theme
  switch. The patch makes the script return before it sources anything, which
  is the same work it already did without the three errors it printed doing it.

**Re-apply after any Omarchy update** — just re-run the deploy.

## Extras: Voxtype and LocalSend

Neither is packaged for Kali/Debian, so `14-omarchy4-extras.sh` fetches both
from their official GitHub releases. Omarchy already expects both — its own
bindings guard on `cmd_present("voxtype")`, and the menu row
**Trigger → Share → Receive** calls `localsend`.

```bash
./14-omarchy4-extras.sh
```

Also on the menu: **Install → Utilities**, with a live ✓ once each is present.

| | |
|---|---|
| **Voxtype** `1.0.1` | Push-to-talk voice-to-text, ~18 MB, installs to `~/.local/bin` — no root |
| **LocalSend** `1.18.2` | LAN file sharing, 23.5 MB `.deb` — needs root |

> **Watch the source.** Voxtype is [peteonrails/voxtype](https://github.com/peteonrails/voxtype)
> (voxtype.io) — what Omarchy's `voxtype-bin` AUR package installs, and what its
> `voxtype record toggle` / `voxtype setup --download` bindings expect. There is an
> unrelated **atheerium/voxtype** on GitHub with the same name whose v0.1.1 is a
> stub: it answers `--version` and has no subcommands at all. Installing that one
> looks like success and does nothing. The script now refuses any build whose
> `--help` produces no usage output.
>
> Upstream also ships a `.deb`, but it is **346 MB** because it bundles models. We
> take the standalone binary (~18 MB) and let it fetch the model on first setup.
> The build is chosen from `/proc/cpuinfo` — `avx512` on this machine, `avx2`
> otherwise.

The script verifies each download before installing (runs `voxtype --version`,
runs `dpkg-deb --info` on the `.deb`). Without passwordless sudo it saves the
`.deb` to `~/Downloads` and prints the one command to finish.

### Setup → Voxtype

The whole branch is hidden unless voxtype is installed. Every action is a real
subcommand, checked against `voxtype --help` and each `setup <cmd> --help`:

| Row | Runs |
|---|---|
| Status | `voxtype status` |
| Configure | `voxtype configure` (TUI) |
| Check system | `voxtype setup check` |
| Select model | `voxtype setup model` |
| Download default model | `voxtype setup --download` |
| List installed models | `voxtype setup model --list` |
| Speech detection model | `voxtype setup vad` (Silero VAD) |
| GPU acceleration | `voxtype setup gpu` |
| Hyprland integration | `voxtype setup compositor hyprland` |
| Install as a service | `voxtype setup systemd` |

**Hyprland integration is worth running** — upstream describes it as fixing
modifier-key interference with the compositor.

`lib/audit-voxtype-menu.py` re-runs every guard and resolves every action's
binary using the same PATH the shell uses.

| Keys | Action |
|---|---|
| `SUPER+CTRL+X` | Toggle dictation |
| `F9` (hold) | Push-to-talk dictation |

Before first use, fetch the model (~150 MB) — **Install → Utilities → Voxtype:
download model**, or `voxtype setup --download`.

Two gotchas worth knowing:

- The binds call voxtype by **absolute path** and are guarded by a file test,
  not `command -v`. Hyprland parses the config with whatever PATH the session
  started with, and a TTY-launched session has no `~/.local/bin` — so a
  `command -v` guard silently skipped the binds.
- Voxtype's *own* global hotkey reads evdev, which needs `sudo usermod -aG
  input $USER` and a re-login. The Hyprland binds above work without it, so
  it is optional.

## GPU compute (NVIDIA)

This laptop is an Optimus hybrid: **Intel Iris Plus G7** drives eDP-1 and
renders Hyprland; the **GeForce MX350** (GP107M, Pascal, 2 GB GDDR5, 640 CUDA
cores) has no display outputs and exists purely for compute.

### Why nouveau is not enough

```
nouveau 0000:01:00.0: pmu: firmware unavailable
```

Without PMU firmware nouveau cannot manage the card's clocks — it is pinned to
boot clocks permanently. Mesa's NVK *does* support Pascal (since Mesa 25.1, and
`nouveau_icd.json` is present), but a GPU stuck at boot clocks is slower than
the CPU, which is why `voxtype info variants` reports `NVIDIA=false` and
recommends the AVX-512 CPU build.

The proprietary driver is the only way to get real clocks, Vulkan and CUDA.

```bash
sudo ./15-nvidia-offload.sh     # driver + CUDA, then REBOOT
./16-voxtype-gpu.sh             # give voxtype a GPU build
./16-voxtype-gpu.sh --cuda      # ...or the ONNX/CUDA build
```

`15-nvidia-offload.sh` preflights before touching anything: NVIDIA on the PCI
bus, **Secure Boot disabled** (an unsigned DKMS module would not load), and
headers matching the *running* kernel. It writes
`/etc/modprobe.d/nvidia-kali-hyprland.conf` with `nvidia-drm modeset=1` and
dynamic power management so the dGPU can idle down on battery.

**The desktop stays on Intel.** The MX350 drives no outputs, so Hyprland keeps
rendering on the iGPU — which sidesteps the usual Hyprland-on-NVIDIA problems
entirely. Verify after reboot with `hyprctl monitors` (eDP-1 on i915) and
`nvidia-smi`.

`16-voxtype-gpu.sh` keeps the CPU build as `voxtype-cpu` so the two can be
compared on the same audio.

### Rollback

```bash
sudo apt purge '^nvidia-.*' && sudo apt autoremove
sudo rm -f /etc/modprobe.d/nvidia-kali-hyprland.conf
sudo update-initramfs -u && sudo reboot
```

nouveau returns automatically. For voxtype:
`cp ~/.local/bin/voxtype-cpu ~/.local/bin/voxtype && systemctl --user restart voxtype`

### Voxtype daemon

It is a **systemd user service**, not a system one — installed by
`voxtype setup systemd` (or **Setup → Voxtype → Install as a service**), enabled
against `graphical-session.target`, so it starts on login.

```bash
systemctl --user status voxtype
voxtype info accel        # says whether the daemon is actually GPU-accelerated
```

## Which session to pick at the login screen

Two Hyprland entries, both real Wayland sessions:

| Entry | Exec | Use it? |
|---|---|---|
| **Hyprland (uwsm-managed)** | `uwsm start -e -D Hyprland hyprland.desktop` | **yes** |
| Hyprland | `/usr/bin/start-hyprland` | works, but see below |

**Pick the uwsm-managed one.** uwsm (Universal Wayland Session Manager) puts the
compositor inside a proper systemd user session, which means:

- `graphical-session.target` activates **natively**, so every user unit bound to
  it (voxtype, portals, the keyring) starts on its own — no workaround needed
- `uwsm stop` works, so Omarchy's own logout works
- the session tears down cleanly instead of leaving stray processes

Everything in this repo works under either, but the plain entry needs the
`hyprland-session.target` shim below to start user units at all.

> **A third entry used to exist and was broken.** The pre-Omarchy setup left
> `~/.local/share/xsessions/hyprland-wayland.desktop` — also called "Hyprland",
> but in **xsessions/**, the X11 directory. LightDM therefore started an X server
> and ran a Wayland compositor inside it, which comes up with **no keyboard or
> mouse input at all**. Removed. If you ever see a Hyprland entry that starts to
> a dead session, check it is not in `xsessions/`.

## The systemd user session

Hyprland is launched by hand from a TTY (`start-hyprland`), not by a session
manager — so **nothing activates `graphical-session.target`**, and every user
unit bound to it stays "enabled" while never running. That is why
`voxtype.service` looked installed but was permanently inactive.

`graphical-session.target` sets `RefuseManualStart=yes`, so it cannot simply be
started. `config/systemd/hyprland-session.target` is the standard workaround: it
`BindsTo` + `Before` graphical-session.target, so starting *it* pulls that one
up. `omarchy4.lua` imports the Wayland environment into systemd and starts it at
`hyprland.start`.

### The catch

Activating that target starts **everything** enabled against it — including the
stack Omarchy replaced. Two of those actively conflict:

| Unit | Why it must go |
|---|---|
| `waybar` | a second bar on the same edge |
| `hyprpolkitagent` | a **second polkit agent** racing `omarchy.polkit` |
| `mako` | a second notification daemon racing `omarchy.notifications` |
| `hyprpaper` | `omarchy.background` owns the wallpaper |
| `hypridle` | the shell has its own idle/lock plugins |

The deploy **masks** them. Disabling is not enough: their enable symlinks live in
root-owned `/etc/systemd/user/graphical-session.target.wants/`, which a user-level
`disable` cannot touch — but a user-level mask overrides them without sudo.
Undo with `systemctl --user unmask <unit>`.

## Qt apps that bundle their own Qt

AmneziaVPN ships its own Qt6 under `/usr/local/sbin` with **no wayland platform
plugin** — `Available platform plugins are: xcb`. It therefore has to run
through XWayland, and Qt 6.5+ needs `libxcb-cursor0` for that:

```
qt.qpa.plugin: Could not find the Qt platform plugin "wayland" in ""
qt.qpa.plugin: From 6.5.0, xcb-cursor0 or libxcb-cursor0 is needed ...
```

`libxcb-cursor0` is in the package stage. This affects any self-contained Qt app,
not just Amnezia.

## Configuring Voxtype

```bash
voxtype configure                  # interactive TUI
voxtype config schema              # every settable key, with its current value
voxtype config get <key>           # read one
voxtype config set <key> <value>   # write one
voxtype config unset <key>         # back to the built-in default
```

Config lives at `~/.config/voxtype/config.toml`. **Almost every key needs a
daemon restart** — `systemctl --user restart voxtype`.

Clicking the bar's **Dictate** indicator runs `omarchy-voxtype-config`, which
opens `voxtype configure` in a floating terminal.

### Keys that matter most

| Key | Values | Notes |
|---|---|---|
| `whisper.model` | `tiny` … `large-v3-turbo` | bigger = better + slower. `voxtype info models` lists them |
| `whisper.language` | `auto`, `en`, `ru`, … | or a comma-separated list to constrain auto-detect |
| `whisper.translate` | bool | **translates to English instead of transcribing verbatim** |
| `output.mode` | `type` \| `clipboard` \| `paste` \| `file` | `type` simulates keystrokes |
| `output.auto_submit` | bool | press Return after typing |
| `output.shift_enter_newlines` | bool | newlines as Shift+Enter so chat apps don't send early |
| `hotkey.enabled` | bool | **false here** — see below |
| `hotkey.key` / `hotkey.mode` | e.g. `SCROLLLOCK`, `toggle` \| `push_to_talk` | only used when `hotkey.enabled = true` |

### Which GPU and which model

Measured on this box — same 31.9 s file, three runs each:

| Device + model | Time | Notes |
|---|---|---|
| **NVIDIA MX350 + `small`** | **3.8 / 3.8 / 3.7 s** | ~8.4× realtime — **what is configured** |
| Intel Iris Plus + `small` | 9.5 / 11.9 / 9.5 s | 2.6× slower |
| Intel Iris Plus + `large-v3-turbo` | 20.7 s | best accuracy, 5.4× slower |
| NVIDIA MX350 + `large-v3-turbo` | **OOM** | 2 GB ceiling |

The MX350 wins by ~2.6× **despite reporting `fp16: 0`** while the Intel iGPU
reports `fp16: 1`. Whisper leans on fp16 and Pascal runs it at 1/64 rate, so the
capability flags suggest the opposite result — its core count more than makes up
for it. Don't infer performance from those flags; measure.

**The 2 GB VRAM ceiling is the real constraint.** `large-v3-turbo` (1.6 GB)
leaves too little for whisper's KV cache:

```
ggml_vulkan: Device memory allocation of size 31457280 failed
whisper_kv_cache_init: failed to allocate memory for the kv cache
ERROR Transcription failed: Failed to create a new whisper context
```

Recording still worked, so this failed **silently** — the only symptom was no
text ever appearing. Worth knowing if you change models.

| Model | Size | On the MX350 |
|---|---|---|
| `tiny` / `base` | 75 / 142 MB | easily |
| **`small`** | **466 MB** | comfortable — uses 468 MiB of 2048 |
| `medium` | ~1.5 GB | tight, expect the same OOM |
| `large-v3-turbo` | 1.6 GB | no — Intel only |

Two traps worth naming:

- **`.en` models are English-only.** With `whisper.language = ru`, `base.en`
  transcribes nothing useful. Multilingual models are the ones *without* the
  `.en` suffix.
- **"turbo" is not a size tier.** It exists only as `large-v3-turbo`, a
  distilled large-v3 — there is no `small-turbo`.

For maximum accuracy instead of speed, `large-v3-turbo` runs on the Intel device
(`uma: 1`, allocates from system RAM, no VRAM ceiling): set
`GGML_VK_VISIBLE_DEVICES=0` in `config/systemd/voxtype.service.d/10-gpu.conf`.

### The OSD (waveform + volume while dictating)

The floating panel is a **separate binary**. `osd.enabled` defaults to `true`,
so without it the daemon logs on every start:

```
WARN Failed to spawn `voxtype-osd`: No such file or directory (os error 2)
```

and dictation runs with no visual feedback at all. `14-omarchy4-extras.sh`
installs it — as `voxtype-osd`, which is the bare name the daemon spawns.

| Frontend | Size | Notes |
|---|---|---|
| `gtk4` *(installed)* | 3.8 MB | the shipped default; needs `libgtk-4-1` + `libgtk4-layer-shell0`, both present |
| `quickshell` | 3.5 MB | renders via quickshell and honours `osd.palette = omarchy` |
| `native` | 2.9 MB | fewest dependencies |

Switch with `VOXTYPE_OSD_FRONTEND=quickshell ./14-omarchy4-extras.sh` after
removing `~/.local/bin/voxtype-osd`, or just
`voxtype config set osd.frontend <name>` once the matching binary is in place.

Position and shape: `osd.position` (default `bottom-center`), `osd.layout`
(`compact` | `wide` | `minimal` | `tile` | `orb`).

> **The extras script refuses to downgrade voxtype.** It once overwrote the
> Vulkan GPU build with the CPU one, because `command -v voxtype` ran before
> `~/.local/bin` was added to PATH and so missed the existing install. PATH is
> now set first, and the script additionally refuses to replace a
> significantly larger binary with a smaller one.

### Why `hotkey.enabled = false`

Voxtype's built-in hotkey watches **evdev** directly, which requires membership
of the `input` group. This setup drives it from Hyprland binds instead
(`SUPER+CTRL+X`, `F9` → `voxtype record ...`), so the evdev watcher is redundant
— and without the group it logged
`Hotkey listener error: No keyboard device found in /dev/input/` on every start.
Upstream's guidance for this key is exactly that: *"Turn this off when your
compositor calls `voxtype record` instead."* The deploy sets it and touches
nothing else.

To use voxtype's own global hotkey instead (works outside Hyprland too):

```bash
sudo usermod -aG input $USER      # then log out and back in
voxtype config set hotkey.enabled true
systemctl --user restart voxtype
```

## The centred admin-password prompt

Omarchy's "password appears in the middle of the screen" is **not** polkit — it
is a window rule. Plain `sudo` never talks to polkit; it prompts on the
terminal's own stdin. What makes it look centred is that the terminal running
it is floated, centred and fixed-size:

```lua
o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })
o.window("(org.omarchy.terminal|org.omarchy.btop|…|Omarchy|TUI.float|…)", { tag = "+floating-window" })
```

Those live in Omarchy's `default/hypr/apps/system.lua`, which this setup does
not load — we require only `omarchy4.lua` — so they are reproduced there,
matching `org.omarchy.*`, `TUI.*`, the `Omarchy` window title, and
`xdg-desktop-portal-gtk` (file pickers and screen-share prompts are only ever
dialogs and should never tile).

### Why the class rules alone are not enough here

Those rules fire on the window's **app_id**, which upstream sets with
`xdg-terminal-exec --app-id=org.omarchy.terminal`. QTerminal cannot carry one.
Its entire command line is `-d -e -h -p -v -w` — no class, no app-id, no title —
and Qt hardcodes the application name, so even exec'ing it through a symlink
named `org.omarchy.terminal` still maps as class `qterminal` (measured). Left
alone, every privileged prompt tiles.

`patches/0002` therefore makes the launcher attach the rules at spawn time
instead:

```bash
hyprctl dispatch 'hl.dsp.exec_cmd("[float;center;size 875 600] uwsm-app -- xdg-terminal-exec …")'
```

which is terminal-agnostic. The association survives the `uwsm-app` handoff —
Hyprland walks the spawned process tree, so entering a systemd scope does not
break it — and lands in exactly the same geometry as the class-rule path:
`float=true`, 875×600 at `[523, 253]` on a 1920×1080 output, from either route.

If that dispatch is ever refused — a Lua API change after a Hyprland upgrade —
the launcher falls through to the upstream exec, so the prompt still appears,
just not centred.

The class rules stay in `omarchy4.lua` regardless. They cost nothing, they are
what catches `xdg-desktop-portal-gtk` and anything registered as `TUI.*`, and
they take over unchanged if the default terminal ever moves to one that can set
its own app_id — kitty is installed and accepts `--class`.

Every Kali menu row that needs root already routes through
`omarchy-launch-floating-terminal-with-presentation`, so they all inherit this.

### When you *do* want polkit's themed modal

`pkexec` rather than `sudo` — that is what reaches `omarchy.polkit` and draws
the shell's own dialog. It suits a GUI app that needs root; it is a poor fit for
the interactive prompts here, which read input and stream output in a terminal,
because pkexec runs with a scrubbed environment and no controlling terminal.

Note that `pkexec` only finds that agent from **inside** the graphical session.
polkit registers an agent per subject, and `omarchy.polkit` registers for the
seat0 Wayland session; run `pkexec` over SSH and it falls back to a textual
agent and dies with `Error opening current controlling terminal for the process
('/dev/tty')`. That is expected, not a broken agent.

## Power management

Settings live in four places, not one:

| What | Where | How |
|---|---|---|
| Screensaver + lock timers | `config/omarchy/shell.json` → `idle` | edit, then `omarchy-restart-shell` |
| Lid close, power button | systemd-logind | `/etc/logind.conf.d/*.conf` (root) |
| Suspend / hibernate / lock actions | Omarchy menu → **System** | `SUPER+ESCAPE` |
| Power profiles | `power-profiles-daemon` | **not installed** |

### The screen never locking — login-shell PATH

The Omarchy shell runs every spawned command as a **login** shell:

```qml
process.command = ["bash", "-lc", command]     // plugins/services/idle/Service.qml
```

A login bash reads `~/.profile`, **not** `~/.bashrc`, and Debian's default
profile rebuilds `PATH` from scratch — so omarchy's own `bin/` was absent and
every spawned `omarchy-*` command died instantly:

```
idle-monitor: idle
idle-cycle-start: screensaver=150 lock=300
process-start: lock omarchy-system-lock
process-exit:  lock exitCode=127          <- command not found
```

The idle timer was firing perfectly on schedule; the action it ran could not be
found. This affects far more than the lock — any menu row or service action
resolving an `omarchy-*` command **by name** goes through the same path.

The deploy appends the PATH export to `~/.profile` and then *verifies* a login
shell can resolve `omarchy-system-lock`, because this failure hides itself.

> **The screensaver** used to be a separate casualty here:
> `omarchy-launch-screensaver` required `ttfx`, an Arch/AUR package with no
> Debian equivalent, so it exited 1 by design. Patch 0003 points the launcher
> at `kali-screensaver` instead and lets it fall back to any installed terminal
> that accepts a window class (qterminal does not). The lock still fires
> independently of the screensaver, so locking works either way.

### Idle and lock timers

```json
"idle": { "screensaver": 150, "lock": 300 }
```

Seconds. Currently screensaver at 2m30, lock at 5m. `omarchy.power` in the bar
also exposes battery state and profiles.

### Current logind behaviour

```
HandleLidSwitch  suspend      HandlePowerKey  poweroff      IdleAction  ignore
```

`IdleAction=ignore` is correct — the Omarchy shell owns idle handling, so
logind should stay out of it. To change lid/power-button behaviour, drop a file
in `/etc/logind.conf.d/` rather than editing `logind.conf` directly.

### Hibernate — works, but Omarchy hid it

Omarchy gates the Hibernate row on `/etc/mkinitcpio.conf.d/omarchy_resume.conf`.
**mkinitcpio is Arch's initramfs generator**, so that file can never exist on
Debian and the row stayed hidden even though hibernate is fully supported here:

- swap: 18.6 G **partition** (`/dev/sda3`) > 15 GiB RAM
- `/sys/power/state` lists `disk`
- `/etc/initramfs-tools/conf.d/resume` has `RESUME=UUID=…`
- logind reports `CanHibernate=challenge` — supported, needs polkit auth

`kali-menu-extras.jsonc` overrides that row with the Debian equivalent, and adds
**Suspend, then hibernate** (sleeps now, hibernates later to save battery).

### Power profiles are unavailable

`power-profiles-daemon` is not installed, so the bar's power widget cannot
switch performance/balanced/power-saver:

```bash
sudo apt install -y power-profiles-daemon
```

## Architecture

Omarchy 3 was waybar + walker. **Omarchy 4 replaced both with one Quickshell
process**:

```
omarchy-launch-shell
  └── quickshell -n -p ~/.local/share/omarchy/shell
        └── plugins/  bar · menu · polkit · panels(network|audio|bluetooth|power) · lock · background
```

Supervised, logging to `journalctl -t omarchy-shell`.

Full write-up: [omarchy-4-architecture.md](omarchy-4-architecture.md).

## The Kali menu is generated

`config/omarchy/extensions/omarchy-menu.jsonc` is **generated — do not edit it**.

```bash
lib/generate-kali-menu.py && omarchy menu refresh
```

(Also on the menu: **Kali → Kali System → Regenerate this menu**.)

It is built from Kali's *own* metadata, so the tree is the real Kali taxonomy
and always matches what is installed:

| Source | Gives |
|---|---|
| `/etc/xdg/menus/applications-merged/kali-applications.menu` | the hierarchy |
| `/usr/share/desktop-directories/kali-*.directory` | category names |
| `/usr/share/applications/kali-*.desktop` | tools, `Categories`, `X-Kali-Package` |

Current run: **66 categories, ~956 rows** — Kali's MITRE ATT&CK chain
(Reconnaissance → Impact) plus Forensics and Services.

Hand-written rows with no `.desktop` equivalent live in
`config/omarchy/kali-menu-extras.jsonc` and are appended verbatim: Quick Actions
(four interactive prompts), Service Control (live ✓ state), Kali System, docs
links, and the `system.logout` override.

`install.kali` sits under Omarchy's Install menu: 39 Kali metapackages each with
a live ✓, plus any not-installed tool grouped by category.

### Two traps if you edit the generator

**1. Installation is resolved at generation time, never at runtime.**
`kali-menu` ships all ~506 desktop files whether or not the tool is installed,
so a guard really is needed — but Omarchy batches every visible row's
`when`/`checked` into a **single `bash -lc` script**, and a `dpkg-query` guard on
all 917 tool rows made that process fail to start and **the menu came up empty**.
The generator filters as it writes and emits no per-tool `when`.
`12-omarchy4-verify.sh` asserts the remaining guard payload stays small.

**2. Empty categories are pruned.** Kali declares categories no
`kali-*.desktop` claims; left in, they are dead ends.

## Arch-only menu rows

Omarchy assumes pacman/yay. **40 of its 275 action rows** reach an Arch-only
script — on Kali they open Omarchy's branded floating terminal (`--title=Omarchy`)
and then fail, which reads as *"Omarchy is offering me a pacman install that
cannot work"*.

They are not hand-listed. `lib/generate-kali-menu.py` computes them on every
run: it scans Omarchy's **own** `bin/` for scripts calling `pacman` or `yay`,
scans its default menu for rows invoking one, and re-emits each with

```json
"when": "omarchy-cmd-present pacman"
```

That predicate is false on Debian, so the rows disappear here — and the same
file stays correct on a real Arch box. Because it is derived rather than
hard-coded, it keeps working when Omarchy changes its menu.

Affected branches: `install/` (3), `remove/` (19), `setup/` (14, the
default-agent/browser/editor pickers), `update/` (4, release-channel switching).

### apt replacements

The two genuinely useful ones are replaced rather than just removed:

| Hidden (pacman) | Replacement |
|---|---|
| Install → Package | **Install → Package (apt)** — searches, then installs |
| Remove → Package | **Remove → Package (apt)** — shows what would go, then purges |
| — | **Update → System (apt)** — `apt update && full-upgrade` |

## Apps dedup

Kali ships a `kali-*.desktop` for nearly every tool, so Apps listed ~623 entries
and buried the ~126 ordinary applications.

```bash
lib/hide-kali-from-apps.py            # hide (497)
lib/hide-kali-from-apps.py --restore  # undo
lib/hide-kali-from-apps.py --status   # report
```

Per XDG, a desktop file in a higher-precedence directory replaces the lower one
by ID, so this writes `~/.local/share/applications/<id>` with `NoDisplay=true` —
nothing under `/usr` is touched. Files carry `X-KaliHyprland-Hidden=true` and the
script only ever modifies its own, so your own overrides are safe.

Apps went from **~623 to ~126**. GUI tools shipping their own desktop file
(Wireshark, Caido, CherryTree) correctly stay.

## Hyprland config — Lua only

**Never add a `hyprland.conf`.** Hyprland prefers `.conf` over `.lua` when both
exist, so a stray one silently shadows everything. The deploy moves any it finds
aside.

- `config/hypr/hyprland.lua` — the working config (installed if absent).
- `config/hypr/omarchy4.lua` — all Omarchy wiring, required from the bottom of
  the above. Comment out that one `require` to disable the whole integration.

### Two non-obvious details

**1. Every `hl.bind` carries a `description`.** Hyprland reports Lua binds with
the opaque dispatcher `__lua`, and `omarchy-menu-keybindings` contains:

```bash
[[ -z $description && $dispatcher == "__lua" ]] && continue
```

No description means the bind is **invisible** in the keybindings menu.
`lib/add-bind-descriptions.py` maintains them, merging into any existing opts
table rather than replacing it. It runs on every deploy and is idempotent.

**2. `package.path` is set before the require.** That same script re-scans
`hyprland.lua` with a **standalone `lua`** via `pcall(dofile, ...)` to recover
the real dispatcher. That interpreter does not know where `~/.config/hypr` is, so
a bare `require("omarchy4")` would fail, the pcall would abort, and **every** Lua
bind would lose its dispatcher. This is also why **`lua5.4` is a hard
dependency**, not a nicety.

## Icons

Debian's `fonts-nerd-symbols` is a `+dfsg1` repack whose charset stops at
`f533` with **zero codepoints above U+FFFF** — so the whole Material Design
block (U+F0001+) that Omarchy and the Kali menu use is missing, and every icon
renders as an empty box. Nothing in the Kali/Debian archive supplies it.

`13-omarchy4-fonts.sh` installs the official upstream Symbols Nerd Font into
`~/.local/share/fonts` (user scope, no root) and verifies the build actually
carries plane-15 glyphs *before* installing. It also registers Omarchy's own
`omarchy` icon font (the bar menu button draws `U+E900` from it), which upstream
registers from its Arch-only installer.

Undo: `rm -rf ~/.local/share/fonts/NerdFontsSymbols ~/.local/share/fonts/omarchy && fc-cache -f`

## Layout

```
10-omarchy4-packages.sh    apt packages (sudo)
13-omarchy4-fonts.sh       icon fonts
11-omarchy4-deploy.sh      generate + deploy config
12-omarchy4-verify.sh      68 assertions
lib/
  generate-kali-menu.py    builds the Kali menu from Kali's metadata
  hide-kali-from-apps.py   Apps dedup (reversible)
  add-bind-descriptions.py keeps binds visible in the keybindings menu
  retire-launchers.py      retires walker/appmenu binds when upgrading
  menu-guard-bytes.py      guard-payload check used by verify
config/
  omarchy/shell.json               bar layout
  omarchy/kali-menu-extras.jsonc   hand-written menu rows
  omarchy/extensions/…jsonc        GENERATED menu
  omarchy/bar/scripts/             VPN + monitor-mode bar modules
  bin/kali-*-prompt                interactive menu helpers
  hypr/hyprland.lua                working Hyprland config
  hypr/omarchy4.lua                Omarchy wiring
docs/omarchy-4-architecture.md     how Omarchy 4 is put together
skills/hermes/                     post-conversion management skills
```

## Notes for this box

- Hyprland is started by hand from a TTY (`start-hyprland`), so **uwsm does not
  manage the session**. Omarchy's own logout calls `uwsm stop` and does nothing
  here; `system.logout` is overridden to exit the compositor, same as `SUPER+M`.
  `uwsm-app` itself still works, so menu launches are fine.
- Terminal goes through `xdg-terminal-exec`, which reads
  `~/.config/xdg-terminals.list` — set to `qterminal.desktop`. Kali's default
  resolved to the GNOME Terminal *preferences dialog*, which is not a terminal.

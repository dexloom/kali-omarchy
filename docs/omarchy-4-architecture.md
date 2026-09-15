# Omarchy 4 architecture notes

Researched against **v4.0.3** (latest release, published 2026-09-08), branch `quattro`.

> The repo moved: `basecamp/omarchy` → **`omacom/omarchy`**. The old URL 301s.
> There is **no Omarchy 4.5** — the 4.x line is 4.0.0 … 4.0.3.

## The big change from Omarchy 3

Omarchy 3 was waybar + walker + a pile of shell scripts. **Omarchy 4 replaced
both with a single long-running Quickshell process**, `omarchy-shell`:

```
omarchy-launch-shell
  └── quickshell -n -p $OMARCHY_PATH/shell
        └── plugins/   ← bar, menu, polkit, panels, services
```

Neither `waybar`, `wofi`, `rofi` nor `walker` appear in `install/omarchy-base.packages`
any more. The single relevant runtime package is `quickshell`.

`omarchy-launch-shell` supervises the process: it relaunches on unclean exit,
gives up after 5 relaunches in 60s, and logs to the journal under the
`omarchy-shell` tag (`journalctl -t omarchy-shell`).

## Plugin layout

`shell/plugins/` is a real plugin system — each plugin is a directory with a
`manifest.json` declaring `id`, `kinds` and `entryPoints`:

| Plugin | Path | Kind | What it is |
|---|---|---|---|
| `omarchy.bar` | `plugins/bar/` | `bar` | The bar engine |
| `omarchy.menu` | `plugins/menu/` | `menu`, `bar-widget` | **Main menu** |
| `omarchy.polkit` | `plugins/polkit/` | `service` | **Root password modal** |
| `omarchy.network` | `plugins/panels/network/` | `bar-widget` | **Wifi panel** |
| `omarchy.audio` | `plugins/panels/audio/` | `bar-widget` | Volume + mixer |
| `omarchy.bluetooth` | `plugins/panels/bluetooth/` | `bar-widget` | Bluetooth |
| `omarchy.power` | `plugins/panels/power/` | `bar-widget` | Battery, profiles |
| `omarchy.clock` | `plugins/panels/clock/` | `bar-widget` | Clock + calendar |
| `omarchy.tray` | `plugins/bar/widgets/` | `bar-widget` | System tray |

Simple widgets carry sibling manifests (`widgets/Tray.manifest.json`); richer
popup plugins get their own directory.

## The four surfaces this project targets

### 1. Main menu — data-driven JSONC

The menu is **not** code. It is two JSONC files merged by id:

```
$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc   ← Omarchy's (368 lines)
~/.config/omarchy/extensions/omarchy-menu.jsonc    ← yours, merged on top
```

Parsed by `shell/plugins/menu/MenuModel.js`. Hierarchy is **inferred from
dotted ids** — `kali.recon.nmap` sits under `kali.recon`, which sits under
`kali`, which sits on the root menu. No registration step.

Per-item fields:

| Field | Meaning |
|---|---|
| `icon` | Nerd Font glyph |
| `label` | Row title |
| `action` | Shell command; **absent ⇒ the row is a submenu** |
| `target` | Jump to another submenu id (link/alias) |
| `provider` | Runtime JSON row provider |
| `aliases` | Extra `omarchy menu summon <name>` routes; also searchable |
| `when` | Shell condition — row hidden when it fails |
| `checked` | Shell condition — appends ✓ when it succeeds |

`stripJsonc()` only strips **whole-line** `//` comments (regex is anchored
`^\s*//`), so `https://` inside a string value is safe. Trailing commas are
stripped before `JSON.parse`.

Control it with: `omarchy menu toggle|summon|close|refresh [route]`, which is a
thin wrapper over `omarchy-shell shell <verb> omarchy.menu '{"menu":"<route>"}'`.

### 2. Keybindings menu

`bin/omarchy-menu-keybindings` — reads `hyprctl binds`, resolves XKB keycodes
via `xkbcli compile-keymap`, prioritises ~45 known actions into a fixed order,
caches the result under `$XDG_CACHE_HOME/omarchy/keybindings-<sha>.records`,
and renders it through `omarchy-menu-select`. Selecting a row **dispatches that
binding**, it does not merely display it.

It parses plain `hyprctl binds` rather than `-j` deliberately: *"Hyprland
0.56.0 emits invalid JSON for binds"*.

**Lua caveat.** Omarchy 4 configures Hyprland in Lua (`~/.config/hypr/hyprland.lua`,
`bindings.lua`), and Hyprland reports Lua binds with dispatcher `__lua`. The
script keeps a parallel Lua-sourced cache to recover the real dispatcher.
Debian's `hyprland` is a repacked `+ds` build whose Lua-provider support is
**unverified** — this project therefore uses classic hyprlang `.conf` syntax.

### 3. Root password modal

`shell/plugins/polkit/PolkitAgent.qml`, a `service`-kind plugin with
`keepLoaded: true`, built on `Quickshell.Services.Polkit`. It is a themed
Wayland-layer dialog, not a separate agent binary.

It handles fingerprint too: it greps the polkit PAM stack for `pam_fprintd.so`
and shows a sensor icon instead of a password field — falling back to the
password when the lid is shut (the reader is unreachable in clamshell).

**Consequence:** do not also run `polkit-gnome-authentication-agent-1` or
`hyprpolkitagent`. Two agents race for the same authority and you get a
dialog that dismisses itself.

### 4. Wifi

Two distinct surfaces:

- **Bar panel** `omarchy.network` (`plugins/panels/network/Panel.qml`) — scan,
  signal, connect, DNS provider selection. Summon with
  `omarchy-shell shell summon omarchy.network`.
- **Menu entries** under `setup.network` — DNS presets (`omarchy-dns DHCP|Cloudflare|Google|Custom`)
  and a QR-code row guarded by `when: [[ $(omarchy-network-status) == wifi* ]]`.

Backing scripts: `omarchy-network-status`, `omarchy-network-password`,
`omarchy-network-qr`, `omarchy-network-band`, `omarchy-restart-wifi`.

## Bar configuration

`~/.config/omarchy/shell.json`, key `bar`. **There is no deep merge** — once
that file exists it is canonical, so it must be complete.

Layout is three lists (`left`, `center`, `right`) of module objects.
`centerAnchor` pins one center module to true centre and flanks the others.

Third-party modules are first-class:

- `type: "command"` — runs an executable on an `interval`, printing plain text
  **or Waybar-style JSON** (`{"text":…,"tooltip":…,"class":…}`).
- `type: "qml"` — an `Item` with `implicitWidth`/`implicitHeight` from
  `~/.config/omarchy/bar/modules/<id>.qml`, receiving injected `bar`,
  `moduleName` and `settings`.

`bar` exposes `foreground`, `background`, `urgent`, `fontFamily`, `position`,
`vertical`, `barSize`, `run()`, `shellQuote()`, `showTooltip()`, `requestPopout()`.

## Portability to Debian/Kali

| Thing | Status |
|---|---|
| `hyprland` | ✅ Debian sid **0.56.2+ds-2** — matches what Omarchy 4 targets |
| `quickshell` | ✅ Debian sid **0.3.1-1** (trixie-backports 0.3.0) |
| `bin/` scripts | ✅ **408 of 444** are portable; only **36** call pacman/yay |
| `omarchy-cmd-present` | ✅ pure bash, no deps — safe for `when` guards |
| `install/` tree | ❌ Arch-only (pacstrap, pacman, yay) — **not used by this project** |
| AUR packages | ❌ `aether`, `herdr`, `omacalc`, `omacut`, `omawrite`, `tensaku`, `omarchy-nvim`, `cliamp`, `tobi-try` have no Debian equivalent. `ttfx` likewise — the screensaver that needed it is replaced by `kali-screensaver` (patch 0003) |
| `uwsm` | ⚠️ in Debian; `omarchy-launch-tui` needs it plus `xdg-terminal-exec` |
| Lua Hyprland config | ⚠️ unverified on Debian's `+ds` build |

Quickshell links against **private Qt APIs** and must be rebuilt against each
Qt release or it crashes on ABI mismatch. Using Debian's packaged quickshell
(built against Debian's Qt) avoids this; a hand-built one will break on the
next Qt upgrade.

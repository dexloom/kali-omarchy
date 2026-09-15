#!/usr/bin/env bash
# Step 10 — packages for the Omarchy 4 shell (requires sudo).
# Run: sudo ./10-omarchy4-packages.sh
#
# Omarchy 4 retired waybar + walker + elephant. The entire shell — bar, menu,
# polkit modal, wifi/audio/bluetooth panels — is ONE quickshell process.
# This installs what that shell needs. It does NOT remove the old stack;
# the snapshot in backups/pre-omarchy4-* is your way back.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Run: sudo $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

pkgs=(
    quickshell                    # THE Omarchy 4 shell runtime (bar/menu/polkit/panels)
    uwsm                          # universal wayland session manager; omarchy-launch-* use it
    lua5.4                        # REQUIRED by omarchy-menu-keybindings — see note below
    jq                            # omarchy-menu and friends parse JSON with it
    pamixer                       # omarchy audio scripts
    brightnessctl                 # omarchy brightness scripts
    alacritty                     # a Wayland terminal for xdg-terminal-exec to resolve
    qml6-module-qtquick-effects   # shell/plugins/image-picker needs QtQuick.Effects;
                                  # without it the shell logs "module not installed"
                                  # and that plugin fails to load
    fonts-nerd-symbols            # REQUIRED for icons — see note below
    fonts-jetbrains-mono          # the monospace family Omarchy is designed around
    fonts-font-awesome            # extra glyph coverage
    imagemagick                   # omarchy theming / capture helpers
    libnotify-bin                 # notify-send, used across omarchy bin/
    iw                            # wireless mode query, used by the Kali bar module
    libxcb-cursor0                # REQUIRED by Qt 6.5+ apps that fall back to the xcb
                                  # platform plugin. AmneziaVPN bundles its own Qt6
                                  # with no wayland plugin, so it must use xcb via
                                  # XWayland — and without this it dies with
                                  # "Could not load the Qt platform plugin xcb".
    ffmpeg                        # audio conversion for voxtype dictation; also the
                                  # usual transcode/screen-record workhorse
    alsa-utils                    # arecord, and ALSA plumbing voxtype falls back to
    pipewire-alsa                 # REQUIRED for voxtype to hear anything. It captures via
                                  # ALSA "default"; without this bridge that device goes
                                  # straight to raw hardware and records PURE SILENCE
                                  # (measured: pw-record peak 32767, arecord -D default
                                  # peak 0). Installs /etc/alsa/conf.d/99-pipewire-default.conf
    intel-media-va-driver         # VA-API hardware video decode/encode on the Iris Plus
    mesa-va-drivers               # VA-API for the Mesa side
    vainfo                        # verify VA-API with `vainfo`
    inotify-tools                 # the shell watches ~/.config/omarchy/plugins with
                                  # inotifywait; without it that watch fails to start
    # Already on this box; listed so the report below confirms them:
    hyprland
    xdg-terminal-exec
    network-manager
    grim
    slurp
    wtype
    wl-clipboard
    playerctl
)

# WHY lua5.4 IS NOT OPTIONAL:
# Hyprland reports binds defined in Lua with the opaque dispatcher `__lua`.
# omarchy-menu-keybindings recovers the real dispatcher by re-scanning
# ~/.config/hypr/hyprland.lua with a standalone `lua`, guarded by
# `omarchy-cmd-present lua || return 0`. With no lua on PATH that cache stays
# empty, every Lua bind ends up with an empty dispatcher, and selecting a row
# in the keybindings menu silently does nothing.

# WHY fonts-nerd-symbols IS NOT OPTIONAL:
# Every icon in the Omarchy bar and menu — and in our Kali menu — is a Nerd
# Font codepoint in the Private Use Area. Style.qml asks fontconfig for
# "monospace" and expects it to resolve to something carrying those glyphs.
# On a stock Kali box `fc-match monospace` gives DejaVu Sans Mono, which has
# none of them, so every icon renders as an empty box. fonts-nerd-symbols
# installs them as a fontconfig FALLBACK, so any monospace family picks them up.

apt-get update -qq
apt-get install -y -qq --no-install-recommends "${pkgs[@]}"

# omarchy-cmd-present looks for a command literally named `lua`. Debian ships
# the interpreter as /usr/bin/lua5.4 and does not reliably register the
# `lua` alternative, so provide the plain name if nothing else has.
if ! command -v lua >/dev/null 2>&1 && command -v lua5.4 >/dev/null 2>&1; then
    ln -sf "$(command -v lua5.4)" /usr/local/bin/lua
    echo "linked /usr/local/bin/lua -> $(command -v lua5.4)"
fi

echo
echo "OK — installed:"
for p in "${pkgs[@]}"; do
    printf '  %-28s %s\n' "$p" "$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null || echo MISSING)"
done

echo
echo "monospace resolves to: $(fc-match -f '%{family[0]}' monospace 2>/dev/null)"
echo "nerd symbol glyphs present: $(fc-list 2>/dev/null | grep -ci 'nerd\|symbols nerd')"
echo "lua resolves to: $(command -v lua || echo 'MISSING — keybindings menu will not dispatch')"
echo
echo "Next: $PROJECT/11-omarchy4-deploy.sh   (no sudo)"

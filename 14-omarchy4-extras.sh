#!/usr/bin/env bash
# Step 14 — Voxtype (voice dictation) and LocalSend (file sharing).
# Run: ./14-omarchy4-extras.sh
#
# Neither is in the Kali/Debian archive, so both come from their official
# GitHub releases. Voxtype is a user-space binary; LocalSend is a .deb and
# needs root — the script skips it cleanly if sudo is not available and tells
# you the one command to run.
#
# Omarchy already expects both:
#   voxtype   — default/hypr/bindings guard on `o.cmd_present("voxtype")`
#   localsend — the menu row Trigger > Share > Receive calls it
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOXTYPE_VERSION="${VOXTYPE_VERSION:-1.0.1}"
LOCALSEND_VERSION="${LOCALSEND_VERSION:-1.18.2}"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m \u2713\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m \u2717\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"

# Put ~/.local/bin on PATH BEFORE any `command -v` check below. Without this
# the checks miss an existing install and this script will happily overwrite a
# GPU build with the CPU one — which is exactly what happened once.
export PATH="$HOME/.local/bin:$PATH"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# ── Voxtype ───────────────────────────────────────────────────────────────
# NOTE ON THE SOURCE: this is peteonrails/voxtype (voxtype.io), which is what
# Omarchy's voxtype-bin AUR package installs and what its `voxtype record
# toggle` / `voxtype setup --download` bindings expect. There is an unrelated
# atheerium/voxtype on GitHub with the same name whose v0.1.1 is a stub: it
# answers --version and nothing else. Do not "fix" this URL to that one.
#
# Upstream also ships a .deb, but it is 346 MB because it bundles models. The
# standalone binary is 17 MB and fetches the model on first setup, so that is
# what we use — and it needs no root.
if command -v voxtype >/dev/null; then
    ok "voxtype already installed ($(voxtype --version 2>/dev/null | head -1))"
else
    # Pick the build matching this CPU: AVX-512 where available, else AVX2.
    if grep -qw avx512f /proc/cpuinfo; then
        variant="avx512"
    elif grep -qw avx2 /proc/cpuinfo; then
        variant="avx2"
    else
        die "CPU has neither AVX2 nor AVX-512; no suitable voxtype build"
    fi

    asset="voxtype-${VOXTYPE_VERSION}-linux-x86_64-${variant}"
    url="https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/${asset}"
    say "Voxtype $VOXTYPE_VERSION ($variant build)"
    curl -fsSL --retry 3 --max-time 300 -o "$tmp/voxtype" "$url" || die "download failed: $url"
    ok "fetched $(du -h "$tmp/voxtype" | cut -f1)"

    chmod +x "$tmp/voxtype"
    # Prove it is a real CLI before installing — the stub mentioned above
    # answers --version but has no subcommands at all.
    "$tmp/voxtype" --version >/dev/null 2>&1 || die "downloaded binary does not run"
    "$tmp/voxtype" --help 2>&1 | grep -qiE "usage|command" \
        || die "downloaded binary has no usage output — wrong project? refusing to install"

    # The GPU builds are much larger than the CPU one. If something bigger is
    # already installed, this script is about to downgrade it — refuse.
    if [[ -f $HOME/.local/bin/voxtype ]]; then
        have=$(stat -c%s "$HOME/.local/bin/voxtype")
        want=$(stat -c%s "$tmp/voxtype")
        if (( have > want + 1000000 )); then
            warn "a larger voxtype is already installed ($((have/1024/1024)) MB vs $((want/1024/1024)) MB)"
            warn "refusing to overwrite it — that would downgrade a GPU build to the CPU one"
            warn "  force with: rm ~/.local/bin/voxtype && $0"
            skip_voxtype=1
        fi
    fi

    if [[ ${skip_voxtype:-0} != 1 ]]; then
        mkdir -p "$HOME/.local/bin"
        install -m755 "$tmp/voxtype" "$HOME/.local/bin/voxtype"
        ok "installed ~/.local/bin/voxtype ($("$HOME/.local/bin/voxtype" --version 2>/dev/null | head -1))"
    fi
fi

export PATH="$HOME/.local/bin:$PATH"

# Runtime bits voxtype uses to type and to capture audio.
for c in wtype wl-copy notify-send; do
    command -v "$c" >/dev/null || warn "$c missing — voxtype uses it (apt install wtype wl-clipboard libnotify-bin)"
done
command -v ffmpeg >/dev/null || warn "ffmpeg missing — needed for audio conversion (apt install ffmpeg)"

# Hotkeys are read from evdev, which needs group access to /dev/input/*.
if ! id -nG | tr ' ' '\n' | grep -qx input; then
    warn "not in the 'input' group — voxtype's own global hotkey needs it:"
    warn "    sudo usermod -aG input $USER   (then log out and back in)"
    warn "  the Hyprland binds work regardless, so this is optional"
fi

# ── Voxtype OSD ───────────────────────────────────────────────────────────
# The floating waveform/volume panel is a SEPARATE binary. voxtype ships
# osd.enabled = true by default, so without it the daemon logs on every start:
#   WARN Failed to spawn `voxtype-osd`: No such file or directory (os error 2)
# and dictation runs with no visual feedback at all.
#
# The daemon spawns it by the bare name `voxtype-osd`, so that is what it must
# be installed as, whichever frontend you pick.
#
# Frontends (set with `voxtype config set osd.frontend <name>`):
#   gtk4       — the shipped default; needs libgtk-4-1 + libgtk4-layer-shell0
#   quickshell — renders through quickshell and honours osd.palette=omarchy
#   native     — smallest, fewest dependencies
VOXTYPE_OSD_FRONTEND="${VOXTYPE_OSD_FRONTEND:-gtk4}"

if [[ -x $HOME/.local/bin/voxtype-osd ]]; then
    ok "voxtype-osd already installed"
elif command -v voxtype >/dev/null || [[ -x $HOME/.local/bin/voxtype ]]; then
    case "$VOXTYPE_OSD_FRONTEND" in
        gtk4)       osd_asset="voxtype-${VOXTYPE_VERSION}-linux-x86_64-osd-gtk4" ;;
        quickshell) osd_asset="voxtype-${VOXTYPE_VERSION}-linux-x86_64-osd-quickshell" ;;
        native)     osd_asset="voxtype-${VOXTYPE_VERSION}-linux-x86_64-osd" ;;
        *) die "unknown OSD frontend: $VOXTYPE_OSD_FRONTEND (gtk4|quickshell|native)" ;;
    esac

    say "Voxtype OSD ($VOXTYPE_OSD_FRONTEND)"
    osd_url="https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/${osd_asset}"
    curl -fsSL --retry 3 --max-time 300 -o "$tmp/voxtype-osd" "$osd_url" || die "download failed: $osd_url"
    chmod +x "$tmp/voxtype-osd"
    ok "fetched $(du -h "$tmp/voxtype-osd" | cut -f1)"

    # gtk4 needs its toolkit at runtime; warn rather than install a broken OSD.
    if [[ $VOXTYPE_OSD_FRONTEND == gtk4 ]]; then
        for lib in libgtk-4-1 libgtk4-layer-shell0; do
            dpkg-query -W -f='${Status}' "$lib" 2>/dev/null | grep -q "ok installed" \
                || warn "$lib missing — the gtk4 OSD will not render (apt install $lib)"
        done
    fi

    mkdir -p "$HOME/.local/bin"
    install -m755 "$tmp/voxtype-osd" "$HOME/.local/bin/voxtype-osd"
    ok "installed ~/.local/bin/voxtype-osd"

    "$HOME/.local/bin/voxtype" config set osd.frontend "$VOXTYPE_OSD_FRONTEND" >/dev/null 2>&1 || true
    systemctl --user restart voxtype.service 2>/dev/null || true
fi

# ── LocalSend ─────────────────────────────────────────────────────────────
if command -v localsend >/dev/null || command -v localsend_app >/dev/null; then
    ok "localsend already installed"
else
    deb="LocalSend-${LOCALSEND_VERSION}-linux-x86-64.deb"
    url="https://github.com/localsend/localsend/releases/download/v${LOCALSEND_VERSION}/${deb}"
    say "LocalSend $LOCALSEND_VERSION"
    curl -fsSL --retry 3 --max-time 300 -o "$tmp/$deb" "$url" || die "download failed: $url"
    ok "fetched $(du -h "$tmp/$deb" | cut -f1)"

    # Sanity-check the package before offering it to dpkg.
    dpkg-deb --info "$tmp/$deb" >/dev/null 2>&1 || die "downloaded file is not a valid .deb"

    if sudo -n true 2>/dev/null; then
        say "installing (passwordless sudo available)"
        sudo apt-get install -y "$tmp/$deb"
        ok "localsend installed"
    else
        keep="$HOME/Downloads/$deb"
        mkdir -p "$HOME/Downloads"
        cp "$tmp/$deb" "$keep"
        warn "sudo needs a password, so the .deb was NOT installed."
        warn "It is saved at: ${keep/#$HOME/\~}"
        warn "Install it with:"
        warn "    sudo apt install $keep"
    fi
fi

echo
say "Done."
cat <<'NEXT'

Voxtype:
  SUPER+CTRL+X    toggle dictation
  F9 (hold)       push-to-talk
  First run downloads a Whisper model (~150 MB):  voxtype setup --download

LocalSend:
  Omarchy menu -> Trigger -> Share -> Receive
  or: omarchy menu summon trigger.share

NEXT

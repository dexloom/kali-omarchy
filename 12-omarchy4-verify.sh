#!/usr/bin/env bash
# Step 12 — verify the Omarchy 4 setup (NO sudo, changes nothing).
# Run: ./12-omarchy4-verify.sh
#
# Safe to run outside a Hyprland session; checks needing a live compositor are
# reported as SKIP rather than failing.
set -uo pipefail

# Derive the project root from this script, so the repo works wherever it
# is cloned rather than only at one fixed path.
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY="$HOME/.local/share/omarchy"
pass=0 fail=0 skip=0

P() { printf '\033[1;32m PASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
F() { printf '\033[1;31m FAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
S() { printf '\033[1;33m SKIP\033[0m %s\n' "$*"; skip=$((skip+1)); }
H() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }

H "Omarchy source"
if [[ -d $OMARCHY/shell ]]; then
    P "omarchy present ($(git -C "$OMARCHY" describe --tags 2>/dev/null || echo '?'))"
else
    F "omarchy missing at $OMARCHY"
fi
for f in bin/omarchy-menu bin/omarchy-menu-keybindings bin/omarchy-launch-shell \
         bin/omarchy-cmd-present shell/shell.qml default/omarchy/omarchy-menu.jsonc \
         shell/plugins/polkit/PolkitAgent.qml shell/plugins/panels/network/Panel.qml; do
    [[ -e $OMARCHY/$f ]] && P "$f" || F "$f missing"
done

H "Packages"
for c in quickshell hyprland jq; do
    command -v "$c" >/dev/null && P "$c ($(command -v $c))" || F "$c not on PATH"
done
# lua is what lets the keybindings menu DISPATCH a Lua bind, not merely list it.
if command -v lua >/dev/null; then
    P "lua ($(command -v lua))"
else
    F "lua missing — keybindings menu will list binds but cannot run them"
fi

H "Config links"
check_link() {
    local dest="$1" want="$2"
    if [[ -L $dest && "$(readlink "$dest")" == "$want" ]]; then
        P "${dest/#$HOME/\~}"
    elif [[ -e $dest ]]; then
        F "${dest/#$HOME/\~} exists but is not our symlink"
    else
        F "${dest/#$HOME/\~} missing"
    fi
}
check_link "$HOME/.config/omarchy/shell.json"                    "$PROJECT/config/omarchy/shell.json"
check_link "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" "$PROJECT/config/omarchy/extensions/omarchy-menu.jsonc"
check_link "$HOME/.config/omarchy/bar/scripts"                   "$PROJECT/config/omarchy/bar/scripts"
check_link "$HOME/.config/hypr/omarchy4.lua"                     "$PROJECT/config/hypr/omarchy4.lua"

H "Config wiring"
# Everything shipped under config/ must be installed by a numbered script.
# Anything shipped and never installed is documentation pretending to be
# configuration: it reads as supported, and silently is not.

# omarchy4.lua runs `systemctl --user start hyprland-session.target` on every
# session start. Without the unit that command fails silently and every unit
# bound to graphical-session.target stays enabled but never runs.
if grep -q "hyprland-session.target" "$PROJECT/config/hypr/omarchy4.lua" 2>/dev/null; then
    if [[ -e $HOME/.config/systemd/user/hyprland-session.target ]]; then
        P "hyprland-session.target installed (omarchy4.lua starts it)"
    else
        F "omarchy4.lua starts hyprland-session.target but the unit is not installed"
    fi
fi

# The voxtype GPU pin is a template: a fixed device index would send another
# machine's transcription to the wrong GPU. Catch a half-applied install.
dropin="$HOME/.config/systemd/user/voxtype.service.d/10-gpu.conf"
if [[ -f $dropin ]]; then
    # Anchor to the directive. The comment above it still names the placeholder
    # on purpose — that is how a reader learns to change the device — so a bare
    # grep for @@VK_DEVICE@@ matches a correctly installed file.
    if grep -qE '^Environment=GGML_VK_VISIBLE_DEVICES=[0-9]+$' "$dropin"; then
        # Same anchor for the REPORTED value: the template also carries a
        # commented-out `Environment=...=0` example for the integrated GPU, and
        # an unanchored grep picks that up and reports the wrong device.
        P "voxtype GPU pin: device $(sed -n 's/^Environment=GGML_VK_VISIBLE_DEVICES=\([0-9]*\)$/\1/p' "$dropin")"
    else
        F "voxtype GPU pin not substituted — re-run 16-voxtype-gpu.sh --pin-device N"
    fi
elif command -v voxtype >/dev/null 2>&1; then
    S "voxtype installed but no GPU pin (ggml will take device 0)"
fi

# Chromium flags only survive in /etc/chromium.d/ — see the file's own header.
if command -v chromium >/dev/null 2>&1; then
    if [[ -f /etc/chromium.d/vaapi ]]; then
        P "chromium VA-API flags installed"
    else
        F "chromium present but /etc/chromium.d/vaapi missing — re-run 10-omarchy4-packages.sh"
    fi
fi

H "Kali menu"
# Validate against the MERGED menu (Omarchy's default + our extension), not the
# extension alone. A row may legitimately parent onto a submenu that only
# exists in the default — install.gaming, setup.default.agent and friends — so
# checking our file in isolation reports false orphans for every one of them.
if out=$(OMARCHY_PATH="$OMARCHY" python3 "$PROJECT/lib/menu-orphans.py" 2>&1); then
    while IFS= read -r line; do
        [[ $line == OK* ]] && P "${line#OK }"
    done <<<"$out"
else
    while IFS= read -r line; do
        case "$line" in
            OK*)   P "${line#OK }" ;;
            FAIL*) F "${line#FAIL }" ;;
            *)     F "$line" ;;
        esac
    done <<<"$out"
fi

H "Generated Kali menu"
gen="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if grep -q "GENERATED FILE" "$gen" 2>/dev/null; then
    P "menu is generated from Kali's own metadata"
else
    F "menu is not the generated file — run lib/generate-kali-menu.py"
fi
# Omarchy batches every visible row's when/checked into ONE bash -lc script.
# Guarding all 917 tools with dpkg-query made that process fail to start and
# the menu came up empty, so installation is resolved at generation time.
guardbytes=$(python3 "$PROJECT/lib/menu-guard-bytes.py" "$gen" 2>/dev/null)
if [[ -n ${guardbytes:-} ]] && (( guardbytes < 200000 )); then
    P "runtime guard payload ${guardbytes} bytes (safe to batch)"
else
    F "runtime guard payload ${guardbytes:-unknown} — the menu may fail to populate"
fi
if grep -q '"install.kali"' "$gen" 2>/dev/null; then
    P "install.kali branch present (Kali metapackages installable from the menu)"
else
    F "install.kali branch missing"
fi

H "Arch-only menu rows"
# Omarchy assumes pacman/yay. Any row reaching those opens its branded floating
# terminal and then fails, which looks like "Omarchy is offering me a pacman
# install that cannot work". The generator guards them on
# `omarchy-cmd-present pacman`, false here.
gen="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
guarded=$(grep -c '"when":"omarchy-cmd-present pacman"' "$gen" 2>/dev/null || echo 0)
if (( guarded > 0 )); then
    P "$guarded Arch-only rows guarded out"
else
    F "no Arch-only rows guarded — pacman rows may be visible (re-run lib/generate-kali-menu.py)"
fi
if command -v pacman >/dev/null 2>&1; then
    warn_pacman=1
    P "pacman present (guards would allow those rows — unexpected on Kali)"
else
    P "pacman absent, so those rows stay hidden"
fi
# And the apt replacements must be there instead.
if grep -q '"install.apt"' "$gen" 2>/dev/null && grep -q '"remove.apt"' "$gen" 2>/dev/null; then
    P "apt install/remove rows present"
else
    F "apt replacement rows missing"
fi

H "Apps dedup"
hidden=$(grep -l "X-KaliHyprland-Hidden=true" "$HOME/.local/share/applications"/kali-*.desktop 2>/dev/null | wc -l)
sys=$(ls /usr/share/applications/kali-*.desktop 2>/dev/null | wc -l)
if (( hidden > 0 && hidden >= sys )); then
    P "$hidden of $sys Kali entries hidden from Apps"
elif (( hidden > 0 )); then
    F "only $hidden of $sys Kali entries hidden — re-run lib/hide-kali-from-apps.py"
else
    F "Kali entries not hidden from Apps ($sys would flood the launcher)"
fi

H "Bar modules"
for m in kali-vpn-status kali-iface-status; do
    script="$HOME/.config/omarchy/bar/scripts/$m"
    if [[ ! -x $script ]]; then
        F "$m not executable"
        continue
    fi
    out="$("$script" 2>/dev/null)"
    # Validate with python3, not jq: jq is installed by step 10, and this
    # verifier has to be able to tell you what is wrong BEFORE that runs.
    if printf '%s' "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        P "$m emits valid JSON: $out"
    else
        F "$m emitted non-JSON: $out"
    fi
done

H "Fonts and Qt modules"
# Every bar/menu icon is a Nerd Font codepoint in the Private Use Area.
# Style.qml asks fontconfig for "monospace"; on stock Kali that is DejaVu Sans
# Mono, which has none of them, so icons render as empty boxes.
mono=$(fc-match -f "%{family[0]}" monospace 2>/dev/null)
# Debian's fonts-nerd-symbols is a +dfsg1 repack whose charset stops at f533
# and has ZERO codepoints above U+FFFF. The Material Design block that Omarchy
# and our Kali menu use lives at U+F0001+, so presence of "a nerd font" is not
# enough — probe an actual plane-15 codepoint.
if fc-list ":charset=F099E" family 2>/dev/null | grep -q .; then
    P "plane-15 glyphs resolve (monospace = $mono)"
else
    F "U+F099E does not resolve — Material Design icons will be empty boxes (run 13-omarchy4-fonts.sh)"
fi
# The bar menu button draws U+E900 with fontFamily "omarchy", a font Omarchy
# ships but its (Arch-only) installer registers. We register it ourselves.
if [[ "$(fc-match -f '%{family[0]}' omarchy 2>/dev/null)" == "omarchy" ]]; then
    P "omarchy icon font registered (menu button glyph)"
else
    F "family 'omarchy' missing — the bar menu button renders as tofu (run 13-omarchy4-fonts.sh)"
fi
# QtQuick.Effects is imported by shell/plugins/image-picker.
if [[ -d /usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick/Effects ]]; then
    P "QtQuick.Effects present"
else
    F "QtQuick.Effects missing (install qml6-module-qtquick-effects)"
fi

H "Terminal"
# Omarchy launches terminals through xdg-terminal-exec, which reads
# ~/.config/xdg-terminals.list. Without it Kali resolves to the GNOME Terminal
# PREFERENCES dialog, which is not a terminal at all.
term=$(xdg-terminal-exec --print-id 2>/dev/null | cut -d: -f1)
case "$term" in
    qterminal.desktop) P "default terminal: qterminal" ;;
    "")                F "xdg-terminal-exec resolves to nothing" ;;
    *)                 F "default terminal is '$term' (expected qterminal.desktop)" ;;
esac

# QTerminal cannot set a Wayland app_id, so Omarchy's class rules for
# org.omarchy.terminal never match it and privileged prompts would tile instead
# of appearing centred. patches/0002 makes the launcher attach the float rules
# at spawn time instead; without it the prompt still works, just not centred.
launcher="$OMARCHY/bin/omarchy-launch-floating-terminal-with-presentation"
if [[ ! -f $launcher ]]; then
    F "floating presentation launcher missing"
elif grep -q 'float;center;size' "$launcher"; then
    P "privileged prompts centre (patches/0002 applied)"
else
    F "patches/0002 not applied — privileged prompts will tile, not centre"
fi

H "Kali menu helpers"
for h in kali-scan-prompt kali-searchsploit-prompt kali-airodump-prompt kali-metapackage-prompt; do
    if [[ -x $HOME/.local/bin/$h ]] && bash -n "$HOME/.local/bin/$h" 2>/dev/null; then
        P "$h"
    else
        F "$h missing or has a syntax error"
    fi
done

H "Hyprland config"
main="$HOME/.config/hypr/hyprland.lua"
grep -q 'require("omarchy4")'   "$main" && P "hyprland.lua requires omarchy4" || F "require missing"
grep -q 'package.path'          "$main" && P "package.path set (keybindings scan needs it)" || F "package.path missing"
if grep -qE '^\s*hl\.exec_cmd\("waybar"\)' "$main"; then
    F "waybar autostart still live — you would get two bars"
else
    P "waybar autostart retired"
fi
if grep -E '^\s*hl\.bind' "$main" | grep -qiE 'walker|appmenu'; then
    F "old launcher binds still live — they fight the Omarchy menu for SUPER+SPACE"
else
    P "old launcher binds retired"
fi
# The Lua-only project rule.
if [[ -e $HOME/.config/hypr/hyprland.conf ]]; then
    F "hyprland.conf exists — Hyprland prefers .conf and would shadow hyprland.lua"
else
    P "Lua-only rule holds (no hyprland.conf)"
fi

H "Lua-only rule"
# Hyprland prefers hyprland.conf over hyprland.lua when both exist, so a stray
# .conf silently shadows the whole config.
if [[ -e $HOME/.config/hypr/hyprland.conf ]]; then
    F "hyprland.conf exists — it SHADOWS hyprland.lua"
else
    P "no hyprland.conf"
fi
# Tools that "integrate with Hyprland" tend to drop hyprlang snippets into
# conf.d/. Nothing sources that directory here, so anything in it is inert and
# usually a sign a tool wrote config the project cannot use — `voxtype setup
# compositor hyprland` did exactly this.
if [[ -d $HOME/.config/hypr/conf.d ]] && [[ -n "$(ls -A "$HOME/.config/hypr/conf.d" 2>/dev/null)" ]]; then
    F "~/.config/hypr/conf.d has files but nothing sources it — inert hyprlang: $(ls -A "$HOME/.config/hypr/conf.d" | tr '\n' ' ')"
else
    P "no inert conf.d snippets"
fi

H "Keybindings menu"
# Reproduce omarchy-menu-keybindings' own Lua scan: it is the only thing that
# can recover a dispatcher from Hyprland's opaque `__lua` binds, and a bind it
# cannot see is a bind the menu cannot run.
if command -v lua >/dev/null; then
    scan=$(awk "/^    lua <<.LUA.\$/,/^LUA\$/" "$OMARCHY/bin/omarchy-menu-keybindings" | sed "1d;\$d")
    found=$(printf '%s' "$scan" | lua - 2>/dev/null | wc -l)
    live=$(grep -cE '^\s*(local\s+\w+\s*=\s*)?hl\.bind\(' "$HOME/.config/hypr/hyprland.lua")
    if (( found > 0 )); then
        P "bind scan recovers $found binds (from $live hl.bind statements; loops expand)"
    else
        F "bind scan recovered nothing — the keybindings menu would be empty"
    fi
    nodesc=$(grep -cE '^\s*(local\s+\w+\s*=\s*)?hl\.bind\(' "$HOME/.config/hypr/hyprland.lua")
    withdesc=$(grep -cE '^\s*(local\s+\w+\s*=\s*)?hl\.bind\(.*description' "$HOME/.config/hypr/hyprland.lua")
    if (( withdesc == nodesc )); then
        P "all $nodesc hl.bind statements carry a description"
    else
        F "$((nodesc - withdesc)) bind(s) lack a description — they will be invisible in the keybindings menu"
    fi
else
    S "lua missing — cannot test the keybindings scan"
fi

H "Lock screen"
# The lock refuses to engage without a PAM stack — `omarchy-shell lock lock`
# answers "missing-pam" and returns success, so the idle timer appears to work
# while nothing locks.
if [[ -f /etc/pam.d/omarchy-lock-password ]]; then
    P "lock PAM stack present"
    # A stack referencing something absent is worse than none: it would lock
    # you out. Check every @include resolves.
    missing=""
    while read -r inc; do
        [[ -f /etc/pam.d/$inc ]] || missing="$missing $inc"
    done < <(grep -oP '^@include\s+\K\S+' /etc/pam.d/omarchy-lock-password 2>/dev/null)
    if [[ -n $missing ]]; then
        F "lock PAM references missing stack(s):$missing — you could be locked out"
    else
        P "every @include in the lock PAM stack resolves"
    fi
    # Ignore comments: the file explains WHY it avoids system-local-login, and
    # matching that prose reported a correct file as broken.
    if grep -vE '^\s*#' /etc/pam.d/omarchy-lock-password 2>/dev/null | grep -q "system-local-login"; then
        F "lock PAM references system-local-login (Arch-only; absent on Debian)"
    else
        P "no Arch-only PAM stack referenced"
    fi
else
    F "/etc/pam.d/omarchy-lock-password missing — the screen will never lock (run 17-lock-pam.sh)"
fi

H "Live session"
# Resolve the live compositor ourselves rather than trusting the caller's env.
# Hyprland leaves an instance directory behind for every session that has run,
# so $XDG_RUNTIME_DIR/hypr can hold several and only one is alive — picking the
# wrong one (or having no HYPRLAND_INSTANCE_SIGNATURE at all) made this whole
# section skip even while Hyprland was plainly running.
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || ! hyprctl version >/dev/null 2>&1; then
    for _d in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/; do
        [[ -d $_d ]] || continue
        _sig=$(basename "$_d")
        if HYPRLAND_INSTANCE_SIGNATURE="$_sig" hyprctl version >/dev/null 2>&1; then
            export HYPRLAND_INSTANCE_SIGNATURE="$_sig"
            break
        fi
    done
fi

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
    P "Hyprland is running"
    n=$(hyprctl binds 2>/dev/null | grep -c '^bind')
    P "hyprctl reports $n binds"
    pgrep -f 'quickshell.*omarchy' >/dev/null \
        && P "omarchy shell process is up" \
        || F "omarchy shell not running (journalctl -t omarchy-shell -n 50)"
else
    S "not inside a Hyprland session — bind and shell checks deferred"
fi

printf '\n\033[1m%d passed, %d failed, %d skipped\033[0m\n' "$pass" "$fail" "$skip"
(( fail == 0 ))

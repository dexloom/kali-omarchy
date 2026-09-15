#!/usr/bin/env bash
# Step 11 — deploy the Omarchy 4 configuration (NO sudo).
# Run: ./11-omarchy4-deploy.sh
#
# Safe to re-run. Every file it overwrites is backed up to <file>.bak-<ts>
# first, matching the convention 02-setup-config.sh established.
set -euo pipefail

# Derive the project root from this script, so the repo works wherever it
# is cloned rather than only at one fixed path.
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY="$HOME/.local/share/omarchy"
TS="$(date +%Y%m%d-%H%M%S)"
backups=()

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

backup() {
    local f="$1"
    [[ -e $f && ! -L $f ]] || return 0
    cp -a "$f" "$f.bak-$TS"
    backups+=("$f.bak-$TS")
    warn "backed up $f -> $f.bak-$TS"
}

# Symlink into the project so `git pull` updates the live config.
link() {
    local src="$1" dest="$2"
    [[ -e $src ]] || die "missing source: $src"
    mkdir -p "$(dirname "$dest")"
    if [[ -L $dest && "$(readlink "$dest")" == "$src" ]]; then
        ok "already linked: ${dest/#$HOME/\~}"
        return 0
    fi
    backup "$dest"
    rm -rf "$dest"
    ln -s "$src" "$dest"
    ok "linked ${dest/#$HOME/\~} -> ${src/#$HOME/\~}"
}

[[ -d $OMARCHY/shell ]] || die "Omarchy not found at $OMARCHY — run 10-omarchy4-packages.sh, then the clone step."

say "Omarchy 4 deploy ($(git -C "$OMARCHY" describe --tags 2>/dev/null || echo unknown))"

# ── 0. Regenerate the Kali menu for THIS machine ──────────────────────────
# The menu is generated from Kali's own metadata and reflects which tools are
# installed, so it must be built here rather than shipped from whatever box
# last committed it.
if [[ -x $PROJECT/lib/generate-kali-menu.py ]] && [[ -f /etc/xdg/menus/applications-merged/kali-applications.menu ]]; then
    say "Generating the Kali menu"
    python3 "$PROJECT/lib/generate-kali-menu.py" 2>&1 | sed "s/^/  /"
else
    warn "skipping menu generation (generator or kali-menu metadata missing)"
    warn "the menu extension is a generated file and is not shipped — the link"
    warn "step below will stop the deploy if it was never built"
fi

# ── 0b. Patch the Omarchy checkout ────────────────────────────────────────
# Omarchy 4.0.3 targets a newer Quickshell than Debian ships, and one QML file
# does not parse against Debian's build. Each patch explains itself; they are
# applied to the checkout, so they must be re-applied after an Omarchy update.
if [[ -d $PROJECT/patches ]] && [[ -d $OMARCHY ]]; then
    say "Patching the Omarchy checkout"
    for patch in "$PROJECT"/patches/*.patch; do
        [[ -f $patch ]] || continue
        name=$(basename "$patch")
        if patch -d "$OMARCHY" -p1 --forward --silent --dry-run <"$patch" >/dev/null 2>&1; then
            patch -d "$OMARCHY" -p1 --forward --silent <"$patch" && ok "applied $name"
        elif patch -d "$OMARCHY" -p1 --reverse --silent --dry-run <"$patch" >/dev/null 2>&1; then
            ok "already applied: $name"
        else
            warn "does not apply cleanly (upstream may have fixed it): $name"
        fi
    done
fi

# ── 1. Shell config: bar layout, Kali menu, bar modules ────────────────────
# NOTE: Omarchy does NOT deep-merge shell.json. Once this file exists it is
# canonical, so our copy must be complete — it is.
link "$PROJECT/config/omarchy/shell.json"                       "$HOME/.config/omarchy/shell.json"
link "$PROJECT/config/omarchy/extensions/omarchy-menu.jsonc"    "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
link "$PROJECT/config/omarchy/bar/scripts"                      "$HOME/.config/omarchy/bar/scripts"

# ── 2. Kali menu helper prompts onto PATH ─────────────────────────────────
mkdir -p "$HOME/.local/bin"
for helper in "$PROJECT"/config/bin/*; do
    [[ -f $helper ]] || continue
    link "$helper" "$HOME/.local/bin/$(basename "$helper")"
done

# kitty gets ctrl+c = copy_or_interrupt, which is how you get GUI-style
# copy/paste in a terminal WITHOUT losing SIGINT. See the file for why the
# compositor is the wrong place to do this.
link "$PROJECT/config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"

# ── 2b. PATH for LOGIN shells ─────────────────────────────────────────────
# The Omarchy shell spawns every command as `bash -lc` (see the idle service:
#   process.command = ["bash", "-lc", command]
# ). A LOGIN bash reads ~/.profile, not ~/.bashrc, and Debian's default profile
# rebuilds PATH from scratch — so omarchy's own bin directory was absent and
# every spawned omarchy-* command died with exit 127. That is why the screen
# never locked: the idle timer fired correctly and then
#   process-exit: lock exitCode=127
#
# It affects far more than the lock — any menu row or service action that
# resolves an omarchy-* command by name goes through the same path.
profile="$HOME/.profile"
path_line='export PATH="$HOME/.local/share/omarchy/bin:$HOME/.local/bin:$PATH"'
if [[ -f $profile ]] && grep -Fqs "share/omarchy/bin" "$profile"; then
    ok "login-shell PATH already configured in ~/.profile"
else
    say "adding omarchy bin to ~/.profile (login shells)"
    backup "$profile"
    printf '\n# kali-hyprland: the Omarchy shell runs commands via `bash -lc`,\n# which reads THIS file rather than ~/.bashrc.\n%s\n' "$path_line" >> "$profile"
    ok "login-shell PATH configured"
fi

# The interactive shell here is zsh, which does NOT read ~/.profile — it reads
# ~/.zshrc / ~/.zprofile. Without this, typing `omarchy-restart-shell` in a
# terminal fails with "command not found" even though the compositor and its
# spawned bash -lc processes resolve it fine.
for zfile in "$HOME/.zshrc" "$HOME/.zprofile"; do
    [[ -f $zfile ]] || continue
    if grep -Fqs "share/omarchy/bin" "$zfile"; then
        ok "omarchy bin already on PATH in $(basename "$zfile")"
    else
        backup "$zfile"
        printf '\n# kali-hyprland: zsh does not read ~/.profile\n%s\n' "$path_line" >> "$zfile"
        ok "added omarchy bin to $(basename "$zfile")"
    fi
done

# Verify it actually took, since this is the failure that hides itself.
if bash -lc 'command -v omarchy-system-lock' >/dev/null 2>&1; then
    ok "a login shell can now resolve omarchy commands"
else
    warn "a login shell still cannot find omarchy-system-lock — lock/idle actions will fail with 127"
fi

# ── 3. Hyprland overlay ───────────────────────────────────────────────────
link "$PROJECT/config/hypr/omarchy4.lua" "$HOME/.config/hypr/omarchy4.lua"

main="$HOME/.config/hypr/hyprland.lua"

# On a raw Kali there is no user hyprland.lua yet — only the package template
# at /usr/share/hypr/hyprland.lua. Install ours so the whole flow works from a
# clean machine, not just on a box that already had one.
if [[ ! -f $main ]]; then
    say "no user hyprland.lua — installing the project config"
    mkdir -p "$(dirname "$main")"
    cp "$PROJECT/config/hypr/hyprland.lua" "$main"
    ok "installed ${main/#$HOME/\~}"
fi

# The Lua-only rule: Hyprland prefers .conf over .lua when both exist, so a
# stray .conf would silently shadow everything above.
if [[ -e $HOME/.config/hypr/hyprland.conf ]]; then
    shadowed="$HOME/.config/hypr/hyprland.conf.shadowed-$TS"
    warn "moving hyprland.conf aside — it would shadow hyprland.lua"
    mv "$HOME/.config/hypr/hyprland.conf" "$shadowed"
    backups+=("$shadowed")
fi

if grep -q 'require("omarchy4")' "$main"; then
    ok "hyprland.lua already requires omarchy4"
else
    backup "$main"

    # Retire the waybar autostart: Omarchy 4 draws its own bar, and leaving
    # waybar running gives you two bars stacked on the same edge.
    if grep -q 'hl.exec_cmd("waybar")' "$main"; then
        sed -i 's|^\(\s*\)hl\.exec_cmd("waybar")|\1-- hl.exec_cmd("waybar")  -- retired by Omarchy 4 (its shell draws the bar)|' "$main"
        ok "commented out the waybar autostart"
    fi

    # Retire the walker / appmenu launcher binds. The Omarchy menu takes
    # SUPER+SPACE, and leaving the old binds live means two launchers fight
    # over the same key. Runs regardless of whether waybar was autostarted.
    if [[ -x $PROJECT/lib/retire-launchers.py ]]; then
        python3 "$PROJECT/lib/retire-launchers.py" | sed "s/^/    /"
    fi

    # package.path matters beyond Hyprland: omarchy-menu-keybindings scans the
    # config with a PLAIN `lua` via pcall(dofile, ...). Without this line that
    # require fails, the pcall aborts, and every Lua bind loses its dispatcher
    # — the keybindings menu would list binds it cannot actually run.
    cat >> "$main" <<'LUA'

-- ── Omarchy 4 ──────────────────────────────────────────────────────────────
-- Set package.path explicitly: Hyprland resolves this require on its own, but
-- omarchy-menu-keybindings also dofile()s this config with a standalone lua,
-- and that interpreter has no idea where ~/.config/hypr is.
package.path = os.getenv("HOME") .. "/.config/hypr/?.lua;" .. package.path
require("omarchy4")
LUA
    ok "hyprland.lua now requires omarchy4"
fi

# ── 3b. Bind descriptions ─────────────────────────────────────────────────
# Hyprland reports Lua binds with the opaque dispatcher `__lua`, and
# omarchy-menu-keybindings drops any `__lua` bind that carries no description:
#     [[ -z $description && $dispatcher == "__lua" ]] && continue
# Without this pass the keybindings menu shows the Omarchy binds and NONE of
# the window-management or media keys. Idempotent.
if [[ -f $PROJECT/lib/add-bind-descriptions.py ]]; then
    say "Bind descriptions"
    python3 "$PROJECT/lib/add-bind-descriptions.py" 2>&1 | sed "s/^/  /"
fi

# ── 3b2. Terminal shortcuts ───────────────────────────────────────────────
# Paste onto Ctrl+V in QTerminal. Copy deliberately stays on Ctrl+Shift+C:
# QTerminal has no "copy if there is a selection, else SIGINT" action, so
# moving Copy to Ctrl+C would cost SIGINT. kitty does have that action and is
# configured for it in config/kitty/kitty.conf.
if [[ -x $PROJECT/lib/configure-qterminal.py ]] && [[ -f $HOME/.config/qterminal.org/qterminal.ini ]]; then
    say "QTerminal shortcuts"
    python3 "$PROJECT/lib/configure-qterminal.py" 2>&1 | sed "s/^/  /"
fi

# ── 3b3. Retire user units that fight the Omarchy shell ───────────────────
# These ship enabled via /etc/systemd/user/graphical-session.target.wants/, so
# they start the moment that target activates. Two of them are not merely
# redundant, they actively conflict:
#   waybar          — a second bar on the same edge
#   hyprpolkitagent — a SECOND polkit agent racing omarchy.polkit; the dialog
#                     can dismiss itself
#   mako            — a second notification daemon racing omarchy.notifications
#   hyprpaper       — omarchy.background owns the wallpaper
#   hypridle        — the shell has its own idle/lock plugins
#
# Masked rather than disabled: the enable symlinks live under /etc (root-owned)
# so a user-level `disable` cannot remove them, but a user-level mask overrides
# them without sudo. Undo any time with `systemctl --user unmask <unit>`.
if command -v systemctl >/dev/null; then
    say "Retiring conflicting user units"
    masked=0
    for unit in waybar hyprpolkitagent mako hyprpaper hypridle; do
        state=$(systemctl --user is-enabled "$unit.service" 2>/dev/null || true)
        [[ $state == masked ]] && continue
        if systemctl --user list-unit-files "$unit.service" &>/dev/null; then
            systemctl --user stop "$unit.service" 2>/dev/null || true
            systemctl --user mask "$unit.service" >/dev/null 2>&1 && masked=$((masked+1))
        fi
    done
    if (( masked > 0 )); then
        systemctl --user daemon-reload 2>/dev/null || true
        ok "masked $masked conflicting unit(s)"
    else
        ok "conflicting units already masked"
    fi
fi

# ── 3b4. Voxtype: let the compositor own the hotkey ───────────────────────
# voxtype's built-in hotkey watches evdev directly, which needs membership of
# the `input` group. We drive it from Hyprland binds instead (SUPER+CTRL+X and
# F9 -> `voxtype record ...`), so the evdev watcher is redundant and, without
# the group, logs "No keyboard device found in /dev/input/" on every start.
# Upstream's own guidance for this key: "Turn this off when your compositor
# calls `voxtype record` instead."
#
# Only this one key is touched — language, model and output settings stay yours.
if command -v voxtype >/dev/null 2>&1 || [[ -x $HOME/.local/bin/voxtype ]]; then
    vox="${HOME}/.local/bin/voxtype"
    command -v voxtype >/dev/null 2>&1 && vox=voxtype
    if [[ "$("$vox" config get hotkey.enabled 2>/dev/null | tr -d '[:space:]')" != *false* ]]; then
        say "Voxtype: disabling the evdev hotkey (compositor binds drive it)"
        "$vox" config set hotkey.enabled false >/dev/null 2>&1 \
            && ok "hotkey.enabled = false" \
            || warn "could not set hotkey.enabled"
        systemctl --user restart voxtype.service 2>/dev/null || true
    else
        ok "voxtype hotkey already delegated to the compositor"
    fi
fi

# ── 3b5. Session hygiene under uwsm ───────────────────────────────────────
# uwsm runs XDG autostart entries; a TTY launch did not. Two consequences the
# moment the session moved to uwsm:
#
#  * /etc/xdg/autostart/polkit-mate-authentication-agent-1.desktop carries
#    NotShowIn=GNOME;KDE; so it DOES start under Hyprland, and it takes the
#    polkit registration first:
#      quickshell.service.polkit.listener: failed to register listener:
#        An authentication agent already exists for the given subject
#    which silently disables Omarchy's own themed root-password modal.
#    A user-level entry of the same name with Hidden=true overrides it.
#
#  * the portal units can start before WAYLAND_DISPLAY/DISPLAY reach the
#    systemd user manager, so xdg-desktop-portal-gtk dies with a bare
#    "cannot open display:" and the core portal then times out waiting for it,
#    leaving file pickers and screen sharing broken. A drop-in orders it after
#    graphical-session.target and restarts it if it still loses the race.
if [[ -f $PROJECT/config/autostart/polkit-mate-authentication-agent-1.desktop ]]; then
    link "$PROJECT/config/autostart/polkit-mate-authentication-agent-1.desktop" \
         "$HOME/.config/autostart/polkit-mate-authentication-agent-1.desktop"
fi
if [[ -f $PROJECT/config/systemd/xdg-desktop-portal-gtk.service.d/10-wait-for-session.conf ]]; then
    link "$PROJECT/config/systemd/xdg-desktop-portal-gtk.service.d/10-wait-for-session.conf" \
         "$HOME/.config/systemd/user/xdg-desktop-portal-gtk.service.d/10-wait-for-session.conf"
    systemctl --user daemon-reload 2>/dev/null || true
fi

# config/hypr/omarchy4.lua runs `systemctl --user start hyprland-session.target`
# on every session start, so the unit has to exist or that command fails
# silently and every unit bound to graphical-session.target — voxtype among
# them — stays enabled but never runs. It is inert under uwsm, which activates
# graphical-session.target itself; it only does work on the hand-started TTY
# path, which is exactly the path that needs it.
if [[ -f $PROJECT/config/systemd/hyprland-session.target ]]; then
    link "$PROJECT/config/systemd/hyprland-session.target" \
         "$HOME/.config/systemd/user/hyprland-session.target"
    systemctl --user daemon-reload 2>/dev/null || true
fi

# ── 3c. Hide Kali tools from the Apps launcher ────────────────────────────
# Kali ships a kali-*.desktop for nearly every tool, which buries the ordinary
# applications in Apps. The generated Kali menu already lists them all.
# Reverse any time with: lib/hide-kali-from-apps.py --restore
if [[ -x $PROJECT/lib/hide-kali-from-apps.py ]]; then
    say "Apps dedup"
    python3 "$PROJECT/lib/hide-kali-from-apps.py" 2>&1 | sed "s/^/  /"
    command -v update-desktop-database >/dev/null && \
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# ── 3d. Fonts ─────────────────────────────────────────────────────────────
# Not run automatically: 13-omarchy4-fonts.sh downloads from the internet.
# Check and point at it, because without those glyphs every icon is a box.
if ! fc-list ":charset=F099E" family 2>/dev/null | grep -q .; then
    warn "Material Design glyphs missing — every menu and bar icon will be an empty box"
    warn "  fix: $PROJECT/13-omarchy4-fonts.sh"
elif [[ "$(fc-match -f '%{family[0]}' omarchy 2>/dev/null)" != "omarchy" ]]; then
    warn "Omarchy icon font not registered — the bar menu button will be tofu"
    warn "  fix: $PROJECT/13-omarchy4-fonts.sh"
else
    ok "icon fonts present"
fi

# ── 4. Report ─────────────────────────────────────────────────────────────
echo
say "Deployed."
if (( ${#backups[@]} )); then
    echo "Backups written:"
    printf '  %s\n' "${backups[@]}"
fi
cat <<NEXT

Next:
  $PROJECT/13-omarchy4-fonts.sh      icon fonts (downloads ~2.3 MB)
  $PROJECT/12-omarchy4-verify.sh     check everything resolves
  hyprctl reload                     (from inside a Hyprland session)

In the session:
  SUPER+SPACE      Omarchy menu
  SUPER+SHIFT+K    Kali tools menu
  SUPER+K          Keybindings
  SUPER+CTRL+W     Wifi
NEXT

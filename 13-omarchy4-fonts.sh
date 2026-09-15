#!/usr/bin/env bash
# Step 13 — install the upstream Symbols Nerd Font (NO sudo).
# Run: ./13-omarchy4-fonts.sh
#
# WHY THIS EXISTS
# ---------------
# Debian ships fonts-nerd-symbols as a +dfsg1 repack. Its charset stops at
# f400-f533 and contains ZERO codepoints above U+FFFF, so the entire Material
# Design Icons block (U+F0001–U+F1AF0, plane 15) is missing. Omarchy's menu and
# bar lean on that block heavily:
#
#   Omarchy default menu : 131 of 333 icons (39%) unrenderable
#   Kali menu (ours)     :  91 of  91 icons (100%) unrenderable
#
# Nothing in the Kali/Debian archive supplies those glyphs, so we fetch the
# official upstream build. Everything lands in ~/.local/share/fonts — user
# scope only, no root, no system files touched. Remove with:
#
#   rm -rf ~/.local/share/fonts/NerdFontsSymbols && fc-cache -f
set -euo pipefail

VERSION="${NERD_FONTS_VERSION:-v3.5.1}"
ASSET="NerdFontsSymbolsOnly.tar.xz"
URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${VERSION}/${ASSET}"
DEST="$HOME/.local/share/fonts/NerdFontsSymbols"
# A glyph from the Material Design block; the whole point of this install.
PROBE_CP="F099E"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required"
command -v fc-cache >/dev/null || die "fontconfig is required"

say "Symbols Nerd Font ${VERSION}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "downloading ${ASSET}"
curl -fsSL --retry 3 --max-time 180 -o "$tmp/$ASSET" "$URL" \
    || die "download failed: $URL"
ok "fetched $(du -h "$tmp/$ASSET" | cut -f1)"

say "extracting"
mkdir -p "$tmp/x"
tar -xJf "$tmp/$ASSET" -C "$tmp/x" || die "extract failed"

# Verify BEFORE installing that this build actually carries the plane-15
# glyphs — installing a font with the same gap would fix nothing.
font=$(find "$tmp/x" -name "SymbolsNerdFontMono-Regular.ttf" -o -name "*Mono*.ttf" | head -1)
[[ -n $font ]] || die "no Mono ttf found in the archive"

if command -v fc-query >/dev/null; then
    high=$(fc-query --format="%{charset}\n" "$font" 2>/dev/null \
           | tr ' ' '\n' | grep -cE "^f[0-9a-f]{4}" || true)
    if (( high > 0 )); then
        ok "upstream font carries $high plane-15 ranges (Debian's carries 0)"
    else
        die "this build has no plane-15 glyphs either — aborting, nothing would improve"
    fi
fi

say "installing to ${DEST/#$HOME/\~}"
rm -rf "$DEST"
mkdir -p "$DEST"
find "$tmp/x" -name '*.ttf' -exec cp {} "$DEST/" \;
ok "installed $(find "$DEST" -name '*.ttf' | wc -l) font file(s)"

say "rebuilding font cache"
fc-cache -f "$DEST" >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1
ok "cache rebuilt"

# ── Omarchy's own icon font ───────────────────────────────────────────────
# The bar's menu button renders "\ue900" with fontFamily "omarchy" — a font
# Omarchy ships at default/fonts/omarchy/omarchy.ttf. Upstream's installer puts
# it on the system; we skip that installer (it is pacman/yay driven), so the
# button renders as tofu until this font is registered with fontconfig.
OMARCHY_TTF="${OMARCHY_PATH:-$HOME/.local/share/omarchy}/default/fonts/omarchy/omarchy.ttf"
if [[ -f $OMARCHY_TTF ]]; then
    say "installing Omarchy icon font"
    mkdir -p "$HOME/.local/share/fonts/omarchy"
    cp -f "$OMARCHY_TTF" "$HOME/.local/share/fonts/omarchy/"
    # Rebuild the whole user font cache, not just this subdirectory: a
    # per-directory fc-cache does not always land before the next query.
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1
    # Ask fontconfig to resolve the family, which is what Qt will do.
    if [[ "$(fc-match -f '%{family[0]}' omarchy 2>/dev/null)" == "omarchy" ]]; then
        ok "family 'omarchy' registered (menu button glyph U+E900)"
    else
        warn "omarchy font did not register — the menu button may stay blank"
    fi
else
    warn "omarchy.ttf not found at $OMARCHY_TTF — is the checkout complete?"
fi

# Prove the glyph resolves now.
resolved=$(fc-list ":charset=$PROBE_CP" family 2>/dev/null | head -1)
if [[ -n $resolved ]]; then
    ok "U+$PROBE_CP now resolves to: $resolved"
else
    warn "U+$PROBE_CP still does not resolve — icons may remain blank"
fi

echo
say "Done. Restart the shell to pick the font up:"
echo "  OMARCHY_PATH=~/.local/share/omarchy ~/.local/share/omarchy/bin/omarchy-restart-shell"

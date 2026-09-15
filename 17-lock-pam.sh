#!/usr/bin/env bash
# Step 17 — PAM config for the Omarchy lock screen (requires sudo).
# Run: sudo ./17-lock-pam.sh
#
# THE SYMPTOM: the screen never locks. The idle timer fires correctly and
# omarchy-system-lock exits 0, but nothing happens. Asking the plugin directly
# shows why:
#     $ omarchy-shell lock lock
#     missing-pam
# The lock refuses to engage without a PAM stack — it will not put up a lock
# screen it cannot authenticate you against. That is correct behaviour, not a
# bug; it is refusing to lock you out of your own machine.
#
# WHY NOT JUST RUN OMARCHY'S OWN omarchy-apply-lock:
# It writes `account include system-local-login`. system-local-login is an ARCH
# PAM stack and does not exist on Debian/Kali — the resulting file would be
# broken, and a broken auth stack on a lock screen means you cannot get back in.
# Debian's equivalents are common-auth and common-account, which is exactly what
# Debian's own hyprlock PAM file uses (@include common-auth).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Run: sudo $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
PAM_PASSWORD=/etc/pam.d/omarchy-lock-password
PAM_FINGERPRINT=/etc/pam.d/omarchy-lock-fingerprint

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

# Refuse to write a stack that references something absent — that is the
# failure mode that locks you out.
for stack in common-auth common-account; do
    [[ -f /etc/pam.d/$stack ]] || die "/etc/pam.d/$stack is missing; this does not look like a Debian PAM setup"
done
ok "Debian PAM stacks present (common-auth, common-account)"

say "Writing $PAM_PASSWORD"
[[ -f $PAM_PASSWORD ]] && cp -a "$PAM_PASSWORD" "$PAM_PASSWORD.bak-$(date +%Y%m%d-%H%M%S)"
tee "$PAM_PASSWORD" >/dev/null <<'EOF'
# kali-hyprland: PAM stack for the Omarchy Quickshell lock screen.
#
# Debian equivalent of what omarchy-apply-lock writes on Arch. Upstream ends
# with `account include system-local-login`, an Arch-only stack; on Debian the
# equivalents are common-auth / common-account. This mirrors Debian's own
# hyprlock PAM file rather than inventing a stack.
@include common-auth
@include common-account
EOF
chmod 644 "$PAM_PASSWORD"
ok "wrote $PAM_PASSWORD"

# Fingerprint only when a reader is actually enrolled, otherwise the lock can
# sit waiting on a sensor that does not exist.
if [[ -x /usr/bin/fprintd-list ]] && \
   /usr/bin/fprintd-list "$REAL_USER" 2>/dev/null | grep -qi finger; then
    say "Enrolled fingerprint found — writing $PAM_FINGERPRINT"
    tee "$PAM_FINGERPRINT" >/dev/null <<'EOF'
auth       required    pam_fprintd.so
@include common-account
EOF
    chmod 644 "$PAM_FINGERPRINT"
    ok "wrote $PAM_FINGERPRINT"
else
    rm -f "$PAM_FINGERPRINT"
    ok "no enrolled fingerprint — password-only (fingerprint stack removed)"
fi

echo
say "Done. Restart the shell so the lock plugin picks it up:"
cat <<'NEXT'
    OMARCHY_PATH=~/.local/share/omarchy ~/.local/share/omarchy/bin/omarchy-restart-shell

Then confirm it no longer reports missing-pam:
    omarchy-shell lock lock      # should lock; your password unlocks it

RECOVERY, if the lock ever refuses your password: switch to a TTY with
Ctrl+Alt+F2, log in, and run
    pkill -f 'quickshell.*omarchy'
which drops the lock surface with the session still running.
NEXT

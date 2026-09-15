#!/usr/bin/env python3
"""Hide Kali's 497 tool entries from the Omarchy Apps launcher.

WHY: Kali ships a kali-*.desktop for nearly every tool. Omarchy's Apps
launcher enumerates XDG desktop entries, so those 497 rows bury the ~150
ordinary applications you actually launch by name. With the Kali branch of the
menu now generated from the same metadata, the tools already have a home —
keeping them in Apps as well is pure duplication.

HOW: the XDG spec says a desktop file in a higher-precedence directory
replaces the lower one by ID, so writing ~/.local/share/applications/<id> with
NoDisplay=true hides it from every launcher without touching /usr. Exec, Name,
Icon and Terminal are copied through so anything resolving the entry by ID
still works.

  hide-kali-from-apps.py            hide them
  hide-kali-from-apps.py --restore  remove the overrides
  hide-kali-from-apps.py --status   report only
"""
import argparse
import sys
from pathlib import Path

SYS_APPS = Path("/usr/share/applications")
USER_APPS = Path.home() / ".local/share/applications"
MARKER = "X-KaliHyprland-Hidden=true"


def read_entry(path):
    data, in_entry = {}, False
    for line in path.read_text(errors="replace").splitlines():
        t = line.strip()
        if t.startswith("["):
            in_entry = t == "[Desktop Entry]"
            continue
        if not in_entry or "=" not in t or t.startswith("#"):
            continue
        k, _, v = t.partition("=")
        if "[" not in k:
            data.setdefault(k.strip(), v.strip())
    return data


def ours(path):
    """Only ever touch overrides this script wrote."""
    try:
        return MARKER in path.read_text(errors="replace")
    except OSError:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--restore", action="store_true", help="remove the overrides")
    ap.add_argument("--status", action="store_true", help="report only")
    args = ap.parse_args()

    existing = [p for p in USER_APPS.glob("kali-*.desktop") if ours(p)]
    sources = sorted(SYS_APPS.glob("kali-*.desktop"))

    if args.status:
        print(f"system kali entries : {len(sources)}")
        print(f"overrides in place  : {len(existing)}")
        foreign = [p.name for p in USER_APPS.glob("kali-*.desktop") if not ours(p)]
        if foreign:
            print(f"NOT ours (left alone): {len(foreign)} -> {foreign[:3]}")
        return

    if args.restore:
        for p in existing:
            p.unlink()
        print(f"removed {len(existing)} override(s)")
        if not any(USER_APPS.iterdir()):
            pass
        print("run: update-desktop-database ~/.local/share/applications 2>/dev/null || true")
        return

    if not sources:
        sys.exit(f"no kali-*.desktop under {SYS_APPS} — nothing to hide")

    USER_APPS.mkdir(parents=True, exist_ok=True)
    written = skipped = 0
    for src in sources:
        dest = USER_APPS / src.name
        if dest.exists() and not ours(dest):
            skipped += 1          # a real user override — never clobber it
            continue
        d = read_entry(src)
        lines = [
            "[Desktop Entry]",
            "# Written by kali-hyprland: hides this Kali tool from the Omarchy",
            "# Apps launcher, because the generated Kali menu already lists it.",
            "# Remove with: lib/hide-kali-from-apps.py --restore",
            MARKER,
            "Type=" + d.get("Type", "Application"),
            "Name=" + d.get("Name", src.stem),
            "NoDisplay=true",
        ]
        for k in ("Exec", "Icon", "Terminal", "Comment", "Categories"):
            if d.get(k):
                lines.append(f"{k}={d[k]}")
        dest.write_text("\n".join(lines) + "\n")
        written += 1

    print(f"hid {written} Kali entries from Apps")
    if skipped:
        print(f"left {skipped} pre-existing user override(s) untouched")


if __name__ == "__main__":
    main()

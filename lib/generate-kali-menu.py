#!/usr/bin/env python3
"""Generate the Kali branch of the Omarchy menu from Kali's own metadata.

SOURCES (all shipped by the kali-menu package — we invent no taxonomy):
  /etc/xdg/menus/applications-merged/kali-applications.menu   the hierarchy
  /usr/share/desktop-directories/kali-*.directory             category names
  /usr/share/applications/kali-*.desktop                      the tools

WHY GENERATE: hand-listing tools duplicates what Kali already publishes, goes
stale the moment a tool is installed or removed, and covered only 79 of 497.

The generated rows are merged with hand-written "extras" (interactive prompts,
service toggles, system maintenance) that have no .desktop equivalent, and the
combined result is written as the Omarchy user menu extension.

Re-run after installing or removing tools, then `omarchy menu refresh`.
"""
import html
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

MENU_XML = Path("/etc/xdg/menus/applications-merged/kali-applications.menu")
DIRS = Path("/usr/share/desktop-directories")
APPS = Path("/usr/share/applications")

PROJECT = Path(__file__).resolve().parents[1]
EXTRAS = PROJECT / "config/omarchy/kali-menu-extras.jsonc"
OUTPUT = PROJECT / "config/omarchy/extensions/omarchy-menu.jsonc"

# Kali's top-level is the MITRE ATT&CK chain. Nerd Font glyphs, chosen per
# stage; subcategories inherit a neutral folder glyph.
TOP_ICONS = {
    "usual applications":       "",
    "reconnaissance":           "\U000f06f5",
    "resource development":     "\U000f0ad1",
    "initial access":           "\U000f0dbc",
    "execution":                "\U000f0234",
    "persistence":              "\U000f0193",
    "privilege escalation":     "\U000f0552",
    "defense evasion":          "\U000f0499",
    "credential access":        "\U000f0341",
    "discovery":                "\U000f0349",
    "lateral movement":         "\U000f0339",
    "collection":               "\U000f0770",
    "command and control":      "\U000f0a0d",
    "exfiltration":             "\U000f0176",
    "impact":                   "\U000f0026",
    "forensics":                "\U000f0964",
    "services and other tools": "\U000f0493",
}
SUB_ICON = "\U000f0770"     # folder-ish, for nested categories
TUI_ICON = "\U000f018d"     # terminal
GUI_ICON = "\U000f04a0"     # window
PKG_ICON = "\U000f0549"     # package / install


def installed_packages():
    """Every installed package name, from ONE dpkg-query call.

    kali-menu ships all ~506 kali-*.desktop files whether or not the tool is
    installed, so the desktop file's existence proves nothing. We therefore
    resolve installation HERE, at generation time, and emit no runtime `when`
    guard for tools at all.

    Doing it the other way round does not work: Omarchy batches every visible
    row's `when` into a single `bash -lc` script, and 917 dpkg-query calls
    overflow the argument limit — the process then fails to start and the whole
    menu comes up empty.
    """
    import subprocess
    out = subprocess.run(
        ["dpkg-query", "-W", "-f", "${Package} ${Status}\n"],
        capture_output=True, text=True).stdout
    return {
        line.split(" ", 1)[0]
        for line in out.splitlines()
        if line.endswith("install ok installed")
    }


def slugify(value):
    s = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return s or "x"


def read_desktop(path):
    """Parse the [Desktop Entry] group of a .desktop file."""
    data = {}
    in_entry = False
    try:
        for line in path.read_text(errors="replace").splitlines():
            line = line.strip()
            if line.startswith("["):
                in_entry = line == "[Desktop Entry]"
                continue
            if not in_entry or "=" not in line or line.startswith("#"):
                continue
            k, _, v = line.partition("=")
            if "[" not in k:          # skip localised keys like Name[fr]
                data.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return data


def load_apps(installed):
    """category -> [entry], INSTALLED tools only."""
    by_cat = {}
    skipped = 0
    for f in sorted(APPS.glob("kali-*.desktop")):
        d = read_desktop(f)
        if not d or d.get("NoDisplay", "").lower() == "true":
            continue
        name, exec_ = d.get("Name"), d.get("Exec")
        if not name or not exec_:
            continue
        pkg = d.get("X-Kali-Package", "")
        # NOTE: uninstalled tools are kept here on purpose — walk() filters
        # them out of the installed tree, and build_install_branch() needs
        # exactly those to offer them for installation.
        if pkg and pkg not in installed:
            skipped += 1

        entry = {
            "name": name,
            "exec": exec_,
            "comment": d.get("Comment", ""),
            "terminal": d.get("Terminal", "false").lower() == "true",
            "package": d.get("X-Kali-Package", ""),
            "file": f.name,
        }
        for cat in filter(None, d.get("Categories", "").split(";")):
            by_cat.setdefault(cat, []).append(entry)
    if skipped:
        print(f"  skipped {skipped} tool(s) whose package is not installed")
    return by_cat


def load_dir_titles():
    """kali-foo.directory -> display name (keeps Kali's "09 - Discovery")."""
    titles = {}
    for f in DIRS.glob("kali-*.directory"):
        d = read_desktop(f)
        if d and d.get("Name"):
            titles[f.name] = d["Name"]
    return titles


def kali_metapackages():
    """(name, summary) for every kali-linux-* / kali-tools-* metapackage."""
    import subprocess
    out = subprocess.run(["apt-cache", "search", "^kali-linux-|^kali-tools-"],
                         capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        name, _, summary = line.partition(" - ")
        name = name.strip()
        if name.startswith(("kali-linux-", "kali-tools-")):
            rows.append((name, summary.strip()))
    return sorted(rows)


def arch_only_overrides(omarchy_path):
    """Hide Omarchy menu rows that can only work on Arch.

    Omarchy assumes pacman/yay. On Kali those rows open its branded floating
    terminal and then fail — the user sees an "Omarchy" window offering a
    pacman install that cannot succeed.

    Rather than hand-listing them (which rots the moment Omarchy changes its
    menu), this scans Omarchy's OWN bin/ for scripts that call pacman or yay,
    then scans its default menu for rows whose action invokes one, and emits a
    `when` guard of `omarchy-cmd-present pacman` for each. That predicate is
    false on Debian, so the rows disappear here and the file stays valid on a
    real Arch box.
    """
    import re as _re
    om = Path(omarchy_path)
    bindir, menu = om / "bin", om / "default/omarchy/omarchy-menu.jsonc"
    if not bindir.is_dir() or not menu.is_file():
        return {}

    word = lambda w: r"(?<![\w-])" + _re.escape(w) + r"(?![\w-])"

    arch_scripts = set()
    for f in bindir.iterdir():
        if not f.is_file():
            continue
        try:
            if _re.search(r"(?<![\w-])(pacman|yay)(?![\w-])", f.read_text(errors="replace")):
                arch_scripts.add(f.name)
        except OSError:
            continue

    raw = menu.read_text()
    body = _re.sub(r"^[ \t]*//[^\n]*(\n|$)", "", raw, flags=_re.M)
    body = _re.sub(r",(\s*[}\]])", r"\1", body)
    try:
        rows = json.loads(body)
    except json.JSONDecodeError as exc:
        print(f"  warning: Omarchy's menu did not parse ({exc}); no Arch rows hidden")
        return {}

    out = {}
    for key, val in rows.items():
        action = val.get("action", "")
        if not action:
            continue
        hit = any(_re.search(word(c), action) for c in arch_scripts) or \
              _re.search(r"(?<![\w-])(pacman|yay)(?![\w-])", action)
        if hit:
            # Reuse the row as-is; only add the guard.
            row = {k: v for k, v in val.items() if k in
                   ("icon", "label", "title", "description", "action", "checked")}
            row["when"] = "omarchy-cmd-present pacman"
            out[key] = row
    return out


def build_install_branch(out, by_cat, installed, titles):
    """An `install.kali` branch: metapackages, plus any tool not yet installed.

    Lives under Omarchy's own `install` root, so it sits beside Omarchy's
    installers rather than inventing a second place to install things.
    """
    out["install.kali"] = {
        "icon": "\uf327", "label": "Kali", "title": "Install Kali Tools",
        "aliases": ["install-kali"],
    }

    metas = kali_metapackages()
    if metas:
        out["install.kali.metapackages"] = {
            "icon": PKG_ICON, "label": "Metapackages", "title": "Kali Metapackages",
        }
        for name, summary in metas:
            row = {
                "icon": PKG_ICON,
                "label": name.replace("kali-tools-", "").replace("kali-linux-", ""),
                # `checked` puts a ✓ on what is already installed.
                "checked": f"dpkg-query -W -f='${{Status}}' {name} 2>/dev/null | grep -q '^install ok installed$'",
                "action": f"omarchy-launch-floating-terminal-with-presentation 'sudo apt update && sudo apt install -y {name}'",
            }
            if summary:
                row["description"] = summary
            out[f"install.kali.metapackages.{slugify(name)}"] = row

    # Individual tools that are NOT installed, grouped by their Kali category.
    # Empty on a kali-linux-everything box; the useful half on a lean one.
    pending = {}
    for cat, entries in by_cat.items():
        for e in entries:
            pkg = e.get("package")
            if pkg and pkg not in installed:
                pending.setdefault(cat, {})[pkg] = e

    if pending:
        out["install.kali.tools"] = {
            "icon": PKG_ICON, "label": "Individual tools", "title": "Install a tool",
        }
        for cat in sorted(pending):
            title = titles.get(cat + ".directory", cat.replace("kali-", "").replace("-", " ").title())
            label = re.sub(r"^\d+\s*[-–]\s*", "", title).strip()
            cid = f"install.kali.tools.{slugify(cat)}"
            out[cid] = {"icon": PKG_ICON, "label": label, "title": label}
            for pkg, e in sorted(pending[cat].items()):
                row = {
                    "icon": PKG_ICON,
                    "label": e["name"],
                    "action": f"omarchy-launch-floating-terminal-with-presentation 'sudo apt update && sudo apt install -y {pkg}'",
                }
                if e.get("comment"):
                    row["description"] = e["comment"]
                out[f"{cid}.{slugify(pkg)}"] = row


def walk(menu_el, parent_id, titles, by_cat, out, seen_tools):
    """Recurse the .menu XML, emitting a submenu row per <Menu>."""
    for sub in menu_el.findall("Menu"):
        name_el = sub.find("Name")
        if name_el is None or not name_el.text:
            continue
        name = name_el.text.strip()

        dir_el = sub.find("Directory")
        title = titles.get(dir_el.text.strip(), name) if dir_el is not None and dir_el.text else name
        # Kali prefixes top-level names with a number ("09 - Discovery").
        label = re.sub(r"^\d+\s*[-–]\s*", "", title).strip() or name

        mid = f"{parent_id}.{slugify(name)}"
        icon = TOP_ICONS.get(label.lower(), SUB_ICON) if parent_id == "kali" else SUB_ICON
        out[mid] = {"icon": icon, "label": label, "title": label}

        # Tools directly in this category.
        cats = [c.text.strip() for c in sub.iter("Category") if c.text]
        tools = []
        for c in cats:
            tools.extend(by_cat.get(c, []))

        # De-dupe within the submenu; a tool tagged with several categories
        # legitimately appears under each, but never twice in the same one.
        local = set()
        for t in sorted(tools, key=lambda e: e["name"].lower()):
            if t["file"] in local:
                continue
            # Only installed tools belong in the launch tree.
            if t["package"] and t["package"] not in INSTALLED:
                continue
            local.add(t["file"])
            seen_tools.add(t["file"])

            tid = f"{mid}.{slugify(t['name'])}"
            if tid in out:
                continue

            if t["terminal"]:
                action = f"omarchy-launch-tui {shell_quote(t['exec'])}"
                ticon = TUI_ICON
            else:
                action = f"uwsm-app -- {t['exec']}"
                ticon = GUI_ICON

            # No `when` here on purpose — installation was resolved at
            # generation time (see installed_packages). Re-run the generator
            # after installing or removing tools.
            row = {"icon": ticon, "label": t["name"], "action": action}
            if t["comment"]:
                row["description"] = t["comment"]
            out[tid] = row

        walk(sub, mid, titles, by_cat, out, seen_tools)


def shell_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


def jsonc_line(key, row):
    def esc(s):
        return (s.replace("\\", "\\\\").replace('"', '\\"')
                 .replace("\n", " ").replace("\t", " "))
    parts = []
    for k in ("icon", "label", "title", "description", "when", "checked", "action", "target", "provider"):
        if row.get(k):
            parts.append(f'"{k}":"{esc(str(row[k]))}"')
    if row.get("aliases"):
        inner = ",".join(f'"{esc(a)}"' for a in row["aliases"])
        parts.insert(2, f'"aliases":[{inner}]')
    return f'  "{key}": {{{",".join(parts)}}},'


def main():
    if not MENU_XML.exists():
        sys.exit(f"missing {MENU_XML} — is the kali-menu package installed?")

    titles = load_dir_titles()
    installed = installed_packages()
    globals()["INSTALLED"] = installed
    print(f"  {len(installed)} packages installed")
    by_cat = load_apps(installed)

    root = ET.parse(MENU_XML).getroot()
    generated, seen = {}, set()
    generated["kali"] = {
        "icon": "",                     # nf-linux-kali_linux, the dragon
        "label": "Kali",
        "title": "Kali Tools",
        "aliases": ["security", "tools", "pentest"],
    }
    walk(root, "kali", titles, by_cat, generated, seen)

    # Drop categories that ended up with nothing in them. Kali declares some
    # (e.g. "Usual Applications") that no kali-*.desktop actually claims, and
    # an empty submenu is just a dead end in the menu.
    def prune(items):
        while True:
            has_child = {k.rsplit(".", 1)[0] for k in items if "." in k}
            dead = [k for k, v in items.items()
                    if "action" not in v and k != "kali" and k not in has_child]
            if not dead:
                return len(items)
            for k in dead:
                del items[k]

    prune(generated)

    # Built after pruning so the install branch is never pruned as "empty".
    build_install_branch(generated, by_cat, installed, titles)

    arch_rows = arch_only_overrides(os.environ.get("OMARCHY_PATH",
                                    str(Path.home() / ".local/share/omarchy")))
    generated.update(arch_rows)

    extras = EXTRAS.read_text() if EXTRAS.exists() else ""
    # Menu actions that run scripts out of this repo cannot hardcode a path:
    # the repo is cloned wherever the user likes. The extras file writes
    # @@PROJECT@@ and it is resolved here, against this script's own location.
    extras = extras.replace("@@PROJECT@@", str(PROJECT))

    submenus = sum(1 for v in generated.values() if "action" not in v)
    tools = len(generated) - submenus

    header = f"""{{
  // ─────────────────────────────────────────────────────────────────────────
  // GENERATED FILE — do not edit by hand.
  //
  //   Regenerate:  {PROJECT}/lib/generate-kali-menu.py
  //   Then:        omarchy menu refresh
  //
  // The Kali branch below is built from Kali's OWN menu metadata, so it is
  // always the real Kali taxonomy and always matches what is installed:
  //   /etc/xdg/menus/applications-merged/kali-applications.menu
  //   /usr/share/desktop-directories/kali-*.directory
  //   /usr/share/applications/kali-*.desktop
  //
  // This run: {submenus} categories, {tools} tools, from {len(list(APPS.glob('kali-*.desktop')))} desktop entries.
  //
  // Hand-written additions (interactive prompts, service toggles, system
  // maintenance, menu overrides) live in and are appended from:
  //   config/omarchy/kali-menu-extras.jsonc
  // ─────────────────────────────────────────────────────────────────────────

"""
    lines = [header]
    for key in sorted(generated, key=lambda k: (k.count("."), k)):
        lines.append(jsonc_line(key, generated[key]))

    if extras.strip():
        lines.append("\n  // ── Hand-written extras ──────────────────────────────────────────────\n")
        lines.append(extras.rstrip().rstrip(","))
        lines.append("")

    lines.append("}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUTPUT}")
    print(f"  categories: {submenus}")
    print(f"  arch-only rows hidden: {len(arch_rows)}")
    print(f"  tools     : {tools}")


if __name__ == "__main__":
    main()

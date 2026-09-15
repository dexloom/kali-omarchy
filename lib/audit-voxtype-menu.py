#!/usr/bin/env python3
"""Audit the voxtype/localsend menu rows: parse, structure, and — the part that
actually matters — run every `when`/`checked` guard and every action's binary
through the same PATH the omarchy shell uses."""
import json, os, re, subprocess, pathlib

MENU = pathlib.Path.home() / ".config/omarchy/extensions/omarchy-menu.jsonc"
raw = MENU.read_text()
s = re.sub(r"^[ \t]*//[^\n]*(\n|$)", "", raw, flags=re.M)
s = re.sub(r",(\s*[}\]])", r"\1", s)
d = json.loads(s)

home = str(pathlib.Path.home())
shell_path = f"{home}/.local/share/omarchy/bin:{home}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
env = {"HOME": home, "PATH": shell_path, "USER": os.environ.get("USER", "fix")}

rows = {k: v for k, v in d.items() if "voxtype" in k or "localsend" in k}
print(f"rows found: {len(rows)}\n")

ok = bad = 0
for k in sorted(rows):
    v = rows[k]
    notes = []

    for guard in ("when", "checked"):
        if v.get(guard):
            r = subprocess.run(["bash", "-c", v[guard]], env=env,
                               capture_output=True, timeout=20)
            notes.append(f"{guard}={'PASS' if r.returncode == 0 else 'fail'}")

    act = v.get("action", "")
    if act:
        # Resolve the first executable word of the action.
        first = act.split()[0]
        r = subprocess.run(["bash", "-c", f"command -v {first}"], env=env,
                           capture_output=True, timeout=10)
        if r.returncode == 0:
            notes.append("action=RESOLVES")
            ok += 1
        else:
            notes.append(f"action=MISSING({first})")
            bad += 1

    kind = "submenu" if "action" not in v else "row"
    print(f"  {k:<38} {kind:<8} {v.get('label','')[:26]:<28} {' '.join(notes)}")

print(f"\nactions resolving: {ok}   NOT resolving: {bad}")

# Structure check
ids = set(d)
known = {"apps","learn","trigger","style","setup","install","remove","update","about","system"}
orph = [(k, k.rsplit(".",1)[0]) for k in rows
        if "." in k and k.rsplit(".",1)[0] not in ids and k.rsplit(".",1)[0] not in known]
print("orphan parents:", orph if orph else "none")

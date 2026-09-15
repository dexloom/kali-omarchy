# Hermes skills for a converted box

Two management skills for the machine *after* the transformation. They encode
the environment facts an agent otherwise has to rediscover — and, more
importantly, the ones it will otherwise get confidently wrong.

| Skill | Covers |
|---|---|
| [`kali-omarchy-system`](kali-omarchy-system/SKILL.md) | apt, the Omarchy command suite, session services, notifications |
| [`kali-omarchy-hyprland`](kali-omarchy-hyprland/SKILL.md) | the Lua config API, binds, window rules, reload and recovery |

## Why they exist

Omarchy is an Arch project. Kali is Debian. An agent reading Omarchy's own
documentation on a converted box will reach for `pacman`, call `notify-send`
directly, paste `hyprland.conf` syntax into a Lua file, and write window rules
against an `app_id` the terminal cannot set. Each of those fails in a way that
looks like broken configuration rather than a wrong assumption.

Both skills lead with the assumption they exist to correct, because that is the
part that has to survive being skimmed.

## Install

```bash
mkdir -p ~/.hermes/skills/devops
cp -r kali-omarchy-system kali-omarchy-hyprland ~/.hermes/skills/devops/
```

Hermes discovers skills under `~/.hermes/skills/<category>/<skill>/SKILL.md`;
the category directory is organisational and `devops` is a convention, not a
requirement.

## Using them with another agent runtime

They are plain Markdown with YAML frontmatter and carry no Hermes-specific
syntax in the body, so they port with a frontmatter change and nothing else:

- **Claude Code** — drop the directory into `.claude/skills/` and reduce the
  frontmatter to `name` and `description`.
- **System prompt / context file** — paste the body. The `## When to Use`
  section is written to be the routing hint; keep it.

## Keeping them honest

These describe a real machine, and a skill that has drifted from the machine is
worse than no skill, because it is trusted. The facts most likely to go stale:

- The list of Omarchy commands that wrap pacman — recheck after an Omarchy
  update with `grep -rln 'pacman\|yay' ~/.local/share/omarchy/bin/`.
- Which `.conf` files under `~/.config/hypr/` are legitimate.
- The `hl.dsp` vocabulary, which has already changed once across a Hyprland
  release.

If the repo is on the box, `12-omarchy4-verify.sh` covers most of the same
ground executably, and should be believed over either skill where they disagree.

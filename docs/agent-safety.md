# Rules for an agent driving this

Every rule here exists because it was broken first. They are grouped by what
they protect: the connection, the box, and your conclusions.

## Protecting the connection

### Never `pkill -f`

`pkill -f <pattern>` matches against the **full command line of every process,
including the one issuing the kill**. An agent running

```bash
pkill -f qterminal
```

over SSH matches its own `bash -c 'pkill -f qterminal'` and kills the session
that issued it. This happened twice during this project — once with
`qterminal`, once with `polkit-mate-authentication-agent` — and both times it
looked like the box had crashed.

Kill by PID, from a list you have already read:

```bash
pgrep -x qterminal                      # exact name, no command-line match
kill <pid>
```

Or, better, don't kill anything: `omarchy-restart-shell`,
`systemctl --user restart <unit>` and `hyprctl reload` cover almost every real
need.

### Never launch a VPN client directly

Starting a VPN reconfigures routing, and a remote session routed through the
interface being reconfigured dies with it. This is not hypothetical — launching
AmneziaVPN to check that it rendered correctly dropped the SSH connection
immediately.

If a network-reconfiguring application must be started, detach it and bound it:

```bash
setsid timeout 30 <command> >/tmp/out 2>&1 < /dev/null &
```

Then read `/tmp/out` on the next connection. Accept that you may need to
reconnect, and never chain anything important behind such a command.

### Treat anything that restarts networking the same way

`systemctl restart NetworkManager`, changing a Wi-Fi profile, bringing an
interface down. All of them are survivable with `ServerAliveInterval` set and a
plan to reconnect; none of them are survivable in the middle of a command whose
output you need.

## Protecting the box

### Hyprland is configured in Lua only

Hyprland looks for `hyprland.conf` **before** `hyprland.lua`. A single stray
`.conf` — one written by a config tool, one pasted from a blog post — silently
shadows the entire Lua configuration. The symptom is that nothing you edit has
any effect, with no error anywhere.

`12-omarchy4-verify.sh` asserts that no `hyprland.conf` exists. The deploy moves
one aside if it finds it. Do not add one back.

### Back up before overwriting, and know the backup exists

Every script here writes `<file>.bak-<timestamp>` before it replaces anything.
That convention is what makes recovery a one-liner:

```bash
ls -t ~/.config/hypr/hyprland.lua.bak-* | head -1
```

An agent adding new file-writing steps should follow it rather than inventing
its own scheme, and should never clean up backups as tidiness work.

### Don't test the lock screen until everything else is verified

Locking the screen is the one action that blocks your own ability to check
results. A locked session screenshots as a blank image, and windows cannot be
placed. Half a session's visual verification was lost this way, and the only way
out was to ask the human to unlock the machine.

Test the lock last, and tell the human immediately that you did.

### Don't write to `/etc` without reading it first

`17-lock-pam.sh` exists because Omarchy references Arch's
`system-local-login` PAM stack, which does not exist on Debian. The fix was to
write a Debian stack that `@include`s `common-auth` and `common-account`. Get
that wrong and you can lock every account out of authentication, from a script
that appeared to succeed.

## Protecting your conclusions

### Run the verifier after every change, and quote it

`12-omarchy4-verify.sh` needs no sudo and changes nothing. It is the only
statement about the system's state that is worth making. Report its tail
verbatim — "61 passed, 0 failed, 0 skipped" — rather than summarising it as
"everything works".

### Resolve the Hyprland instance every time

Hyprland leaves the socket directory of previous instances in
`$XDG_RUNTIME_DIR/hypr`. A stale `HYPRLAND_INSTANCE_SIGNATURE` addresses a
compositor that no longer exists, and `hyprctl` then reports confidently about
nothing. Always take the newest by mtime:

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
```

An early version of the verifier trusted the inherited value and passed checks
against a dead instance.

### Export PATH before probing for a binary

`command -v voxtype` run before the PATH export found the system copy rather
than the freshly built GPU one, and the script then "upgraded" a good binary
with a worse one. Set PATH first, and refuse to replace a binary that is
significantly larger than its replacement.

### Verify you installed the thing you meant

There are two projects called `voxtype` on GitHub. The one that installs first
from a naive search is a stub whose `--help` prints nothing. A check as cheap as
"does `--help` produce usage output" catches it. Name collisions are common
enough in this space to be worth one assertion each time.

### Never let a bare `except` hide a bug

The Kali menu generator wrapped its work in `except Exception: pass` and
reported "0 rows hidden" for an entire session. The real cause was a
`NameError` — `json` was never imported. Catch specific exceptions, or let it
crash.

### Check that a check can fail

Two verifier assertions passed for the wrong reasons: one grepped a file
including its comments, so a commented-out line satisfied it; another validated
the menu extension in isolation and reported 38 orphans that did not exist. An
assertion you have never seen fail is not evidence.

### Measure instead of reasoning about hardware

Two confident predictions in this project were wrong: that NVK needed a Turing
card (it has supported Pascal since Mesa 25.1 — the real blocker was missing PMU
firmware), and that the Intel iGPU would beat the NVIDIA MX350 for Whisper
inference (NVIDIA: 3.8 s; Intel: 9.5 s on the same 31.9 s clip).

Both cost more time than the measurement would have. Benchmark, then write the
number down in the file that depends on it — which is why
`config/systemd/voxtype.service.d/10-gpu.conf` carries its timings in comments.

## When to stop and ask

- A password is needed. Do not attempt `sudo -S`, do not edit sudoers to get
  around it, do not look for a cached credential.
- The verifier fails in a way the change does not explain.
- Recovery would need physical access to the machine.
- Something worked but you could not confirm it. Say that plainly; a claim of
  success you could not verify is worse than an honest "unverified".

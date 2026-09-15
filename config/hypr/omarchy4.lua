-- ---------------------------------------------------------------------------
-- omarchy4.lua — Omarchy 4 overlay for this box
--
-- Required from the bottom of hyprland.lua:  require("omarchy4")
--
-- Why an overlay and not a rewrite: hyprland.lua is the package-default
-- template plus your own edits. Keeping the Omarchy 4 wiring in its own module
-- means you can disable the whole thing by commenting out one require line,
-- and the Lua-only project rule still holds.
--
-- WHAT OMARCHY 4 IS, IN ONE LINE: bar, main menu, polkit modal and the
-- wifi/audio/bluetooth/power panels are all plugins inside ONE quickshell
-- process, started by omarchy-launch-shell.
--
-- NOTE ON DESCRIPTIONS: every hl.bind below passes `description`. That is not
-- decoration — `omarchy-menu-keybindings` only lists a Lua bind when it has a
-- description, because Hyprland reports Lua binds with the opaque dispatcher
-- `__lua`. No description means the bind is invisible in the keybindings menu.
-- ---------------------------------------------------------------------------

local omarchy = os.getenv("HOME") .. "/.local/share/omarchy"

-------------------------------
---- ENVIRONMENT            ----
-------------------------------

-- omarchy-launch-shell reads this to find shell/.
hl.env("OMARCHY_PATH", omarchy)

-- Omarchy's bin/ must be on PATH for menu actions and `when` guards to
-- resolve, and ~/.local/bin carries voxtype and the kali-* helper prompts.
--
-- IDEMPOTENT ON PURPOSE: hl.env() is re-evaluated on every `hyprctl reload`,
-- and an unconditional prepend grows PATH without bound — after ~20 reloads
-- this had the same two directories repeated 22 times. Only prepend when the
-- entry is not already there.
local omarchy_bin = omarchy .. "/bin"
local local_bin = os.getenv("HOME") .. "/.local/bin"
local current_path = os.getenv("PATH") or "/usr/bin:/bin"

local function path_has(dir)
    for entry in string.gmatch(current_path, "[^:]+") do
        if entry == dir then return true end
    end
    return false
end

local prefix = {}
if not path_has(omarchy_bin) then prefix[#prefix + 1] = omarchy_bin end
if not path_has(local_bin) then prefix[#prefix + 1] = local_bin end
if #prefix > 0 then
    hl.env("PATH", table.concat(prefix, ":") .. ":" .. current_path)
end

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland")

-- Hardware video decode/encode (VA-API).
--
-- This laptop has two render nodes:
--   renderD128 -> nouveau (MX350, PCI 01:00.0)     -- no useful VA-API
--   renderD129 -> i915    (Iris Plus, PCI 00:02.0) -- iHD, full decode/encode
--
-- Wayland clients inherit the compositor's device, which is the Intel one, so
-- naming the driver is enough here. There is NO libva variable for choosing
-- the DRM device (only LIBVA_DRIVER_NAME, LIBVA_DRIVERS_PATH,
-- LIBVA_MESSAGING_LEVEL and LIBVA_TRACE* exist) — a tool that opens DRM
-- directly has to be pointed at the node itself, e.g.
--   vainfo --display drm --device /dev/dri/by-path/pci-0000:00:02.0-render
hl.env("LIBVA_DRIVER_NAME", "iHD")

-------------------------------
---- AUTOSTART              ----
-------------------------------

hl.on("hyprland.start", function()
    -- Hand the Wayland session over to systemd --user.
    --
    -- Hyprland here is started by hand from a TTY (start-hyprland), not by a
    -- session manager, so NOTHING activates graphical-session.target. Every
    -- user unit bound to it therefore stays inactive forever — voxtype.service
    -- is "enabled" yet never runs, which looks exactly like a broken install.
    --
    -- Importing the env first matters: units started by systemd inherit only
    -- what systemd knows, and without WAYLAND_DISPLAY a graphical unit cannot
    -- talk to the compositor.
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE PATH")
    -- Start OUR target, not graphical-session.target directly: the latter sets
    -- RefuseManualStart=yes and can only be pulled in as a dependency.
    -- hyprland-session.target BindsTo it, so starting ours drags it up.
    hl.exec_cmd("systemctl --user start hyprland-session.target")

    -- The whole Omarchy shell. One process: bar + menu + polkit agent +
    -- panels. It supervises itself and logs to `journalctl -t omarchy-shell`.
    --
    -- Do NOT also start hyprpolkitagent: the shell ships its own polkit agent
    -- (omarchy.polkit, a keepLoaded service plugin) and two agents racing for
    -- the same authority produce a dialog that dismisses itself.
    hl.exec_cmd(omarchy .. "/bin/omarchy-launch-shell")
end)

-------------------------------
---- INPUT / BIND TUNING    ----
-------------------------------

hl.config({
    general = {
        -- Drag a window EDGE to resize it, no modifier needed — the mouse
        -- resize most people expect. Off by default in Hyprland (and in
        -- Omarchy), which is why grabbing an edge did nothing.
        resize_on_border = true,
        -- Borders are 2px; without a grab area you would have to hit those
        -- 2 pixels exactly. 15px makes the edge comfortably catchable.
        extend_border_grab_area = 15,
        -- Show the resize cursor when hovering a border, so the hit zone is
        -- discoverable rather than invisible.
        hover_icon_on_border = true,
    },
    input = {
        -- Hyprland's bind system fires on DISCRETE scroll steps. A touchpad
        -- emits continuous axis events; 1 emulates steps only when the device
        -- sends none, 2 forces it always. Forced here so SUPER+two-finger
        -- scroll reliably reaches the resize binds.
        emulate_discrete_scroll = 2,
    },
    binds = {
        -- A click had to move ZERO pixels to become a drag (Hyprland's
        -- default), so SUPER+click grabbed the window into move mode the
        -- instant the button went down. 10px means a click stays a click and
        -- only a deliberate drag moves the window.
        drag_threshold = 10,
        -- THE reason SUPER+two-finger-scroll felt dead: Hyprland throttles
        -- scroll-triggered binds, and the default is 300 ms. A mouse wheel
        -- emits one discrete click per notch so 300 ms is tolerable, but a
        -- touchpad emits a stream of small continuous axis events and all but
        -- one per 300 ms were being dropped. 0 processes every event.
        scroll_event_delay = 0,
    },
})

-------------------------------
---- OMARCHY KEYBINDINGS    ----
-------------------------------

local mod = "SUPER"

-- Menus ------------------------------------------------------------------
hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("omarchy-menu"),
    { description = "Omarchy menu" })
hl.bind(mod .. " + ALT + SPACE", hl.dsp.exec_cmd("omarchy-menu summon apps"),
    { description = "Launch apps" })
hl.bind(mod .. " + SHIFT + K", hl.dsp.exec_cmd("omarchy-menu summon kali"),
    { description = "Kali tools menu" })
hl.bind(mod .. " + CTRL + I", hl.dsp.exec_cmd("omarchy-menu summon install.kali"),
    { description = "Install Kali tools" })
hl.bind(mod .. " + ESCAPE", hl.dsp.exec_cmd("omarchy-menu summon system"),
    { description = "System menu" })
hl.bind(mod .. " + K", hl.dsp.exec_cmd("omarchy-menu-keybindings"),
    { description = "Keybindings" })

-- Terminals --------------------------------------------------------------
hl.bind(mod .. " + T", hl.dsp.exec_cmd("uwsm-app -- kitty"),
    { description = "Terminal (kitty)" })

-- Floating windows ---------------------------------------------------------
-- THIS is what makes Omarchy's "admin password" prompt appear centred: the
-- terminal running `sudo` is floated, centred and given a fixed size, so the
-- password line lands in the middle of the screen. It is a window rule, not
-- polkit — plain sudo never talks to polkit at all.
--
-- Omarchy applies these from default/hypr/apps/system.lua, which this setup
-- does not load (we require only omarchy4.lua), so they are reproduced here.
--
-- Matches:
--   org.omarchy.*  every terminal Omarchy launches (its presentation terminal,
--                  btop, bash, about) — including the Kali menu prompts, which
--                  go through omarchy-launch-floating-terminal-with-presentation
--   TUI.*          TUIs registered through Omarchy's TUI installer
--   Omarchy        the --title it sets on the presentation terminal
--   portal dialogs file pickers and screen-share prompts, which are only ever
--                  dialogs and should never tile
local float_match = "^(org\\.omarchy\\..*|TUI\\..*|xdg-desktop-portal-gtk)$"

hl.window_rule({ name = "omarchy-float",  match = { class = float_match }, float = true })
hl.window_rule({ name = "omarchy-center", match = { class = float_match }, center = true })
hl.window_rule({ name = "omarchy-size",   match = { class = float_match }, size = { 875, 600 } })

-- ...except the screensaver, which is also an `org.omarchy.*` class and so is
-- caught by the three rules above. Upstream never hits this: Omarchy tags the
-- windows it wants floated and sizes `tag:floating-window`, while the rules
-- here match on the class pattern, which is the broader net. Left alone, the
-- screensaver opens as a centred 875x600 box in the middle of the desktop
-- instead of covering it.
--
-- These come last so they win, and they mirror what Omarchy's own
-- default/hypr/apps/system.lua asks for.
local screensaver_match = "^org\\.omarchy\\.screensaver$"
hl.window_rule({ name = "screensaver-fullscreen", match = { class = screensaver_match }, fullscreen = true })
hl.window_rule({ name = "screensaver-animation",  match = { class = screensaver_match }, animation = "slide" })

-- The presentation terminal is identified by title as well as app-id, because
-- xdg-terminal-exec does not always pass --app-id through to every terminal.
hl.window_rule({ name = "omarchy-title-float",  match = { title = "^Omarchy$" }, float = true })
hl.window_rule({ name = "omarchy-title-center", match = { title = "^Omarchy$" }, center = true })
hl.window_rule({ name = "omarchy-title-size",   match = { title = "^Omarchy$" }, size = { 875, 600 } })

-- Browser ------------------------------------------------------------------
-- omarchy-launch-or-focus raises an existing Chromium window instead of
-- spawning a second one; it only launches when no match is found. Note
-- SUPER+CTRL+B is Bluetooth, so plain SUPER+B was free.
hl.bind(mod .. " + B", hl.dsp.exec_cmd("omarchy-launch-or-focus chromium \"uwsm-app -- chromium\""),
    { description = "Browser (Chromium)" })

-- Bar panels -------------------------------------------------------------
hl.bind(mod .. " + CTRL + W", hl.dsp.exec_cmd("omarchy-shell shell summon omarchy.network"),
    { description = "Wifi controls" })
hl.bind(mod .. " + CTRL + B", hl.dsp.exec_cmd("omarchy-shell shell summon omarchy.bluetooth"),
    { description = "Bluetooth controls" })
hl.bind(mod .. " + CTRL + A", hl.dsp.exec_cmd("omarchy-shell shell summon omarchy.audio"),
    { description = "Audio controls" })
hl.bind(mod .. " + CTRL + P", hl.dsp.exec_cmd("omarchy-shell shell summon omarchy.power"),
    { description = "Power and battery" })

-- Clipboard, emoji, capture ----------------------------------------------
hl.bind(mod .. " + CTRL + V", hl.dsp.exec_cmd("omarchy-menu-clipboard"),
    { description = "Clipboard history" })
hl.bind(mod .. " + CTRL + E", hl.dsp.exec_cmd("omarchy-menu-emoji"),
    { description = "Emojis" })
hl.bind("PRINT", hl.dsp.exec_cmd("omarchy-capture-screenshot"),
    { description = "Screenshot" })
hl.bind(mod .. " + PRINT", hl.dsp.exec_cmd("omarchy-capture-region"),
    { description = "Screenshot region" })

-- System-wide copy / paste / undo ----------------------------------------
-- NOT bound to SUPER+C/V/Z: those are already "close window" and "toggle
-- floating" in the base config, and stealing them is a bad trade.
--
-- The honest situation on Wayland:
--   * GUI apps already handle Ctrl+C / Ctrl+V / Ctrl+Z natively.
--   * In terminals Ctrl+C is SIGINT; copy/paste live on Ctrl+Shift+C/V.
--   * A compositor bind on CTRL+C would fire FIRST and take SIGINT away from
--     every terminal on the box — unacceptable on a machine running scans.
--
-- So terminals are fixed in the TERMINAL, not the compositor: kitty gets
-- `copy_or_interrupt`, which copies when there is a selection and sends SIGINT
-- when there is not. See config/kitty/kitty.conf and the README.
--
-- hypr-clipkey stays available for anything that needs a forced re-emit:
--   hypr-clipkey copy | paste | undo

-- Touchpad gestures --------------------------------------------------------
-- THE fix for "SUPER + two-finger scroll doesn't resize".
--
-- Hyprland's `mouse_up` / `mouse_down` binds only fire for a PHYSICAL mouse
-- wheel; touchpad scrolling never reaches the keybind system at all. Confirmed
-- here by probe (an exclusively-bound logging action never fired) and upstream
-- in hyprwm/Hyprland discussion #12942, where the request for generalised
-- scroll_* binds is answered by pointing at the gesture system instead.
--
-- So touchpad resize is a GESTURE, not a bind. `mods` keeps plain two-finger
-- scrolling working normally for content — only SUPER + two fingers resizes.
hl.gesture({ fingers = 2, direction = "horizontal", action = "resize", mods = "SUPER" })
hl.gesture({ fingers = 2, direction = "vertical",   action = "resize", mods = "SUPER" })

-- Three fingers moves the window, again only while SUPER is held.
hl.gesture({ fingers = 3, direction = "horizontal", action = "move", mods = "SUPER" })

-- Window resize ----------------------------------------------------------
-- Mouse resize with the LEFT button, since SUPER + LEFT-drag is already
-- "move window". Omarchy's default SUPER + RIGHT-drag is deliberately not used
-- here: a right-button drag on a touchpad is a two-finger click-and-hold,
-- which is awkward and did not work reliably on this machine.
hl.bind(mod .. " + SHIFT + mouse:272", hl.dsp.window.resize(),
    { mouse = true, description = "Resize window (left drag)" })

-- Keyboard resize, matching Omarchy's own scheme: MINUS / EQUAL (code:20 and
-- code:21) with three magnitudes — ALT small, plain medium, CTRL large.
hl.bind(mod .. " + code:20", hl.dsp.window.resize({ x = -100, y = 0, relative = true }),
    { description = "Shrink window width" })
hl.bind(mod .. " + code:21", hl.dsp.window.resize({ x =  100, y = 0, relative = true }),
    { description = "Expand window width" })
hl.bind(mod .. " + SHIFT + code:20", hl.dsp.window.resize({ x = 0, y = -100, relative = true }),
    { description = "Shrink window height" })
hl.bind(mod .. " + SHIFT + code:21", hl.dsp.window.resize({ x = 0, y =  100, relative = true }),
    { description = "Expand window height" })
hl.bind(mod .. " + ALT + code:20", hl.dsp.window.resize({ x = -25, y = 0, relative = true }),
    { description = "Shrink window width a little" })
hl.bind(mod .. " + ALT + code:21", hl.dsp.window.resize({ x =  25, y = 0, relative = true }),
    { description = "Expand window width a little" })
hl.bind(mod .. " + CTRL + code:20", hl.dsp.window.resize({ x = -300, y = 0, relative = true }),
    { description = "Shrink window width a lot" })
hl.bind(mod .. " + CTRL + code:21", hl.dsp.window.resize({ x =  300, y = 0, relative = true }),
    { description = "Expand window width a lot" })

-- Voice dictation ----------------------------------------------------------
-- Same keys Omarchy uses. Guarded on the binary being present so the binds
-- simply do not exist if voxtype was never installed.
-- Test the file directly rather than shelling out to `command -v`: Hyprland
-- parses this config with whatever PATH the session was started with, and a
-- TTY-launched session does not necessarily have ~/.local/bin on it, so the
-- lookup failed and the binds were silently skipped.
local voxtype_bin = os.getenv("HOME") .. "/.local/bin/voxtype"
local voxtype_f = io.open(voxtype_bin, "r")
if voxtype_f then
    voxtype_f:close()
    hl.bind(mod .. " + CTRL + X", hl.dsp.exec_cmd(voxtype_bin .. " record toggle"),
        { description = "Toggle dictation" })
    hl.bind("F9", hl.dsp.exec_cmd(voxtype_bin .. " record start"),
        { description = "Start dictation (push-to-talk)" })
    hl.bind("F9", hl.dsp.exec_cmd(voxtype_bin .. " record stop"),
        { description = "Stop dictation (push-to-talk)", release = true })
end

-- Layout -----------------------------------------------------------------
-- Hyprland 0.56 ships a built-in `scrolling` layout alongside `dwindle`
-- (no plugin needed). Omarchy's toggle switches the CURRENT workspace between
-- them and persists the choice per workspace under
-- ~/.local/state/omarchy/workspace-layouts/.
--   dwindle   — binary tree, auto-arranges every window into the split
--   scrolling — infinite horizontal strip; windows keep their width and you
--               scroll along the row instead of everything shrinking
hl.bind(mod .. " + L", hl.dsp.exec_cmd("omarchy-hyprland-workspace-layout-toggle"),
    { description = "Toggle workspace layout (dwindle / scrolling)" })

-- Shell ------------------------------------------------------------------
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("omarchy-restart-shell"),
    { description = "Restart Omarchy shell" })

-- Hyprland, the M3 desktop.
--
-- Managed by ArchWork. This file is the one in the repository: the dotfiles
-- role links ~/.config/hypr at the clone, so an edit made on the machine is an
-- edit to the repository, and Hyprland reloads it as soon as it is saved.
--
-- Lua rather than the older hyprland.conf. Hyprland deprecated hyprlang at
-- 0.55 and removes it at 0.57, which is the next release after the 0.56.2 in
-- extra, so on a rolling distribution the old format stops being read on an
-- ordinary update rather than on a schedule of ours (D-026).
--
-- Deliberately plain. D-020 leaves the Kvantum theme and its GTK counterpart
-- open, so nothing here picks a colour scheme: a desktop that looks half
-- themed is harder to reason about than one that looks like the defaults.
-- Keybindings, autostart and input are decided, so they are here.

-- Whatever the machine has, at its preferred mode. Real monitor layout belongs
-- to the physical machines at M8 and M9, not to a VM that has one virtual head.
-- scale is a string here, not a number: Hyprland parses mode, position and
-- scale as strings (MONITOR_FIELDS in LuaBindingsConfigRules.cpp), so the 1
-- that the old hyprland.conf wrote as a bare number has to be quoted.
--
-- The desktop's two named outputs get an explicit layout: DP-2 (3840x2160 (resized
-- by scaling)) on the left at 0x0, DP-1 (3440x1440) on the right auto-positioned,
-- flush against DP-2's own width. Named rules match by output name, so this says
-- nothing about any other machine: the laptop's panel is eDP-1, never DP-1 or DP-2,
-- and falls through to the wildcard rule below untouched.
hl.monitor({ output = "DP-2", mode = "preferred", position = "0x0",    scale = "1.33" })
hl.monitor({ output = "DP-1", mode = "preferred", position = "auto-right", scale = "1" })

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})

hl.config({
    -- The installer sets KEYMAP=uk for the console
    -- (scripts/archwork-install.sh). Hyprland defaults to us, so without this
    -- the desktop and the greeter would disagree about where the punctuation
    -- is.
    input = {
        kb_layout    = "gb",
        follow_mouse = 1,

        touchpad = {
            natural_scroll = true,
        },
    },

    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        layout      = "dwindle",
    },

    decoration = {
        rounding = 4,
    },

    misc = {
        -- No Hyprland logo and no splash. What is behind the windows is
        -- hyprpaper's, configured in hyprpaper.conf next to this file, and
        -- the grey below is only what shows before it starts.
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = 0x1c1c1c,
    },
})

hl.env("XCURSOR_SIZE", "24")
-- Qt applications on Wayland, falling back to XWayland where a toolkit has no
-- Wayland plugin.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- Qt file dialogs come from the portal, Qt widgets come from Kvantum. These
-- two settings look like they contradict each other and do not: the platform
-- theme decides who draws a dialog, the style override decides who paints the
-- widgets. Setting QT_QPA_PLATFORMTHEME to kvantum instead, which is the usual
-- advice, gives Qt its own file chooser and takes the portal out of the path
-- the M3 criteria test (D-023).
hl.env("QT_QPA_PLATFORMTHEME", "xdgdesktopportal")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
-- GTK asks the portal for a file chooser only when told to. Unset, a GTK
-- application opens its own, which looks identical on screen and proves
-- nothing about xdg-desktop-portal-gtk (D-023).
hl.env("GTK_USE_PORTAL", "1")

-- What the session starts.
--
-- The environment import comes first. xdg-desktop-portal and the polkit agent
-- are activated by D-Bus, which starts them with whatever environment the bus
-- knew about at the time: without this they come up unable to find the
-- compositor, and every portal request fails in a way that looks like a
-- portal bug rather than a missing variable.
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

    -- The fallback set (desktop-shell.md). Quickshell replaces the bar and the
    -- notifications at M6 and these stay installed behind it, so that a broken
    -- shell leaves an ugly desktop rather than an unusable machine. waybar runs
    -- the configuration it ships, per D-020.
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")

    -- hypridle and hyprpaper are pure background daemons, nothing left for
    -- this hook to coordinate beyond starting them, so they run as systemd
    -- --user units instead (D-048): restart on crash, real logs
    -- (journalctl --user -u hypridle), a real status. Started explicitly
    -- here, the same as hyprpolkitagent above, rather than left to
    -- graphical-session.target to reach on its own: whether that target's
    -- timing in this session can be trusted is not something to assume.
    -- Units live at dotfiles/systemd/user/, linked alongside this file.
    --
    -- hypridle reads dotfiles/hypr/hypridle.conf (M4, security-power.md,
    -- D-028). hyprpaper reads dotfiles/hypr/hyprpaper.conf, the wallpaper
    -- that is the keybinding cheat sheet (D-032).
    hl.exec_cmd("systemctl --user start hypridle.service")
    hl.exec_cmd("systemctl --user start hyprpaper.service")

    -- Clipboard history (D-048), Quickshell-independent: cliphist watches
    -- here, Super+C below picks. Two watchers rather than one --watch
    -- covering everything, matching cliphist's own documented setup.
    hl.exec_cmd("systemctl --user start cliphist-text.service")
    hl.exec_cmd("systemctl --user start cliphist-image.service")
end)

local mod = "SUPER"

hl.bind(mod .. " + Return",   hl.dsp.exec_cmd("kitty"))
hl.bind(mod .. " + D",        hl.dsp.exec_cmd("fuzzel"))
hl.bind(mod .. " + Q",        hl.dsp.window.close())
hl.bind(mod .. " + F",        hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",        hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + L",        hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())

-- Clipboard history picker (D-048). cliphist-text.service and
-- cliphist-image.service do the watching; this is the on-demand half.
hl.bind(mod .. " + C", hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"))

-- grim writes to a path that has to exist, and a screenshot that fails because
-- a directory is missing is a poor first impression of a fresh machine.
hl.bind("Print", hl.dsp.exec_cmd("mkdir -p ~/Pictures/screenshots && grim ~/Pictures/screenshots/$(date +%Y-%m-%d-%H%M%S).png"))

hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 9 do
    hl.bind(mod .. " + " .. i,             hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i,     hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

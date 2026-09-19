// this file is used to index all searchable items in the settings tab

import QtQuick
import qs.modules.theme
import qs.modules.services

QtObject {
    // Array of searchable items
    // { label, keywords, section (int), subSection (string), subLabel (string), icon: (string/url), isIcon (bool) }

    // IMPORTANT: about the keywords,
    // it will try to guess what users would want to search, not the feature name only

    // Main Sections:
    // 0: Network, 1: Bluetooth, 2: Mixer, 3: AI, 4: Effects, 5: Theme,
    // 6: Binds, 7: System, 8: Compositor, 9: Ambxst, 10: Plugins,
    // 11: System Sounds, 12: Mods, 13: Turret Assistant
    // Upstream ships Mods as section 10; it is renumbered to 12 locally
    // because 10 and 11 were already taken. Keep SettingsTab.qml in sync.
    
    property var dynamicItems: []

    readonly property var staticItems: [
        // --- Mods ---
        { label: "Mods", keywords: "extensions plugins modifications packages", section: 12, subSection: "", subLabel: "", icon: Icons.puzzlePiece, isIcon: true },
        { label: "Install mod", keywords: "add local directory archive git repository source", section: 12, subSection: "", subLabel: "Mods", icon: Icons.puzzlePiece, isIcon: true },
        { label: "Rollback generation", keywords: "restore recover previous failed", section: 12, subSection: "", subLabel: "Mods", icon: Icons.arrowCounterClockwise, isIcon: true },

        // --- Network ---
        { label: I18n.t("settings.network"), keywords: "internet wifi connection ethernet ip", section: 0, subSection: "", subLabel: "", icon: Icons.wifiHigh, isIcon: true },

        // --- Bluetooth ---
        { label: I18n.t("settings.bluetooth"), keywords: "devices pairing connect", section: 1, subSection: "", subLabel: "", icon: Icons.bluetooth, isIcon: true },

        // --- Mixer ---
        { label: I18n.t("settings.audio_mixer"), keywords: "sound volume output input mic speaker", section: 2, subSection: "", subLabel: "", icon: Icons.faders, isIcon: true },

        // --- Effects ---
        { label: I18n.t("settings.audio_effects"), keywords: "equalizer bass treble easyeffects", section: 4, subSection: "", subLabel: "", icon: Icons.waveform, isIcon: true },
        
        // --- Theme ---
        { label: I18n.t("settings.theme"), keywords: "appearance look style customize", section: 5, subSection: "", subLabel: I18n.t("settings.theme"), icon: Icons.paintBrush, isIcon: true },
        
        // Theme > General
        { label: I18n.t("settings.theme.wallpapers"), keywords: "background image picture desktop", section: 5, subSection: "general", subLabel: I18n.t("settings.theme"), icon: Icons.image, isIcon: true },
        { label: I18n.t("settings.theme.tint_icons"), keywords: "color icons tint monochrome", section: 5, subSection: "general", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.enable_corners"), keywords: "rounded corners radius screen", section: 5, subSection: "general", subLabel: I18n.t("settings.theme"), icon: Icons.cornersOut, isIcon: true },
        { label: I18n.t("settings.theme.animation_duration"), keywords: "speed fast slow transition", section: 5, subSection: "general", subLabel: I18n.t("settings.theme"), icon: Icons.clock, isIcon: true },
        { label: I18n.t("settings.theme.ui_font"), keywords: "typography text family size", section: 5, subSection: "general", subLabel: I18n.t("settings.theme"), icon: Icons.textT, isIcon: true },
        { label: I18n.t("settings.theme.roundness"), keywords: "radius border curve", section: 5, subSection: "general", subLabel: I18n.t("settings.theme"), icon: Icons.circle, isIcon: true },
        
        // Theme > Shadow
        { label: I18n.t("settings.theme.shadow_opacity"), keywords: "darkness alpha transparency", section: 5, subSection: "shadow", subLabel: I18n.t("settings.theme"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.theme.shadow_blur"), keywords: "softness diffusion", section: 5, subSection: "shadow", subLabel: I18n.t("settings.theme"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.theme.shadow_offset"), keywords: "position x y direction", section: 5, subSection: "shadow", subLabel: I18n.t("settings.theme"), icon: Icons.arrowsOutSimple, isIcon: true },

        // Theme > Colors
        { label: I18n.t("settings.theme.color_scheme"), keywords: "palette variant light dark", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.color_variant"), keywords: "background popup internal bar pane", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.background_variant"), keywords: "wallpaper desktop color", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.popup_variant"), keywords: "dialog modal color", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.internal_bg_variant"), keywords: "inside background color", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.bar_bg_variant"), keywords: "taskbar panel color", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.pane_variant"), keywords: "sidebar panel color", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("theme.gradient_mode"), keywords: "linear radial halftone", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("theme.item_color"), keywords: "overbackground surface", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.color_opacity"), keywords: "alpha transparency", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.color_border"), keywords: "stroke outline", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("theme.gradient_stops"), keywords: "color position stops", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.theme.gradient_angle"), keywords: "direction rotation degrees", section: 5, subSection: "colors", subLabel: I18n.t("settings.theme"), icon: Icons.palette, isIcon: true },

        // --- Binds ---
        { label: I18n.t("settings.binds.key_bindings"), keywords: "shortcuts keyboard hotkeys", section: 6, subSection: "", subLabel: "", icon: Icons.keyboard, isIcon: true },
        // Binds > Ambxst
        { label: I18n.t("settings.binds.launcher"), keywords: "app launcher menu shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.rocket, isIcon: true },
        { label: I18n.t("settings.binds.dashboard"), keywords: "widgets dashboard shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.binds.clipboard"), keywords: "copy paste shortcut super v", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.clipboard, isIcon: true },
        { label: I18n.t("settings.binds.emoji"), keywords: "picker shortcut super period", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.binds.tmux"), keywords: "terminal shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.binds.wallpapers"), keywords: "background shortcut super comma", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.binds.assistant"), keywords: "ai help shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.binds.notes"), keywords: "note shortcut super n", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.binds.overview"), keywords: "workspace shortcut super tab", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.binds.powermenu"), keywords: "logout shutdown shortcut super escape", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.power, isIcon: true },
        { label: I18n.t("settings.binds.settings"), keywords: "config preferences shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.gear, isIcon: true },
        { label: I18n.t("settings.binds.lockscreen"), keywords: "lock security shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.lock, isIcon: true },
        { label: I18n.t("settings.binds.tools"), keywords: "utilities tools shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.wrench, isIcon: true },
        { label: I18n.t("settings.binds.screenshot"), keywords: "capture screen shortcut print", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.camera, isIcon: true },
        { label: I18n.t("settings.binds.screenrecord"), keywords: "record video shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.videoCamera, isIcon: true },
        { label: I18n.t("settings.binds.lens"), keywords: "magnifier zoom shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.magnifyingGlass, isIcon: true },
        { label: I18n.t("settings.binds.reload"), keywords: "refresh restart shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.arrowCounterClockwise, isIcon: true },
        { label: I18n.t("settings.binds.quit"), keywords: "exit close shortcut", section: 6, subSection: "", subLabel: I18n.t("settings.binds"), icon: Icons.signOut, isIcon: true },
        
        // --- System ---
        { label: I18n.t("settings.system"), keywords: "hardware info resources cpu ram", section: 7, subSection: "", subLabel: I18n.t("settings.system"), icon: Icons.circuitry, isIcon: true },
        
        // System > Prefixes
        { label: I18n.t("settings.system.prefixes"), keywords: "shortcuts launcher quick actions", section: 7, subSection: "prefixes", subLabel: I18n.t("settings.system"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.system.clipboard_prefix"), keywords: "cc copy paste launcher", section: 7, subSection: "prefixes", subLabel: I18n.t("settings.system"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.system.emoji_prefix"), keywords: "ee picker launcher", section: 7, subSection: "prefixes", subLabel: I18n.t("settings.system"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.system.tmux_prefix"), keywords: "tt terminal launcher", section: 7, subSection: "prefixes", subLabel: I18n.t("settings.system"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.system.wallpapers_prefix"), keywords: "ww background launcher", section: 7, subSection: "prefixes", subLabel: I18n.t("settings.system"), icon: Icons.keyboard, isIcon: true },
        { label: I18n.t("settings.system.notes_prefix"), keywords: "nn note launcher", section: 7, subSection: "prefixes", subLabel: I18n.t("settings.system"), icon: Icons.keyboard, isIcon: true },
        
        // System > Clipboard
        { label: "Move to /tmp", keywords: "clipboard history tmpfs volatile reboot wipe encrypted", section: 7, subSection: "clipboard", subLabel: "System > Clipboard", icon: Icons.clipboard, isIcon: true },
        
        // System > Weather
        { label: I18n.t("settings.system.weather_location"), keywords: "city country place gps", section: 7, subSection: "weather", subLabel: I18n.t("settings.system"), icon: Icons.mapPin, isIcon: true },
        { label: I18n.t("settings.system.temperature_unit"), keywords: "celsius fahrenheit scale", section: 7, subSection: "weather", subLabel: I18n.t("settings.system"), icon: Icons.thermometer, isIcon: true },

        // System > Performance
        { label: I18n.t("settings.system.blur_transition"), keywords: "animation speed performance effect", section: 7, subSection: "performance", subLabel: I18n.t("settings.system"), icon: Icons.lightning, isIcon: true },
        { label: I18n.t("settings.system.window_preview"), keywords: "thumbnail overview alt-tab", section: 7, subSection: "performance", subLabel: I18n.t("settings.system"), icon: Icons.windowsLogo, isIcon: true },
        { label: I18n.t("settings.system.wavy_line"), keywords: "animated wave effect performance", section: 7, subSection: "performance", subLabel: I18n.t("settings.system"), icon: Icons.lightning, isIcon: true },
        
        // System > Resources
        { label: I18n.t("settings.system.system_resources"), keywords: "cpu ram memory usage monitor", section: 7, subSection: "resources", subLabel: I18n.t("settings.system"), icon: Icons.circuitry, isIcon: true },
        
        // System > Idle
        { label: I18n.t("settings.system.idle_settings"), keywords: "screen lock timeout sleep suspend", section: 7, subSection: "idle", subLabel: I18n.t("settings.system"), icon: Icons.moon, isIcon: true },
        { label: I18n.t("settings.system.lock_command"), keywords: "ambxst lock screen idle", section: 7, subSection: "idle", subLabel: I18n.t("settings.system"), icon: Icons.moon, isIcon: true },
        { label: I18n.t("settings.system.before_sleep"), keywords: "loginctl lock-session idle", section: 7, subSection: "idle", subLabel: I18n.t("settings.system"), icon: Icons.moon, isIcon: true },
        { label: I18n.t("settings.system.after_sleep"), keywords: "screen on resume idle", section: 7, subSection: "idle", subLabel: I18n.t("settings.system"), icon: Icons.moon, isIcon: true },
        { label: I18n.t("settings.system.idle_listener"), keywords: "timeout brightness screen off suspend", section: 7, subSection: "idle", subLabel: I18n.t("settings.system"), icon: Icons.moon, isIcon: true },
        
        // --- Compositor ---
        { label: I18n.t("settings.compositor"), keywords: "compositor window manager wm", section: 8, subSection: "", subLabel: I18n.t("settings.compositor"), icon: Icons.compositor, isIcon: true },
        
        // Compositor > AxctlService > General
        { label: I18n.t("settings.compositor.border_size"), keywords: "width thickness stroke", section: 8, subSection: "general", subLabel: I18n.t("settings.compositor"), icon: Icons.frameCorners, isIcon: true },
        { label: I18n.t("settings.compositor.window_gaps"), keywords: "spacing margin padding", section: 8, subSection: "general", subLabel: I18n.t("settings.compositor"), icon: Icons.squaresFour, isIcon: true },
        
        // Compositor > AxctlService > Colors
        { label: I18n.t("settings.compositor.border_colors"), keywords: "active inactive focus", section: 8, subSection: "colors", subLabel: I18n.t("settings.compositor"), icon: Icons.palette, isIcon: true },

        // Compositor > AxctlService > Shadows
        { label: I18n.t("settings.compositor.shadows_enabled"), keywords: "toggle on off", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.sync_shadow_color"), keywords: "match border", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.compositor.sync_shadow_opacity"), keywords: "match border alpha", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.shadow_range"), keywords: "blur radius size", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.circle, isIcon: true },
        { label: I18n.t("settings.compositor.shadow_offset"), keywords: "position x y move", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.arrowsOutSimple, isIcon: true },
        { label: I18n.t("settings.compositor.shadow_power"), keywords: "strength render intensity", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.lightning, isIcon: true },
        { label: I18n.t("settings.compositor.shadow_scale"), keywords: "zoom resize", section: 8, subSection: "shadows", subLabel: I18n.t("settings.compositor"), icon: Icons.cornersOut, isIcon: true },

        // Compositor > AxctlService > Blur
        { label: I18n.t("settings.compositor.blur_enabled"), keywords: "toggle on off transparency", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_size"), keywords: "radius amount", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.circle, isIcon: true },
        { label: I18n.t("settings.compositor.blur_passes"), keywords: "quality iterations", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.circle, isIcon: true },
        { label: I18n.t("settings.compositor.blur_xray"), keywords: "transparency see through", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_new_optimizations"), keywords: "performance speed", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.lightning, isIcon: true },
        { label: I18n.t("settings.compositor.blur_ignore_opacity"), keywords: "transparency alpha", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_ignorealpha"), keywords: "explicit transparency", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_ignorealpha_value"), keywords: "threshold amount", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_noise"), keywords: "grain texture static", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_contrast"), keywords: "intensity difference", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_brightness"), keywords: "light dark level", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },
        { label: I18n.t("settings.compositor.blur_vibrancy"), keywords: "saturation color", section: 8, subSection: "blur", subLabel: I18n.t("settings.compositor"), icon: Icons.drop, isIcon: true },

        // --- Ambxst / Shell ---
        { label: I18n.t("settings.ambxst"), keywords: "about info credits version shell", section: 9, subSection: "", subLabel: "", icon: Qt.resolvedUrl("../../../../assets/ambxst/ambxst-icon.svg"), isIcon: false },
        
        // Ambxst > Bar
        { label: I18n.t("settings.shell.bar_entry"), keywords: "panel taskbar top bottom", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.bar_position"), keywords: "top bottom left right edge", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.launcher_icon"), keywords: "logo symbol path", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.launcher_icon_tint"), keywords: "color theme", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.shell.launcher_icon_full_tint"), keywords: "monochrome color", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.palette, isIcon: true },
        { label: I18n.t("settings.shell.launcher_icon_size"), keywords: "width height pixels", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.pill_style"), keywords: "squished roundness radius bar", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.firefox_player"), keywords: "browser media music", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.bar_autohide"), keywords: "autohide hide show reveal", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.pinned_on_startup"), keywords: "show visible default", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.hover_to_reveal"), keywords: "mouse show hide edge", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.hover_region_height"), keywords: "pixels trigger area", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.show_pin_button"), keywords: "toggle pin unpin", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.available_on_fullscreen"), keywords: "overlay game video", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.show_running_indicators"), keywords: "dots active apps", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.show_overview_button"), keywords: "workspace switcher", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.bar_screens"), keywords: "monitor display eDP", section: 9, subSection: "bar", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        
        // Ambxst > Notch
        { label: I18n.t("settings.shell.notch_entry"), keywords: "island dynamic island center", section: 9, subSection: "notch", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        
        // Ambxst > Workspaces
        { label: I18n.t("settings.shell.workspaces_entry"), keywords: "virtual desktop spaces", section: 9, subSection: "workspaces", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.workspaces_shown"), keywords: "number count visible", section: 9, subSection: "workspaces", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.show_app_icons"), keywords: "application thumbnail workspace", section: 9, subSection: "workspaces", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.always_show_numbers"), keywords: "workspace label index", section: 9, subSection: "workspaces", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.always_show_numbers"), keywords: "workspace label index", section: 9, subSection: "workspaces", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.dynamic_workspaces"), keywords: "auto add remove flexible", section: 9, subSection: "workspaces", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        
        // Ambxst > Overview
        { label: I18n.t("settings.shell.overview_entry"), keywords: "expose mission control windows", section: 9, subSection: "overview", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.overview_rows"), keywords: "grid layout vertical", section: 9, subSection: "overview", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.overview_columns"), keywords: "grid layout horizontal", section: 9, subSection: "overview", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.overview_scale"), keywords: "zoom size preview", section: 9, subSection: "overview", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        { label: I18n.t("settings.shell.overview_workspace_spacing"), keywords: "gap margin distance", section: 9, subSection: "overview", subLabel: I18n.t("settings.ambxst"), icon: Icons.squaresFour, isIcon: true },
        
        // Ambxst > Dock
        { label: I18n.t("settings.shell.dock_entry"), keywords: "taskbar launcher apps favorites", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_enabled"), keywords: "show hide toggle", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_mode"), keywords: "default floating integrated style", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_position"), keywords: "left bottom right edge", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_height"), keywords: "size thickness pixels", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_icon_size"), keywords: "width height pixels apps", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_spacing"), keywords: "gap between icons", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_margin"), keywords: "edge distance offset", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.dock_hover_region_height"), keywords: "trigger area pixels", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.pinned_on_startup"), keywords: "show visible default", section: 9, subSection: "dock", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        
        // Ambxst > Lockscreen
        { label: I18n.t("settings.shell.lockscreen_entry"), keywords: "lock screen password login", section: 9, subSection: "lockscreen", subLabel: I18n.t("settings.ambxst"), icon: Icons.lock, isIcon: true },
        
        // Ambxst > Desktop
        { label: I18n.t("settings.shell.desktop_entry"), keywords: "icons wallpaper home", section: 9, subSection: "desktop", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.desktop_enabled"), keywords: "show hide icons toggle", section: 9, subSection: "desktop", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.launcher_icon_size"), keywords: "width height pixels", section: 9, subSection: "desktop", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.desktop_vertical_spacing"), keywords: "gap margin", section: 9, subSection: "desktop", subLabel: I18n.t("settings.ambxst"), icon: Icons.layout, isIcon: true },
        { label: I18n.t("settings.shell.desktop_text_color"), keywords: "label font", section: 9, subSection: "desktop", subLabel: I18n.t("settings.ambxst"), icon: Icons.palette, isIcon: true },
        
        // Ambxst > System
        { label: I18n.t("settings.shell.system_entry"), keywords: "config settings ambxst", section: 9, subSection: "system", subLabel: I18n.t("settings.ambxst"), icon: Icons.circuitry, isIcon: true },

        // --- System Sounds ---
        { label: "System Sounds", keywords: "audio notification sound cue alert volume mute theme portal turret", section: 11, subSection: "", subLabel: "", icon: Icons.speakerHigh, isIcon: true },
        // --- Turret Assistant ---
        { label: "Turret Assistant", keywords: "voice assistant turret speech microphone stt tts local ai kokoro whisper", section: 13, subSection: "", subLabel: "", icon: Icons.robot, isIcon: true },
        { label: "Speaking Voice", keywords: "voice tts kokoro piper speak rate speed", section: 13, subSection: "", subLabel: "Turret Assistant", icon: Icons.speakerHigh, isIcon: true },
        { label: "Microphone", keywords: "mic input capture device speech recognition whisper", section: 13, subSection: "", subLabel: "Turret Assistant", icon: Icons.mic, isIcon: true },
        { label: "Assistant Memory", keywords: "memory remember forget recall facts preferences privacy", section: 13, subSection: "", subLabel: "Turret Assistant", icon: Icons.robot, isIcon: true },
        { label: "Sound Theme", keywords: "default portal turret theme cues", section: 11, subSection: "", subLabel: "System Sounds", icon: Icons.speakerHigh, isIcon: true },
        { label: "Notification Sound", keywords: "notification critical low alert cue path test mute", section: 11, subSection: "", subLabel: "System Sounds", icon: Icons.bell, isIcon: true },
        { label: "Volume", keywords: "sound loud quiet level percentage", section: 11, subSection: "", subLabel: "System Sounds", icon: Icons.speakerHigh, isIcon: true }
    ]

    property var items: staticItems.concat(dynamicItems)

    function addDynamicItems(newItems) {
        // Simple deduplication based on label + section
        let currentLabels = new Set(items.map(i => i.section + ":" + i.label));
        let uniqueNew = [];
        
        for (let i = 0; i < newItems.length; i++) {
            let item = newItems[i];
            let key = item.section + ":" + item.label;
            if (!currentLabels.has(key)) {
                uniqueNew.push(item);
                currentLabels.add(key);
            }
        }
        
        if (uniqueNew.length > 0) {
            dynamicItems = dynamicItems.concat(uniqueNew);
        }
    }
}

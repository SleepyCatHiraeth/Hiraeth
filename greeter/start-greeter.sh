#!/bin/sh
# greetd's default_session command. The greeter user has no home directory,
# so Hyprland and Quickshell get their writable dirs under /var/cache.
base=/var/cache/ambxst-greeter
export XDG_CACHE_HOME="$base/cache"
export XDG_STATE_HOME="$base/state"
export XDG_DATA_HOME="$base/data"
export XDG_CONFIG_HOME="$base/config"
mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
exec start-hyprland -- -c /usr/share/ambxst-greeter/hyprland.lua

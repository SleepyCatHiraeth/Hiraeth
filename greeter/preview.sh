#!/bin/sh
# Preview the greeter in the current session (mock mode, nothing is installed).
#   ./preview.sh                 use the snapshot the shell publishes
#   ./preview.sh <wallpaper>     same, but with another image, GIF or video
# Escape quits; the password "fail" shows the error path, anything else succeeds.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src=/var/lib/ambxst-greeter
[ -f "$src/theme.json" ] || src=/var/tmp/ambxst-greeter
if [ -n "$1" ]; then
    dir=$(mktemp -d)
    trap 'rm -rf "$dir"' EXIT
    cp "$src"/colors.json "$src"/avatar.png "$dir"/ 2>/dev/null || true
    ext=$(printf '%s' "${1##*.}" | tr 'A-Z' 'a-z')
    cp -- "$1" "$dir/wallpaper.$ext"
    sed "s/\"wallpaper\":\"[^\"]*\"/\"wallpaper\":\"wallpaper.$ext\"/" "$src/theme.json" > "$dir/theme.json"
    src=$dir
fi
AMBXST_GREETER_DIR=$src GREETD_SOCK= qs -p "$here/shell.qml"

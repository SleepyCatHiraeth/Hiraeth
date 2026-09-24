#!/bin/bash
# Installs the AMBXST greeter and switches the display manager from SDDM to
# greetd. Run as root:  pkexec greeter/install.sh <user>
#
# Reversible with greeter/uninstall.sh. SDDM stays installed; only the
# enabled service changes. A snapper pre/post pair brackets the change.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
user=${1:-}
[ "$(id -u)" -eq 0 ] || { echo "run as root (pkexec $0 <user>)" >&2; exit 1; }
[ -n "$user" ] && id "$user" >/dev/null 2>&1 || { echo "usage: $0 <user>" >&2; exit 1; }
home=$(getent passwd "$user" | cut -d: -f6)
hypr_conf="$home/.config/hypr/hyprland.lua"

for cmd in qs start-hyprland hyprctl; do
    command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }
done
[ -f "$hypr_conf" ] || { echo "missing $hypr_conf (monitor lines are copied from it)" >&2; exit 1; }

share=/usr/share/ambxst-greeter
snap_pre=""
if command -v snapper >/dev/null; then
    snap_pre=$(snapper -c root create -t pre -p -d "ambxst-greeter install" -c number)
    echo "snapper pre snapshot: $snap_pre"
fi

pacman -S --needed --noconfirm greetd

# Greeter files. The compositor config gets the user's monitor blocks
# appended so both compositors set identical modes.
install -d -m 755 "$share"
install -m 644 "$src"/*.qml "$src"/Splashes.js "$share"/
install -m 755 "$src"/start-greeter.sh "$src"/session.sh "$share"/
install -m 755 "$src"/uninstall.sh "$share"/
{
    cat "$src"/hyprland.lua
    awk '/^hl\.monitor\(\{/{p=1} p{print} p&&/^\}\)/{p=0; print ""}' "$hypr_conf"
} > "$share"/hyprland.lua
chmod 644 "$share"/hyprland.lua

# Snapshot directory, written by the user's shell, read by the greeter.
install -d -m 755 -o "$user" -g "$(id -gn "$user")" /var/lib/ambxst-greeter
if [ -d /var/tmp/ambxst-greeter ]; then
    cp -a /var/tmp/ambxst-greeter/. /var/lib/ambxst-greeter/
    chown -R "$user:$(id -gn "$user")" /var/lib/ambxst-greeter
fi

# Writable dirs for the greeter user, which has no home.
install -d -m 700 -o greeter -g greeter /var/cache/ambxst-greeter
usermod -aG video greeter

# greetd config, keeping whatever was there.
install -d -m 755 /etc/greetd
if [ -f /etc/greetd/config.toml ] && ! grep -q ambxst-greeter /etc/greetd/config.toml; then
    cp -a /etc/greetd/config.toml "/etc/greetd/config.toml.pre-ambxst-$(date +%Y%m%d-%H%M%S)"
fi
cat > /etc/greetd/config.toml <<'EOF'
# AMBXST greeter (installed by ambxst greeter/install.sh)
[terminal]
vt = 1

[default_session]
command = "/usr/share/ambxst-greeter/start-greeter.sh"
user = "greeter"
EOF

systemctl disable sddm.service
systemctl enable greetd.service

if [ -n "$snap_pre" ]; then
    snap_post=$(snapper -c root create -t post --pre-number "$snap_pre" -p -d "ambxst-greeter install" -c number)
    echo "snapper post snapshot: $snap_post"
fi

cat <<EOF

AMBXST greeter installed. It takes over at the next boot.
If the login screen does not come up: Ctrl+Alt+F3, log in, then
    sudo $share/uninstall.sh
EOF

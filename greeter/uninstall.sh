#!/bin/bash
# Reverses install.sh: switches back to SDDM and removes the greeter files.
# greetd itself stays installed (remove it with pacman if wanted).
#   sudo /usr/share/ambxst-greeter/uninstall.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

systemctl disable greetd.service 2>/dev/null || true
systemctl enable sddm.service

# Restore the greetd config that was there before, if any.
latest=$(ls -1t /etc/greetd/config.toml.pre-ambxst-* 2>/dev/null | head -1 || true)
if [ -n "$latest" ]; then
    cp -a "$latest" /etc/greetd/config.toml
elif grep -qs ambxst-greeter /etc/greetd/config.toml; then
    rm -f /etc/greetd/config.toml
fi

rm -rf /var/cache/ambxst-greeter
# The snapshot dir holds only public theme data; keep it so a reinstall
# has a look straight away. The shell falls back to /var/tmp without it.
rm -rf /usr/share/ambxst-greeter

echo "Switched back to SDDM. Reboot to use it."

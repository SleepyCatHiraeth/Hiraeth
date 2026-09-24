#!/bin/sh
# Starts the user session the way SDDM's wayland-session does, so the
# environment (profile, login shell) is the same as before.
#   session.sh <command> [args...]
case $SHELL in
    */bash|*/zsh)
        exec "$SHELL" --login -c 'exec "$@"' - "$@"
        ;;
    */fish)
        [ -f /etc/profile ] && . /etc/profile
        [ -f "$HOME/.profile" ] && . "$HOME/.profile"
        exec "$SHELL" --login -c 'exec $argv' "$@"
        ;;
    *)
        [ -f /etc/profile ] && . /etc/profile
        [ -f "$HOME/.profile" ] && . "$HOME/.profile"
        exec "$@"
        ;;
esac

#!/usr/bin/env bash
set -euo pipefail

if (($#)); then
    exec "$@"
fi

password_file=/run/secrets/pi-coder/password
if [[ ! -r "$password_file" ]]; then
    printf 'Cockpit login requires a password mounted at %s.\n' "$password_file" >&2
    exit 1
fi
password="$(cat "$password_file")"
if [[ -z "$password" || "$password" == *$'\n'* || "$password" == *$'\r'* ]]; then
    printf 'Cockpit login password must be nonempty and contain no line breaks.\n' >&2
    exit 1
fi
printf 'pi:%s\n' "$password" | chpasswd
unset password
ssh-keygen -A
install -d -m 0755 /run/dbus
dbus-uuidgen --ensure=/etc/machine-id

exec /usr/sbin/init

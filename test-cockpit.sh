#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: test-cockpit.sh IMAGE}"
temporary_dir="$(mktemp -d)"
container="pi-coder-cockpit-test-$$"
cleanup() {
    docker rm --force "$container" >/dev/null 2>&1 || true
    rm -f "$temporary_dir/password" "$temporary_dir/auth" "$temporary_dir/cookies"
    rmdir "$temporary_dir"
}
trap cleanup EXIT

if docker run --rm "$image"; then
    printf 'Startup unexpectedly succeeded without a login Secret.\n' >&2
    exit 1
fi

umask 077
password="$(openssl rand -hex 32)"
printf '%s' "$password" > "$temporary_dir/password"
printf 'user = "pi:%s"\n' "$password" > "$temporary_dir/auth"
unset password
docker run --detach --name "$container" \
    --publish 127.0.0.1::9090 \
    --mount "type=bind,src=$temporary_dir/password,dst=/run/secrets/pi-coder/password,readonly" \
    "$image" >/dev/null
address="$(docker port "$container" 9090/tcp)"
base_url="http://$address"

ready=false
for attempt in {1..30}; do
    if curl --fail --silent "$base_url/ping" >/dev/null; then
        ready=true
        break
    fi
    sleep 1
done
if [[ "$ready" != true ]]; then
    docker logs "$container"
    printf 'Cockpit did not become ready.\n' >&2
    exit 1
fi

curl --fail --silent --show-error \
    --config "$temporary_dir/auth" \
    --cookie-jar "$temporary_dir/cookies" \
    --header 'Host: pi.ergoshear.dev' \
    --header 'Origin: https://pi.ergoshear.dev' \
    --header 'X-Forwarded-Proto: https' \
    "$base_url/cockpit/login" |
    python3 -c '
import json
import sys
response = json.load(sys.stdin)
assert isinstance(response["csrf-token"], str) and response["csrf-token"]
'
[[ "$(docker exec --user pi "$container" sudo -n id -u)" == 0 ]]
docker exec --user pi "$container" pi --version
docker exec "$container" python3 -c '
from pathlib import Path
listeners = [
    line.split()[1]
    for line in Path("/proc/net/tcp").read_text().splitlines()[1:]
    if line.split()[3] == "0A" and line.split()[1].endswith(":0016")
]
assert listeners == ["0100007F:0016"], listeners
'
printf 'Cockpit login, loopback SSH, Pi CLI, and passwordless sudo checks passed.\n'

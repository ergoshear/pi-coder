#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: test-cockpit.sh IMAGE}"
temporary_dir="$(mktemp -d)"
container="pi-coder-cockpit-test-$$"
cleanup() {
    if [[ $? != 0 ]]; then
        docker logs "$container" 2>/dev/null || true
        docker exec "$container" journalctl --no-pager --lines=100 2>/dev/null || true
    fi
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
    --privileged --cgroupns=host \
    --tmpfs /run --tmpfs /tmp \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --publish 127.0.0.1::9090 \
    --mount "type=bind,src=$temporary_dir/password,dst=/run/secrets/pi-coder/password,readonly" \
    "$image" >/dev/null
address="$(docker port "$container" 9090/tcp)"
base_url="http://$address"

ready=false
for _attempt in {1..60}; do
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
    --dump-header "$temporary_dir/cookies" \
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
python3 "$(dirname "$0")/test-session.py" "$base_url" "$temporary_dir/cookies"
[[ "$(docker exec "$container" cat /proc/1/comm)" == systemd ]]
docker exec "$container" systemctl is-active cockpit.socket sshd.service dbus.service
[[ "$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --user pi:incorrect-password \
    --header 'Host: pi.ergoshear.dev' \
    --header 'Origin: https://pi.ergoshear.dev' \
    --header 'X-Forwarded-Proto: https' \
    "$base_url/cockpit/login")" == 401 ]]
[[ "$(docker exec --user pi "$container" sudo -n id -u)" == 0 ]]
docker exec --user pi "$container" pi --version
for account in pi root; do
    docker exec --user "$account" "$container" node -e '
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const agentDirectory = path.join(os.homedir(), ".pi", "agent");
const models = JSON.parse(fs.readFileSync(path.join(agentDirectory, "models.json"), "utf8"));
const settings = JSON.parse(fs.readFileSync(path.join(agentDirectory, "settings.json"), "utf8"));
assert.equal(models.providers.olla.baseUrl, "https://olla.ergoshear.dev/olla/openai/v1");
assert.equal(models.providers.olla.api, "openai-completions");
assert.equal(settings.defaultProvider, "olla");
assert.equal(settings.defaultModel, "/models/gpt-oss-20b-MXFP4.gguf");
const model = models.providers.olla.models.find(model => model.id === settings.defaultModel);
assert.ok(model);
assert.equal(model.contextWindow, 65536);
assert.equal(model.maxTokens, 8192);
assert.equal(settings.compaction.reserveTokens, model.maxTokens);
assert.ok(settings.compaction.reserveTokens < model.contextWindow);
'
done
docker exec "$container" python3 -c '
from pathlib import Path
listeners = [
    line.split()[1]
    for line in Path("/proc/net/tcp").read_text().splitlines()[1:]
    if line.split()[3] == "0A" and line.split()[1].endswith(":0016")
]
assert listeners == ["0100007F:0016"], listeners
'
printf 'Systemd socket activation, Cockpit login, loopback SSH, Pi CLI, and passwordless sudo checks passed.\n'

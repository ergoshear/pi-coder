# pi-coder

Fedora 44 with the Pi coding agent and a Cockpit browser terminal. Cockpit
is installed with `dnf install cockpit` and enabled with
`systemctl enable cockpit.socket`, following the
[Fedora setup guide](https://cockpit-project.org/running#fedora).
The entrypoint starts systemd as PID 1, and Cockpit's stock socket-activated
service authenticates the local `pi` account. The `pi` account has passwordless
sudo inside the container. Root Cockpit logins and remote-host logins are disabled.

Systemd manages Cockpit, the container-local system D-Bus, and an SSH server
bound only to loopback. SSH retains its container-specific Unix PAM stack.
Use Cockpit's Terminal for the Pi workspace.

The systemd runtime requires a privileged container, writable cgroup access,
and writable temporary filesystems at `/run` and `/tmp`. The GitOps deployment
mounts the node's `/sys/fs/cgroup` read-write. This substantially weakens node
isolation: deploy only trusted workloads on a node where this access is acceptable.

The default entrypoint starts Cockpit on port 9090. Mount a nonempty login
password at `/run/secrets/pi-coder/password`; it is applied at startup and
must not be baked into the image. Missing or invalid passwords fail startup.
The GitOps deployment supplies this file from the `pi-coder-login` Secret.

TLS terminates at the ingress for `https://pi.ergoshear.dev`. Do not expose
the unencrypted container port directly to untrusted networks. Cockpit is
configured to trust the ingress's `X-Forwarded-Proto` header and accepts
WebSocket connections from that HTTPS origin.
`AllowUnencrypted` permits the ingress-to-container HTTP connection; TLS is
still required at the public ingress.

After logging in as `pi`, open Cockpit's Terminal and run `cd /workspace`
then `pi`. Terminal files are currently ephemeral and are lost when the pod
is replaced.

Explicit commands bypass the web startup for CLI use, for example:

```sh
docker run --rm -it ghcr.io/ergoshear/pi-coder:latest pi
```

## Olla Provider

The image installs `models.json` and `settings.json` under `~/.pi/agent/`
for both `pi` and root. New sessions default to provider `olla`, model `llama3`,
using `https://olla.ergoshear.dev/olla/openai/v1` and a placeholder API key.
Edit these files to select another Olla model or change the endpoint. The
Llama 3 entry assumes an 8192-token context window with 2048 output tokens;
adjust these limits to match the model and context configured on your backends.
Coding-agent tool use requires a model/backend that supports tool calls.

Rebuild and publish the image, then restart the deployment to apply these
defaults. Existing mounted home directories or saved sessions can override them.

Validate a built image with `bash test-cockpit.sh IMAGE`. This checks that
missing login credentials fail startup, correct credentials authenticate,
incorrect credentials are rejected, SSH is loopback-only, Pi is installed,
Olla defaults are installed for both accounts, and `pi` can run `sudo -n`
without a password. The test uses privileged Docker
with the same writable host cgroup mount and verifies systemd socket activation.
It also opens authenticated
WebSocket system-bus and session-control channels and executes a terminal
command for 30 seconds, catching short-lived failures after HTTP login. Pull requests run this smoke
test on the built image.
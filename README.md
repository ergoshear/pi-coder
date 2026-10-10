# pi-coder

Fedora 44 with the Pi coding agent and a Cockpit browser terminal. Cockpit
authenticates the local `pi` account through an SSH server bound only to
loopback; the container does not need systemd or privileged mode. The `pi`
account has passwordless sudo inside the container. Root Cockpit logins and
remote-host logins are disabled.

The default entrypoint starts Cockpit on port 9090. Mount a nonempty login
password at `/run/secrets/pi-coder/password`; it is applied at startup and
must not be baked into the image. Missing or invalid passwords fail startup.
The GitOps deployment supplies this file from the `pi-coder-login` Secret.

TLS terminates at the ingress for `https://pi.ergoshear.dev`. Do not expose
the unencrypted container port directly to untrusted networks. Cockpit is
configured to trust the ingress's `X-Forwarded-Proto` header and accepts
WebSocket connections from that HTTPS origin.

After logging in as `pi`, open Cockpit's Terminal and run `cd /workspace`
then `pi`. Terminal files are currently ephemeral and are lost when the pod
is replaced.

Explicit commands bypass the web startup for CLI use, for example:

```sh
docker run --rm -it ghcr.io/ergoshear/pi-coder:latest pi
```

Validate a built image with `bash test-cockpit.sh IMAGE`. This checks that
missing login credentials fail startup, correct credentials authenticate,
incorrect credentials are rejected, SSH is loopback-only, Pi is installed,
and `pi` can run `sudo -n` without a password. Pull requests run this smoke
test on the built image.
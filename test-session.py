from contextlib import closing
from http.cookies import SimpleCookie
import json
from pathlib import Path
import sys

import websocket

cookies = SimpleCookie()
for line in Path(sys.argv[2]).read_text().splitlines():
    if line.lower().startswith("set-cookie:"):
        cookies.load(line.split(":", 1)[1].strip())
cookie_header = "; ".join(f"{key}={cookie.value}" for key, cookie in cookies.items())
with closing(websocket.create_connection(
    sys.argv[1].replace("http://", "ws://").replace("https://", "wss://") + "/cockpit/socket",
    cookie=cookie_header,
    host="pi.ergoshear.dev",
    origin="https://pi.ergoshear.dev",
    header=["X-Forwarded-Proto: https"],
    subprotocols=["cockpit1"],
    timeout=15,
)) as connection:
    init = connection.recv()
    initial = json.loads(init.split("\n", 1)[1])
    assert initial["command"] == "init"
    assert not initial.get("problem"), initial.get("problem")
    connection.send('\n{"command":"init","version":1}')
    connection.send("\n" + json.dumps({
        "command": "open", "channel": "system-bus",
        "payload": "dbus-json3", "bus": "system", "name": "org.freedesktop.DBus",
    }))
    connection.send("\n" + json.dumps({
        "command": "open", "channel": "session",
        "payload": "session-control",
    }))
    connection.send("\n" + json.dumps({
        "command": "open",
        "channel": "test",
        "payload": "stream",
        "spawn": ["/bin/sh", "-c", "printf cockpit-terminal-ok"],
    }))
    output = ""
    ready_channels = set()
    while True:
        frame = connection.recv()
        assert frame, "Cockpit WebSocket disconnected"
        channel, payload = frame.split("\n", 1)
        if channel == "test":
            output += payload
        elif not channel:
            control = json.loads(payload)
            if control["command"] == "ready":
                ready_channels.add(control["channel"])
            if control["command"] == "close":
                assert control.get("channel") == "test", control
                assert not control.get("problem"), control
                assert control.get("exit-status") == 0, control
                break
    assert output == "cockpit-terminal-ok", output
    assert {"system-bus", "session", "test"} <= ready_channels, ready_channels
print("Authenticated Cockpit system-bus, session-control, and terminal checks passed.")

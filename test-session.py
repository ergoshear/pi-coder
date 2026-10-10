import http.cookiejar
import json
import sys

import websocket

cookies = http.cookiejar.MozillaCookieJar(sys.argv[2])
cookies.load(ignore_discard=True, ignore_expires=True)
cookie_header = "; ".join(f"{cookie.name}={cookie.value}" for cookie in cookies)
with websocket.create_connection(
    sys.argv[1].replace("http://", "ws://") + "/cockpit/socket",
    cookie=cookie_header,
    host="pi.ergoshear.dev",
    origin="https://pi.ergoshear.dev",
    header=["X-Forwarded-Proto: https"],
    subprotocols=["cockpit1"],
    timeout=15,
) as connection:
    init = connection.recv()
    assert json.loads(init.split("\n", 1)[1])["command"] == "init"
    connection.send('\n{"command":"init","version":1}')
    connection.send("\n" + json.dumps({
        "command": "open",
        "channel": "test",
        "payload": "stream",
        "spawn": ["/bin/sh", "-c", "printf cockpit-terminal-ok"],
    }))
    output = ""
    while True:
        frame = connection.recv()
        assert frame, "Cockpit WebSocket disconnected"
        channel, payload = frame.split("\n", 1)
        if channel == "test":
            output += payload
        elif not channel:
            control = json.loads(payload)
            if control["command"] == "close":
                assert control.get("channel") == "test", control
                assert not control.get("problem"), control
                assert control.get("exit-status") == 0, control
                break
    assert output == "cockpit-terminal-ok", output
print("Authenticated Cockpit WebSocket terminal command passed.")

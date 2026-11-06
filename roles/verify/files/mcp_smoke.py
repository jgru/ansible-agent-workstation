"""Start an MCP server over stdio, do the handshake and print its tools."""

import json
import subprocess
import sys
import tempfile


def main():
    with tempfile.TemporaryFile("w+") as stderr:
        server = subprocess.Popen(
            sys.argv[1:],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=stderr,
            text=True,
        )

        def send(message):
            server.stdin.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
            server.stdin.flush()

        def receive():
            line = server.stdout.readline()
            if not line:
                stderr.seek(0)
                sys.exit("server exited during the handshake:\n" + stderr.read())
            return json.loads(line)["result"]

        try:
            send({
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "clientInfo": {"name": "verify", "version": "1"},
                },
            })
            receive()
            send({"method": "notifications/initialized"})
            send({"id": 2, "method": "tools/list"})
            print(" ".join(tool["name"] for tool in receive()["tools"]))
        finally:
            server.kill()


main()

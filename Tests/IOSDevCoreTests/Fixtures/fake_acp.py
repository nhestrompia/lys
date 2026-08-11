import json
import sys


def send(payload):
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    try:
        request = json.loads(line)
        request_id = request.get("id")
        method = request.get("method")
        if method == "initialize":
            result = {
                "protocolVersion": 1,
                "agentInfo": {"name": "iosdev-fake-agent", "version": "1"},
                "agentCapabilities": {},
            }
        elif method == "session/new":
            result = {"sessionId": "fake-session"}
        elif method == "session/prompt":
            send({
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": "fake-session",
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": "Fake journey complete."},
                    },
                },
            })
            result = {"stopReason": "end_turn"}
        else:
            send({
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": "Unsupported fake method"},
            })
            continue
        send({"jsonrpc": "2.0", "id": request_id, "result": result})
    except Exception as error:
        send({
            "jsonrpc": "2.0",
            "id": None,
            "error": {"code": -32603, "message": str(error)},
        })

#!/usr/bin/env python3
"""
vibing-session-logger.py — Log all terminal session activity to a file.

Usage:
    pip install sseclient-py requests
    python session-logger.py --token YOUR_TOKEN --output session.log

Creates an audit trail of everything your AI agents do.
"""

import argparse
import base64
import json
import sys
from datetime import datetime

import requests
import sseclient


def main():
    parser = argparse.ArgumentParser(description="Log Vibing session activity")
    parser.add_argument("--api", default="http://127.0.0.1:8767/api/v1")
    parser.add_argument("--token", required=True, help="Hook API auth token")
    parser.add_argument("--output", default="vibing-session.log", help="Output log file")
    parser.add_argument("--session", help="Only log a specific session ID")
    args = parser.parse_args()

    headers = {"Authorization": f"Bearer {args.token}"}

    try:
        resp = requests.get(
            f"{args.api}/events",
            headers=headers,
            stream=True,
            timeout=None,
        )
        resp.raise_for_status()
    except requests.ConnectionError:
        print("Error: Cannot connect. Is vibing-server running with --hook-api?")
        sys.exit(1)

    print(f"Logging to {args.output} ...\n")

    with open(args.output, "a") as f:
        for event in sseclient.SSEClient(resp).events():
            try:
                data = json.loads(event.data)
            except json.JSONDecodeError:
                continue

            session_id = data.get("session_id", "?")
            if args.session and session_id != args.session:
                continue

            event_type = data["type"]
            ts = datetime.fromtimestamp(data["timestamp"]).strftime("%Y-%m-%d %H:%M:%S")

            if event_type == "on_output":
                raw = base64.b64decode(data["data_base64"]).decode("utf-8", errors="replace")
                line = f"[{ts}] [{session_id}] OUTPUT: {raw}"
            elif event_type == "on_prompt":
                line = f"[{ts}] [{session_id}] PROMPT: {data['prompt']['text']}"
            elif event_type == "on_idle":
                line = f"[{ts}] [{session_id}] IDLE: {data['idle_ms']}ms"
            elif event_type == "on_error":
                line = f"[{ts}] [{session_id}] ERROR: {data['line']}"
            elif event_type == "on_session_created":
                line = f"[{ts}] [{session_id}] SESSION CREATED"
            elif event_type == "on_session_closed":
                line = f"[{ts}] [{session_id}] SESSION CLOSED"
            else:
                line = f"[{ts}] [{session_id}] {event_type}: {json.dumps(data)}"

            f.write(line + "\n")
            f.flush()
            print(f"  {line}")


if __name__ == "__main__":
    main()

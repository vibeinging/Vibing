#!/usr/bin/env python3
"""
vibing-slack-notify.py — Send Slack notifications when AI agents need attention.

Usage:
    pip install sseclient-py requests
    python slack-notify.py --token YOUR_TOKEN --slack-webhook https://hooks.slack.com/...

Notifies you when:
  - An agent needs manual approval (on_prompt)
  - An agent goes idle (on_idle) — task probably done
  - An agent encounters an error (on_error)
"""

import argparse
import json
import sys

import requests
import sseclient


def send_slack(webhook_url: str, text: str):
    requests.post(webhook_url, json={"text": text}, timeout=10)


def main():
    parser = argparse.ArgumentParser(description="Slack notifications for Vibing")
    parser.add_argument("--api", default="http://127.0.0.1:8767/api/v1")
    parser.add_argument("--token", required=True, help="Hook API auth token")
    parser.add_argument("--slack-webhook", required=True, help="Slack incoming webhook URL")
    args = parser.parse_args()

    headers = {"Authorization": f"Bearer {args.token}"}

    try:
        resp = requests.get(
            f"{args.api}/events?filter=on_prompt,on_idle,on_error",
            headers=headers,
            stream=True,
            timeout=None,
        )
        resp.raise_for_status()
    except requests.ConnectionError:
        print("Error: Cannot connect. Is vibing-server running with --hook-api?")
        sys.exit(1)

    print("Listening for events → Slack notifications...\n")

    for event in sseclient.SSEClient(resp).events():
        try:
            data = json.loads(event.data)
        except json.JSONDecodeError:
            continue

        event_type = data["type"]
        session_id = data["session_id"]

        if event_type == "on_prompt":
            prompt_text = data["prompt"]["text"]
            msg = f"🔔 *Vibing* — Session `{session_id}` needs your approval:\n> {prompt_text}"
            send_slack(args.slack_webhook, msg)
            print(f"  Notified: prompt in session {session_id}")

        elif event_type == "on_idle":
            idle_sec = data["idle_ms"] / 1000
            msg = f"💤 *Vibing* — Session `{session_id}` has been idle for {idle_sec:.0f}s. Task may be complete."
            send_slack(args.slack_webhook, msg)
            print(f"  Notified: idle in session {session_id}")

        elif event_type == "on_error":
            error_line = data["line"]
            msg = f"❌ *Vibing* — Error in session `{session_id}`:\n```{error_line}```"
            send_slack(args.slack_webhook, msg)
            print(f"  Notified: error in session {session_id}")


if __name__ == "__main__":
    main()

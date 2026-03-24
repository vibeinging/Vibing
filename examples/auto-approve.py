#!/usr/bin/env python3
"""
vibing-auto-approve.py — Auto-approve safe prompts from AI coding CLIs.

Usage:
    pip install sseclient-py requests
    python auto-approve.py --token YOUR_TOKEN

Start vibing-server with hook API enabled:
    vibing-server --bind 0.0.0.0:8765 --hook-api --hook-api-token YOUR_TOKEN
"""

import argparse
import json
import sys

import requests
import sseclient  # pip install sseclient-py

# Prompt text patterns considered safe to auto-approve
SAFE_PATTERNS = [
    "read file",
    "list directory",
    "view file",
    "search for",
    "read the file",
    "list files",
]

# Patterns that should NEVER be auto-approved
DANGEROUS_PATTERNS = [
    "delete",
    "remove",
    "drop",
    "force push",
    "rm -rf",
    "password",
    "passphrase",
    "secret",
    "credential",
]


def is_safe(prompt_text: str) -> bool:
    text = prompt_text.lower()
    if any(p in text for p in DANGEROUS_PATTERNS):
        return False
    return any(p in text for p in SAFE_PATTERNS)


def main():
    parser = argparse.ArgumentParser(description="Auto-approve safe Vibing prompts")
    parser.add_argument("--api", default="http://127.0.0.1:8767/api/v1")
    parser.add_argument("--token", required=True, help="Hook API auth token")
    parser.add_argument("--dry-run", action="store_true", help="Print decisions without acting")
    args = parser.parse_args()

    headers = {"Authorization": f"Bearer {args.token}"}

    print(f"Connecting to {args.api}/events?filter=on_prompt ...")

    try:
        resp = requests.get(
            f"{args.api}/events?filter=on_prompt",
            headers=headers,
            stream=True,
            timeout=None,
        )
        resp.raise_for_status()
    except requests.ConnectionError:
        print("Error: Cannot connect. Is vibing-server running with --hook-api?")
        sys.exit(1)

    client = sseclient.SSEClient(resp)
    print("Listening for prompts...\n")

    for event in client.events():
        try:
            data = json.loads(event.data)
        except json.JSONDecodeError:
            continue

        session_id = data["session_id"]
        prompt = data["prompt"]
        prompt_text = prompt["text"]
        prompt_kind = prompt["kind"]

        if prompt_kind == "passphrase":
            print(f"  [SKIP] Password prompt — never auto-approve")
            continue

        if is_safe(prompt_text):
            action = "APPROVE"
            if not args.dry_run:
                requests.post(
                    f"{args.api}/sessions/{session_id}/approve",
                    headers=headers,
                )
        else:
            action = "MANUAL"

        icon = "✅" if action == "APPROVE" else "⏸️"
        print(f"  {icon} [{action}] session={session_id}: {prompt_text}")


if __name__ == "__main__":
    main()

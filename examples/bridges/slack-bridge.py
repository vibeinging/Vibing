#!/usr/bin/env python3
"""
vibing-slack-bridge.py — Slack 双向桥接

功能：
  - Agent 需要确认时，发送 Slack 消息带 Approve / Reject 按钮
  - Agent 空闲、出错时发送通知
  - 点击按钮直接操作 Vibing，不用回到电脑前

使用：
  1. 创建 Slack App: https://api.slack.com/apps
     - 开启 Incoming Webhooks
     - 开启 Interactivity，Request URL 填: http://你的公网IP:9100/slack/actions
     - 安装到 workspace，拿到 Bot Token

  2. 配置环境变量：
     export VIBING_API=http://127.0.0.1:8767/api/v1
     export VIBING_TOKEN=your-vibing-hook-api-token
     export SLACK_BOT_TOKEN=xoxb-your-slack-bot-token
     export SLACK_CHANNEL=C01234ABCDE

  3. 启动：
     pip install flask requests sseclient-py
     python slack-bridge.py
"""

import json
import os
import sys
import threading

import requests
import sseclient
from flask import Flask, request, jsonify

# ── 配置 ──

VIBING_API = os.environ.get("VIBING_API", "http://127.0.0.1:8767/api/v1")
VIBING_TOKEN = os.environ.get("VIBING_TOKEN", "")
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "")
SLACK_CHANNEL = os.environ.get("SLACK_CHANNEL", "")
BRIDGE_PORT = int(os.environ.get("BRIDGE_PORT", "9100"))

if not VIBING_TOKEN or not SLACK_BOT_TOKEN or not SLACK_CHANNEL:
    print("Error: set VIBING_TOKEN, SLACK_BOT_TOKEN, SLACK_CHANNEL")
    sys.exit(1)

VIBING_HEADERS = {"Authorization": f"Bearer {VIBING_TOKEN}"}
SLACK_HEADERS = {
    "Authorization": f"Bearer {SLACK_BOT_TOKEN}",
    "Content-Type": "application/json",
}

app = Flask(__name__)


# ── Slack 消息发送 ──

def slack_post(text, blocks=None):
    payload = {"channel": SLACK_CHANNEL, "text": text}
    if blocks:
        payload["blocks"] = blocks
    requests.post(
        "https://slack.com/api/chat.postMessage",
        headers=SLACK_HEADERS,
        json=payload,
        timeout=10,
    )


def slack_prompt_message(session_id, prompt_text):
    """带 Approve / Reject 按钮的交互式消息"""
    return [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Vibing* — Session `{session_id}` needs approval:\n> {prompt_text}",
            },
        },
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Approve"},
                    "style": "primary",
                    "action_id": "vibing_approve",
                    "value": session_id,
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Reject"},
                    "style": "danger",
                    "action_id": "vibing_reject",
                    "value": session_id,
                },
            ],
        },
    ]


# ── Slack 回调（点击按钮） ──

@app.route("/slack/actions", methods=["POST"])
def slack_actions():
    payload = json.loads(request.form.get("payload", "{}"))
    actions = payload.get("actions", [])

    for action in actions:
        action_id = action.get("action_id", "")
        session_id = action.get("value", "")
        user = payload.get("user", {}).get("name", "someone")

        if action_id == "vibing_approve":
            requests.post(
                f"{VIBING_API}/sessions/{session_id}/approve",
                headers=VIBING_HEADERS,
                timeout=10,
            )
            return jsonify({
                "replace_original": True,
                "text": f"Approved by {user}",
            })

        elif action_id == "vibing_reject":
            requests.post(
                f"{VIBING_API}/sessions/{session_id}/reject",
                headers=VIBING_HEADERS,
                timeout=10,
            )
            return jsonify({
                "replace_original": True,
                "text": f"Rejected by {user}",
            })

    return jsonify({"ok": True})


# ── SSE 事件监听 ──

def sse_listener():
    print(f"Connecting to {VIBING_API}/events ...")
    try:
        resp = requests.get(
            f"{VIBING_API}/events?filter=on_prompt,on_idle,on_error",
            headers=VIBING_HEADERS,
            stream=True,
            timeout=None,
        )
        resp.raise_for_status()
    except requests.ConnectionError:
        print("Error: cannot connect to Vibing. Is vibing-server running with --hook-api?")
        sys.exit(1)

    print("Listening for Vibing events → Slack ...")

    for event in sseclient.SSEClient(resp).events():
        try:
            data = json.loads(event.data)
        except json.JSONDecodeError:
            continue

        event_type = data.get("type")
        session_id = data.get("session_id", "?")

        if event_type == "on_prompt":
            prompt_text = data["prompt"]["text"]
            # 密码类不发到 Slack
            if data["prompt"].get("kind") == "passphrase":
                continue
            blocks = slack_prompt_message(session_id, prompt_text)
            slack_post(f"Session {session_id} needs approval", blocks=blocks)

        elif event_type == "on_idle":
            idle_sec = data.get("idle_ms", 0) / 1000
            slack_post(f"Session `{session_id}` idle for {idle_sec:.0f}s — task may be done.")

        elif event_type == "on_error":
            line = data.get("line", "")
            slack_post(f"Session `{session_id}` error:\n```{line}```")


# ── 启动 ──

if __name__ == "__main__":
    # SSE 监听跑在后台线程
    t = threading.Thread(target=sse_listener, daemon=True)
    t.start()

    print(f"Slack bridge running on :{BRIDGE_PORT}")
    print(f"  Slack callback URL: http://YOUR_IP:{BRIDGE_PORT}/slack/actions")
    app.run(host="0.0.0.0", port=BRIDGE_PORT)

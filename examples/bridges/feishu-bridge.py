#!/usr/bin/env python3
"""
vibing-feishu-bridge.py — 飞书双向桥接

功能：
  - Agent 需要确认时，发送飞书卡片消息带 批准 / 拒绝 按钮
  - Agent 空闲、出错时发送通知
  - 点击按钮直接操作 Vibing

使用：
  1. 创建飞书自建应用: https://open.feishu.cn/app
     - 添加机器人能力
     - 事件订阅里添加回调 URL: http://你的公网IP:9100/feishu/actions
     - 获取 App ID 和 App Secret

  2. 配置环境变量：
     export VIBING_API=http://127.0.0.1:8767/api/v1
     export VIBING_TOKEN=your-vibing-hook-api-token
     export FEISHU_APP_ID=cli_xxxxx
     export FEISHU_APP_SECRET=xxxxx
     export FEISHU_CHAT_ID=oc_xxxxx

  3. 启动：
     pip install flask requests sseclient-py
     python feishu-bridge.py
"""

import json
import os
import sys
import threading
import time

import requests
import sseclient
from flask import Flask, request, jsonify

# ── 配置 ──

VIBING_API = os.environ.get("VIBING_API", "http://127.0.0.1:8767/api/v1")
VIBING_TOKEN = os.environ.get("VIBING_TOKEN", "")
FEISHU_APP_ID = os.environ.get("FEISHU_APP_ID", "")
FEISHU_APP_SECRET = os.environ.get("FEISHU_APP_SECRET", "")
FEISHU_CHAT_ID = os.environ.get("FEISHU_CHAT_ID", "")
BRIDGE_PORT = int(os.environ.get("BRIDGE_PORT", "9100"))

if not VIBING_TOKEN or not FEISHU_APP_ID or not FEISHU_APP_SECRET or not FEISHU_CHAT_ID:
    print("Error: set VIBING_TOKEN, FEISHU_APP_ID, FEISHU_APP_SECRET, FEISHU_CHAT_ID")
    sys.exit(1)

VIBING_HEADERS = {"Authorization": f"Bearer {VIBING_TOKEN}"}

app = Flask(__name__)

# ── 飞书 Token 管理 ──

_tenant_token = ""
_token_expires = 0


def get_tenant_token():
    global _tenant_token, _token_expires
    if time.time() < _token_expires - 60:
        return _tenant_token

    resp = requests.post(
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
        json={"app_id": FEISHU_APP_ID, "app_secret": FEISHU_APP_SECRET},
        timeout=10,
    )
    data = resp.json()
    _tenant_token = data.get("tenant_access_token", "")
    _token_expires = time.time() + data.get("expire", 7200)
    return _tenant_token


def feishu_headers():
    return {
        "Authorization": f"Bearer {get_tenant_token()}",
        "Content-Type": "application/json",
    }


# ── 飞书消息发送 ──

def feishu_send_text(text):
    requests.post(
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id",
        headers=feishu_headers(),
        json={
            "receive_id": FEISHU_CHAT_ID,
            "msg_type": "text",
            "content": json.dumps({"text": text}),
        },
        timeout=10,
    )


def feishu_send_prompt_card(session_id, prompt_text):
    """发送带按钮的交互式卡片"""
    card = {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": "Vibing — 需要确认"},
            "template": "orange",
        },
        "elements": [
            {
                "tag": "markdown",
                "content": f"**Session** `{session_id}`\n\n> {prompt_text}",
            },
            {
                "tag": "action",
                "actions": [
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "批准"},
                        "type": "primary",
                        "value": json.dumps({"action": "approve", "session_id": session_id}),
                    },
                    {
                        "tag": "button",
                        "text": {"tag": "plain_text", "content": "拒绝"},
                        "type": "danger",
                        "value": json.dumps({"action": "reject", "session_id": session_id}),
                    },
                ],
            },
        ],
    }

    requests.post(
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id",
        headers=feishu_headers(),
        json={
            "receive_id": FEISHU_CHAT_ID,
            "msg_type": "interactive",
            "content": json.dumps(card),
        },
        timeout=10,
    )


# ── 飞书回调（点击卡片按钮） ──

@app.route("/feishu/actions", methods=["POST"])
def feishu_actions():
    body = request.json or {}

    # 飞书 URL 验证（首次注册回调时）
    if body.get("type") == "url_verification":
        return jsonify({"challenge": body.get("challenge", "")})

    # 卡片按钮回调
    action = body.get("action", {})
    value_str = action.get("value", "{}")
    try:
        value = json.loads(value_str)
    except json.JSONDecodeError:
        return jsonify({"ok": True})

    act = value.get("action", "")
    session_id = value.get("session_id", "")
    operator = body.get("operator", {}).get("open_id", "someone")

    if act == "approve":
        requests.post(
            f"{VIBING_API}/sessions/{session_id}/approve",
            headers=VIBING_HEADERS,
            timeout=10,
        )
        return jsonify({"toast": {"type": "success", "content": f"已批准 Session {session_id}"}})

    elif act == "reject":
        requests.post(
            f"{VIBING_API}/sessions/{session_id}/reject",
            headers=VIBING_HEADERS,
            timeout=10,
        )
        return jsonify({"toast": {"type": "info", "content": f"已拒绝 Session {session_id}"}})

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

    print("Listening for Vibing events → 飞书 ...")

    for event in sseclient.SSEClient(resp).events():
        try:
            data = json.loads(event.data)
        except json.JSONDecodeError:
            continue

        event_type = data.get("type")
        session_id = data.get("session_id", "?")

        if event_type == "on_prompt":
            prompt_text = data["prompt"]["text"]
            if data["prompt"].get("kind") == "passphrase":
                continue
            feishu_send_prompt_card(session_id, prompt_text)

        elif event_type == "on_idle":
            idle_sec = data.get("idle_ms", 0) / 1000
            feishu_send_text(f"Session {session_id} 空闲 {idle_sec:.0f}s — 任务可能已完成")

        elif event_type == "on_error":
            line = data.get("line", "")
            feishu_send_text(f"Session {session_id} 出错:\n{line}")


# ── 启动 ──

if __name__ == "__main__":
    t = threading.Thread(target=sse_listener, daemon=True)
    t.start()

    print(f"Feishu bridge running on :{BRIDGE_PORT}")
    print(f"  Feishu callback URL: http://YOUR_IP:{BRIDGE_PORT}/feishu/actions")
    app.run(host="0.0.0.0", port=BRIDGE_PORT)

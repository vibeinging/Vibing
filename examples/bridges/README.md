# Vibing Bridges

把 Vibing 的事件桥接到 Slack、飞书等平台。双向交互 — 不只是收通知，还能在聊天里直接点按钮审批。

## 工作原理

```
Agent 问你 [y/n]
    ↓
Vibing Hook API (SSE)
    ↓
Bridge 服务
    ↓
Slack / 飞书: "Session 1 需要确认 [批准] [拒绝]"
    ↓ 你点了 [批准]
Bridge 服务
    ↓
Vibing Hook API: POST /sessions/1/approve
    ↓
Agent 继续执行
```

## Slack

```bash
# 环境变量
export VIBING_API=http://127.0.0.1:8767/api/v1
export VIBING_TOKEN=your-vibing-token
export SLACK_BOT_TOKEN=xoxb-your-bot-token
export SLACK_CHANNEL=C01234ABCDE

# 启动
pip install flask requests sseclient-py
python slack-bridge.py
```

Slack App 配置：
1. 去 https://api.slack.com/apps 创建 App
2. 开启 **Incoming Webhooks**
3. 开启 **Interactivity**，Request URL 填 `http://你的公网IP:9100/slack/actions`
4. 安装到 workspace

## 飞书

```bash
# 环境变量
export VIBING_API=http://127.0.0.1:8767/api/v1
export VIBING_TOKEN=your-vibing-token
export FEISHU_APP_ID=cli_xxxxx
export FEISHU_APP_SECRET=xxxxx
export FEISHU_CHAT_ID=oc_xxxxx

# 启动
pip install flask requests sseclient-py
python feishu-bridge.py
```

飞书应用配置：
1. 去 https://open.feishu.cn/app 创建自建应用
2. 添加 **机器人** 能力
3. 事件订阅 → 回调 URL 填 `http://你的公网IP:9100/feishu/actions`
4. 发布应用

## 自己写一个 Bridge

Bridge 就干两件事：

1. **监听** Vibing 的 SSE 事件 → 翻译成目标平台的消息格式
2. **接收** 目标平台的回调 → 翻译成 Vibing 的 REST 调用

核心代码不超过 100 行。参考 `slack-bridge.py` 或 `feishu-bridge.py` 改就行。

需要对接 Discord / Telegram / 企业微信？按同样的模式写，换一下 API 调用。

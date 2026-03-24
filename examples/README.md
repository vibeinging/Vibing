# Vibing Hook API Examples

## Bridges (Slack / 飞书)

双向桥接 — 在 Slack 或飞书里直接审批 Agent 的请求。

→ [bridges/](bridges/) — Slack Bridge、飞书 Bridge、自己写 Bridge 的指南

## Quick Start (curl only)

Start the server with Hook API enabled:

```bash
vibing-server --bind 0.0.0.0:8765 --hook-api --hook-api-token mysecret
```

### Subscribe to all events

```bash
curl -N -H "Authorization: Bearer mysecret" \
  http://127.0.0.1:8767/api/v1/events
```

### Subscribe to prompts only

```bash
curl -N -H "Authorization: Bearer mysecret" \
  "http://127.0.0.1:8767/api/v1/events?filter=on_prompt"
```

### Approve a prompt

```bash
curl -X POST -H "Authorization: Bearer mysecret" \
  http://127.0.0.1:8767/api/v1/sessions/1/approve
```

### Reject a prompt

```bash
curl -X POST -H "Authorization: Bearer mysecret" \
  http://127.0.0.1:8767/api/v1/sessions/1/reject
```

### Send arbitrary input

```bash
curl -X POST -H "Authorization: Bearer mysecret" \
  -H "Content-Type: application/json" \
  -d '{"data": "ls -la\n"}' \
  http://127.0.0.1:8767/api/v1/sessions/1/input
```

### List active sessions

```bash
curl -H "Authorization: Bearer mysecret" \
  http://127.0.0.1:8767/api/v1/sessions
```

## Python Examples

Install dependencies:

```bash
pip install sseclient-py requests
```

### auto-approve.py

Auto-approve safe prompts (file reads, directory listings), block dangerous ones (delete, force push).

```bash
python auto-approve.py --token mysecret
python auto-approve.py --token mysecret --dry-run  # preview without acting
```

### slack-notify.py

Get Slack notifications when an agent needs approval, goes idle, or errors out.

```bash
python slack-notify.py --token mysecret --slack-webhook https://hooks.slack.com/services/...
```

### session-logger.py

Log all session activity to a file for audit trail.

```bash
python session-logger.py --token mysecret --output audit.log
python session-logger.py --token mysecret --session 1  # log only session 1
```

## Build Your Own

The Hook API is a standard SSE + REST interface. Use any language:

```javascript
// Node.js example
const EventSource = require("eventsource");
const es = new EventSource("http://127.0.0.1:8767/api/v1/events", {
  headers: { Authorization: "Bearer mysecret" },
});
es.onmessage = (e) => {
  const data = JSON.parse(e.data);
  if (data.type === "on_prompt") {
    console.log(`Prompt detected: ${data.prompt.text}`);
    // auto-approve, notify, or whatever you want
  }
};
```

```go
// Go example — use r3labs/sse/v2
client := sse.NewClient("http://127.0.0.1:8767/api/v1/events")
client.Headers["Authorization"] = "Bearer mysecret"
client.Subscribe("", func(msg *sse.Event) {
    fmt.Println(string(msg.Data))
})
```

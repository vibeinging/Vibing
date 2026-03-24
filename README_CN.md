<p align="center">
  <img src="assets/vibing-logo.svg" alt="Vibing" width="120" />
</p>

<h1 align="center">Vibing</h1>

<p align="center">
  <a href="README.md">English</a> | <strong>中文</strong>
</p>

<p align="center">
  <strong>Vibe Coding. Anywhere. Anytime.</strong><br/>
  给 AI 编程 Agent 做的开源基础设施。
</p>

<p align="center">
  <img src="assets/screenshots/hero.png" alt="Vibing — macOS + iPhone" width="800" />
</p>

---

你启动了 Claude Code，它正在重写你的认证模块。写到一半，问你："auth.rs 这个文件我能改吗？[y/n]"

但你在开会。或者在买咖啡。或者在遛狗。总之你不在电脑旁边。

回来一看 — 它等了你 20 分钟。

**Vibing 就是解决这个的。** 手机上看到所有 AI agent，该批准的批准，该停的停。在哪儿都行。

```
  你的 Mac                          你的手机
 ┌────────────────┐                ┌──────────────────┐
 │ $ claude       │                │ 📋 All Sessions  │
 │ ⏳ Thinking... │    Vibing      │                  │
 │                │ ──────────►   │ ● claude  ⏳思考中│
 │ $ gemini       │   E2E加密      │ ● gemini  ✅已完成│
 │ ✅ Done.       │                │ ● aider   ⚠️等确认│
 │                │ ◄──────────   │                  │
 │ $ aider        │   你点了y      │ > aider [y/n]    │
 │ Apply? [y/n]   │                │   [✅ Yes]       │
 └────────────────┘                └──────────────────┘
```

<p align="center">
  <img src="assets/screenshots/session-list.png" alt="iPhone 上的 Session 列表" width="300" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/screenshots/mobile-terminal.png" alt="iPhone 上的终端渲染" width="300" />
</p>

## Vibing 有什么不一样

**什么 agent 都能用。** Claude Code、Gemini CLI、Aider、Copilot、Cursor、Codex — 所有的终端工具都能用。Vibing 在 PTY 层工作（就是你和终端程序之间的那根"管道"），程序完全感知不到。用什么 agent 随意，随时换。

**所有会话一个屏幕。** 3 个项目同时跑 3 个 agent？手机上全看到。不用在标签页之间切来切去猜哪个卡住了。

**不只是看 — 还能编程。** Vibing 有一个 [Hook API](#hook-api)，让你在终端数据流上构建任何东西。自动批准安全操作、捕获失控 agent、把事件发到 Slack、搞多 agent 流水线。PTY 层是一块开放的画布。

**端到端加密。** 中继是个瞎子 — 看不到你的代码。可以自己搭。

**开源。** MIT 协议，想跑就跑，想改就改，想扩展就扩展。

<p align="center">
  <img src="assets/screenshots/multi-tab.png" alt="多标签和分屏" width="700" />
</p>

## 内置功能

在 **设置 → 功能** 里开关，不用写代码。

| | |
|---|---|
| **智能自动批准** | Agent 问 "能不能读这个文件"？自动说 yes。问 "能不能 rm -rf"？自动说 no。关键词匹配，规则你定。 |
| **失控断路器** | Agent 陷入死循环？连续重复 N 次后自动 Ctrl+C。帮你省 API 额度。 |
| **密钥泄露检测** | 终端里不小心打印了 API Key 或密码？实时告警。 |
| **会话审计** | 每条命令、每次审批，全部带时间戳记录。 |
| **空闲通知** | Agent 干完了就通知你，不用自己盯着。 |

## Hook API

给喜欢折腾的人。Vibing 把终端数据流变成 HTTP 接口。

```bash
# 实时监听 AI agent 的确认提示
curl -N -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8767/api/v1/events?filter=on_prompt"

# 命令行一键批准
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8767/api/v1/sessions/1/approve

# 把任意命令行工具变成 REST API
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -d '{"command": "ls -la", "timeout_ms": 5000}' \
  http://127.0.0.1:8767/api/v1/sessions/1/exec
# → {"output": "total 32\ndrwxr-xr-x ...", "status": "completed"}
```

已经有人在上面搭了：Slack/飞书机器人（在群里直接操控终端）、费用追踪器、多 agent 编排器、会话回放工具。

→ [Hook API 文档](docs/design/2026-03-24_hook-api-design.md) · [示例脚本](examples/) · [Slack & 飞书桥接](examples/bridges/)

## 上手

### 下载客户端

| 平台 | 下载 |
|------|------|
| **macOS** | [Download](https://github.com/anthropics/vibing/releases) |
| **iOS** | App Store (coming soon) |
| **Android** | Google Play (coming soon) |

装好打开，扫码配对，就能用了。

### 多端同步

客户端默认连接我们的免费公共中继服务，开箱即用。你的数据端到端加密，中继看不到任何内容。

如果你想私有化部署，可以自建中继：

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/template/vibing-relay)
[![Deploy to Fly.io](https://img.shields.io/badge/Deploy%20to-Fly.io-blueviolet)](https://fly.io/docs/hands-on/install-flyctl/)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/anthropics/vibing)
[![Deploy on Zeabur](https://zeabur.com/button.svg)](https://zeabur.com/templates/vibing-relay)

```bash
# 或者 Docker 自建
git clone https://github.com/anthropics/vibing.git && cd vibing
cp .env.example .env   # 设置密钥
docker compose up -d
```

→ [部署文档](docs/ARCHITECTURE.md)

## 一起来搞

Vibing 还很早期。PTY 层能干的事情远不止终端同步 — 我们觉得这里面藏着很多还没人做过的东西。

### 我们接下来想做的

**Agent 记忆体** — 你的 AI agent 每次启动都从零开始，不记得上次做过什么。Vibing 坐在 PTY 层，天然能看到所有交互历史。我们想做跨会话的持久记忆：你的编码习惯、项目规范、踩过的坑 — 自动注入，让 agent 真正"认识"你。

**AI 时代的简历** — 想想看，你和 AI 的每一次交互都经过 Vibing。你怎么描述需求、怎么做技术决策、怎么 review AI 的代码 — 这些比传统简历真实 100 倍。我们想把这些交互数据变成一种新的开发者画像：不是你说你会什么，而是 AI 见证了你会什么。

**多 Agent 编排** — 一个人同时跑 5 个 agent 已经不稀奇了。但现在你得手动盯着每一个。我们想做 agent 流水线：Agent A 写完前端 → 自动触发 Agent B 写测试 → Agent C 做 code review。你定规则，Vibing 调度。

**Web 客户端** — 不是所有人都用 macOS。浏览器打开就能用，覆盖所有平台。

**插件生态** — Hook API 已经能做很多事了，但现在还得自己写脚本。我们想做一个插件市场：别人写好的自动批准规则、Slack bridge、费用追踪器 — 一键装上就能用。

### 你能帮什么

不一定要写代码。

- 用 Vibing，然后告诉我们哪里不爽 — 开个 issue 就行
- 有想法？在 Discussions 里聊
- 给你们团队搭个 bridge — Discord、Telegram、企业微信、钉钉，随便什么
- 写篇文章聊聊你的 Vibe Coding 工作流
- 给个 Star ⭐ 让更多人看到

→ [GitHub Issues](https://github.com/anthropics/vibing/issues) · [Discussions](https://github.com/anthropics/vibing/discussions)

## License

[MIT](LICENSE)

---

<p align="center">
  <strong>Vibe Coding. Anywhere. Anytime.</strong><br/>
  <sub>最好的 Vibe Coding 方式还没被发明出来 — 所以 Vibing 是开放的。</sub>
</p>

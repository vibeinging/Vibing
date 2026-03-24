<p align="center">
  <img src="assets/vibing-logo.svg" alt="Vibing" width="120" />
</p>

<h1 align="center">Vibing</h1>

<p align="center">
  <strong>English</strong> | <a href="README_CN.md">中文</a>
</p>

<p align="center">
  <strong>Vibe Coding. Anywhere. Anytime.</strong><br/>
  Open-source infrastructure for AI coding agents.
</p>

<p align="center">
  <img src="assets/screenshots/hero.png" alt="Vibing — macOS + iPhone" width="800" />
</p>

---

You start Claude Code. It's rewriting your auth module. Halfway through, it asks: "Allow edit to auth.rs? [y/n]"

But you're in a meeting. Or getting coffee. Or walking the dog. You're just not at your desk.

You come back — it's been waiting for 20 minutes.

**Vibing fixes this.** See all your AI agents on your phone. Approve, reject, or kill — from anywhere.

```
  Your Mac                            Your Phone
 ┌────────────────┐                ┌──────────────────┐
 │ $ claude       │                │ 📋 All Sessions  │
 │ ⏳ Thinking... │    Vibing      │                  │
 │                │ ──────────►   │ ● claude  ⏳ busy │
 │ $ gemini       │  E2E encrypted │ ● gemini  ✅ done │
 │ ✅ Done.       │                │ ● aider   ⚠️ wait │
 │                │ ◄──────────   │                  │
 │ $ aider        │   you tap y    │ > aider [y/n]    │
 │ Apply? [y/n]   │                │   [✅ Yes]       │
 └────────────────┘                └──────────────────┘
```

<p align="center">
  <img src="assets/screenshots/session-list.png" alt="Session list on iPhone" width="300" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/screenshots/mobile-terminal.png" alt="Terminal rendering on iPhone" width="300" />
</p>

## What Makes Vibing Different

**It works with every AI agent.** Claude Code, Gemini CLI, Aider, Copilot, Cursor, Codex — every terminal tool works. Vibing operates at the PTY layer (the "pipe" between you and any terminal program), so it's invisible to the tools. Use whatever agent you want, switch anytime.

**All sessions, one screen.** Running 3 agents on 3 projects? See them all on your phone. No more switching between tabs wondering which one is stuck.

**It's not just a viewer — it's programmable.** Vibing has a [Hook API](#hook-api) that lets you build on top of the terminal stream. Auto-approve safe operations, catch runaway agents, pipe events to Slack, build multi-agent pipelines. The PTY layer is an open canvas.

**End-to-end encrypted.** The relay is blind — it can't read your code. Self-hostable.

**Open source.** MIT. Run it, fork it, extend it.

<p align="center">
  <img src="assets/screenshots/multi-tab.png" alt="Multi-tab and split pane" width="700" />
</p>

## Smart Features

Turn these on in **Settings → Features**. No code needed.

| | |
|---|---|
| **Smart Auto-Approve** | Agent asks "can I read this file?" → auto yes. Asks "can I rm -rf?" → auto no. Keyword-based, you set the rules. |
| **Circuit Breaker** | Agent stuck in a loop? Auto Ctrl+C after N repeats. Saves your API credits. |
| **Secret Leak Detector** | Catches API keys and passwords accidentally printed in the terminal. |
| **Session Audit Trail** | Every command, every approval, timestamped. |
| **Idle Notifications** | Agent done? You'll know. |

## Hook API

For the tinkerers. Vibing exposes the terminal stream as an HTTP interface.

```bash
# Watch for prompts in real-time
curl -N -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8767/api/v1/events?filter=on_prompt"

# Approve from the command line
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8767/api/v1/sessions/1/approve

# Turn any CLI into a REST API
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -d '{"command": "ls -la", "timeout_ms": 5000}' \
  http://127.0.0.1:8767/api/v1/sessions/1/exec
# → {"output": "total 32\ndrwxr-xr-x ...", "status": "completed"}
```

People have built: Slack/Feishu bots (control your terminal from chat), cost trackers, multi-agent orchestrators, session replay tools.

→ [Hook API docs](docs/design/2026-03-24_hook-api-design.md) · [Examples](examples/) · [Slack & Feishu bridges](examples/bridges/)

## Get Started

### Download the Client

| Platform | Download |
|----------|----------|
| **macOS** | [Download](https://github.com/anthropics/vibing/releases) |
| **iOS** | App Store (coming soon) |
| **Android** | Google Play (coming soon) |

Install, open, scan QR code to pair. That's it.

### Multi-device Sync

The client connects to our free public relay by default — works out of the box. Your data is end-to-end encrypted, the relay can't see anything.

Want to self-host? Deploy your own relay:

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.app/template/vibing-relay)
[![Deploy to Fly.io](https://img.shields.io/badge/Deploy%20to-Fly.io-blueviolet)](https://fly.io/docs/hands-on/install-flyctl/)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/anthropics/vibing)
[![Deploy on Zeabur](https://zeabur.com/button.svg)](https://zeabur.com/templates/vibing-relay)

```bash
# Or self-host with Docker
git clone https://github.com/anthropics/vibing.git && cd vibing
cp .env.example .env   # set your secrets
docker compose up -d
```

→ [Deployment docs](docs/ARCHITECTURE.md)

## Get Involved

Vibing is early. The PTY layer can do far more than terminal sync — we think there are things here that nobody has built yet.

### What we're building next

**Agent Memory** — Your AI agent starts from zero every time. It doesn't remember what you did yesterday. Vibing sits at the PTY layer, so it naturally sees every interaction. We want to build persistent memory across sessions: your coding patterns, project conventions, past mistakes — auto-injected so the agent actually "knows" you.

**AI-era Resume** — Think about it: every interaction you have with AI flows through Vibing. How you describe requirements, how you make technical decisions, how you review AI's code — that's 100x more real than a traditional resume. We want to turn this interaction data into a new kind of developer profile: not what you *say* you can do, but what AI has *witnessed* you do.

**Multi-Agent Orchestration** — Running 5 agents at once is already normal. But you're manually watching each one. We want agent pipelines: Agent A writes the frontend → auto-triggers Agent B to write tests → Agent C does code review. You set the rules, Vibing dispatches.

**Web Client** — Not everyone uses macOS. Open a browser, start vibing.

**Plugin Ecosystem** — The Hook API can already do a lot, but you still have to write scripts yourself. We want a plugin marketplace: auto-approve rules, Slack bridges, cost trackers someone else already built — install with one click.

### How you can help

You don't have to write code.

- Use Vibing and tell us what sucks — open an issue
- Got an idea? Start a Discussion
- Build a bridge for your team — Discord, Telegram, Teams, whatever
- Write about your Vibe Coding workflow
- Star the repo ⭐ so more people see it

→ [GitHub Issues](https://github.com/anthropics/vibing/issues) · [Discussions](https://github.com/anthropics/vibing/discussions)

## License

[MIT](LICENSE)

---

<p align="center">
  <strong>Vibe Coding. Anywhere. Anytime.</strong><br/>
  <sub>The best Vibe Coding workflow hasn't been invented yet — that's why Vibing is open.</sub>
</p>

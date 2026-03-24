# AI Coding CLI Tools: Remote Control via Terminal Relay Feasibility Study

**Date**: 2026-03-23
**Context**: Research for Vibing -- a product that lets users monitor and control terminal sessions from a mobile device via PTY + WebSocket relay.

---

## Executive Summary

AI coding CLI tools (Claude Code, Gemini CLI, Copilot CLI, Aider, etc.) **can** be controlled remotely through a PTY-based terminal relay system, but there are two fundamentally different architectural approaches, each with distinct trade-offs. The industry is actively building products in this space, validating the market opportunity.

---

## 1. How Each Tool Renders Its Terminal UI

### Claude Code
- **Framework**: React + [Ink](https://github.com/vadimdemedes/ink) (a React renderer for CLI apps)
- **Language**: TypeScript / Node.js
- **Rendering approach**: Full-screen redraws via ANSI escape sequences. Does NOT use the alternate screen buffer (`\e[?1049h`).
- **Output characteristics**: Sends output in ~4,095-byte chunks with heavy ANSI formatting (~50 bytes of color codes per line). Generates 4,000-6,700 scroll events/second during streaming -- 40-600x more than typical terminal tools.
- **Input**: Standard PTY stdin. Interactive prompts (y/n confirmations, permission requests) read from stdin.
- **TTY requirement**: Requires a TTY even in some non-interactive modes (known bug with `-p` flag in headless environments).

### Gemini CLI
- **Framework**: React + Ink (same as Claude Code)
- **Language**: TypeScript / Node.js
- **Key feature**: Built-in PTY support for running interactive sub-commands (vim, git rebase -i, etc.)
- **Architecture**: Clean separation between UI layer (packages/cli) and orchestration layer (packages/core)

### GitHub Copilot CLI
- **Language**: Closed-source binary (distributed via shell installer)
- **Rendering**: Full TUI with interactive elements, model switching (Ctrl+T), permission prompts
- **Known issue**: Infinite refresh loop with long conversation history (Issue #1874), similar scroll issues to Claude Code

### Aider
- **Framework**: Python + [prompt-toolkit](https://python-prompt-toolkit.readthedocs.io/)
- **Language**: Python
- **Rendering**: Simpler than Ink-based tools. Uses prompt-toolkit's rendering pipeline which optimizes output for slow connections.
- **Input**: Standard readline-style input with emacs/vi keybindings
- **Compatibility**: prompt-toolkit is specifically designed to work across different terminal environments including remote PTYs

### OpenCode
- **Framework**: Go + Bubble Tea (charmbracelet TUI framework)
- **Language**: Go
- **Rendering**: Full TUI with native terminal rendering

---

## 2. Can These Tools Be Controlled via PTY stdin?

**Yes.** All of these tools ultimately read from stdin through a PTY. When they display prompts like "Do you want to apply these changes? [y/n]", the input comes through the same PTY stdin that any keyboard input would use.

### Evidence:
1. **Claude Code Remote Control** (official Anthropic feature) works by routing messages through a relay -- proving the concept works.
2. **MobileCLI** (third-party) captures PTY output from AI coding sessions and streams via WebSocket with full ANSI color support.
3. **Claude Remote** (iOS app) manages Claude Code through tmux sessions -- "sending keystrokes and capturing terminal output in real time."
4. **ttyd** (generic web terminal) has been successfully used with AI coding tools via PTY + WebSocket relay with xterm.js rendering.

### Caveats:
- Claude Code's Bash tool currently does NOT support interactive sub-commands that need PTY passthrough (tracked in Issue #9881, #27294). But this is about Claude Code's *own* sub-process handling, not about controlling Claude Code itself.
- The `-p` (print/pipe) flag hangs without TTY in some environments (Issue #9026), but this affects headless scripting, not PTY-based relay.

---

## 3. Terminal Multiplexer Compatibility

### Claude Code + tmux

Claude Code works inside tmux, and this is in fact the **recommended setup** for remote control scenarios. However, there are known issues:

| Issue | Severity | Details |
|-------|----------|---------|
| **Excessive scroll events** | Medium | 4,000-6,700 scrolls/sec causes UI jitter in tmux |
| **Keyboard protocol mismatch** | Medium | tmux sends xterm extended key format; Claude Code expects kitty format. Raw escape sequences may print as garbage. |
| **Scrollback buffer pollution** | Low | `/clear` doesn't clean tmux scrollback; old content reappears on resize |
| **Keybinding conflicts** | Low | tmux intercepts Ctrl shortcuts that Claude Code also uses (e.g., Ctrl+O) |

### Aider + tmux
- Works well. prompt-toolkit is designed for cross-terminal compatibility.

### Gemini CLI + tmux
- Same Ink-based rendering issues as Claude Code (scroll rate, escape sequences).

### Implications for Vibing
A PTY relay (without tmux as intermediary) may actually **avoid** some tmux-specific issues (keyboard protocol mismatch, keybinding conflicts) while needing to handle the raw output volume itself.

---

## 4. WebSocket Terminal Relay Feasibility

### The Two Approaches

#### Approach A: Raw PTY Relay (ttyd-style)
```
PTY stdout → raw bytes → WebSocket → client terminal emulator (xterm.js)
client input → WebSocket → raw bytes → PTY stdin
```

**Pros:**
- Works with ANY terminal application (Claude Code, Aider, vim, htop, etc.)
- No application-specific integration needed
- Full fidelity -- every escape sequence is forwarded
- Proven technology (ttyd, gotty, etc. have been doing this for years)

**Cons:**
- High bandwidth for Ink-based tools (Claude Code generates ~189 KB/sec of ANSI overhead alone)
- No semantic understanding of what's happening (can't tell "waiting for approval" from "streaming output")
- No push notifications for completion/approval events
- Mobile connection drops lose context

**This is what Vibing does** (PTY → VT100 parser → WebSocket → client).

#### Approach B: Structured Message Relay (Claude Code Remote Control style)
```
Claude Code → structured JSON messages → HTTPS relay → mobile UI
mobile input → HTTPS relay → structured commands → Claude Code
```

**Pros:**
- Semantic awareness (knows when approval is needed, when task is done)
- Push notifications possible
- Low bandwidth (only meaningful content, no escape sequences)
- Survives connection drops gracefully (message buffering)

**Cons:**
- Application-specific -- only works with one tool
- Cannot run arbitrary terminal commands
- Requires the tool to expose a structured API

### Specific Technical Concerns for Raw PTY Relay

#### ANSI Escape Sequence Handling
- **Challenge**: Ink-based tools (Claude Code, Gemini CLI) generate massive volumes of escape sequences for full-screen redraws.
- **Solution**: Vibing already has a VT100 parser and incremental dirty-region rendering. This is the right architecture. The server should throttle/debounce screen updates (the existing 60fps throttle is good).
- **Risk**: Some edge cases with 24-bit RGB color sequences, cursor positioning during rapid redraws.

#### Interactive Prompts
- **Works**: All prompts read from PTY stdin. Sending `y\n` or `n\n` via WebSocket → PTY stdin will work.
- **Enhancement opportunity**: Parse the PTY output to detect common prompt patterns (e.g., `[y/n]`, `[Y/N/a]`) and surface them as mobile-friendly buttons.

#### Real-time Streaming Output
- **Challenge**: Claude Code streams LLM responses token-by-token with full-screen redraws at 4,000+ lines/sec.
- **Solution**: Server-side frame throttling (already implemented at 60fps). Client needs efficient terminal rendering.
- **Bandwidth**: On mobile, consider adaptive quality -- reduce color depth or skip intermediate frames on slow connections.

#### Ctrl+C Interruption
- **Works**: Ctrl+C is just byte `0x03` sent to PTY stdin. WebSocket relay handles this trivially.
- **Important**: Ensure the relay has minimal latency for interrupt signals. Users expect Ctrl+C to be immediate.

---

## 5. Competitive Landscape (as of March 2026)

| Product | Approach | Scope | Status |
|---------|----------|-------|--------|
| **Claude Code Remote Control** | Structured messages via Anthropic relay | Claude Code only | Official, GA |
| **Claude Remote (iOS)** | tmux + WebSocket | Claude Code only | Third-party |
| **MobileCLI** | PTY + WebSocket (self-hosted Rust daemon) | Any AI agent | Third-party |
| **Forge Remote** | Unknown | Claude Code | Third-party |
| **BeachViber** | Unknown | Claude Code | Third-party |
| **Bridge Terminal** | WebSocket | AI coding agents | Third-party |
| **cc-connect** | Messaging bridge | Multiple agents | Open source |
| **Agent Deck** | tmux session manager TUI | Multiple agents | Open source |
| **Vibing** | PTY + VT100 parser + WebSocket + Metal rendering | Any terminal app | In development |

### Vibing's Differentiation
1. **Universal**: Works with any terminal application, not just one AI tool
2. **Native rendering**: Metal GPU rendering (vs. xterm.js web rendering)
3. **Incremental updates**: Dirty-region based protocol (vs. full screen capture like tmux capture-pane)
4. **Self-hosted**: No dependency on Anthropic's relay servers

---

## 6. Recommendations for Vibing

### Must-Have
1. **Robust VT100/ANSI parsing**: Support 24-bit RGB colors, cursor save/restore, scroll regions -- Ink-based tools use all of these heavily.
2. **Frame throttling**: 60fps server-side throttle is essential. Consider adaptive throttling based on client connection quality.
3. **Low-latency input path**: Ctrl+C and other interrupt signals must have priority. Consider a separate high-priority input channel.
4. **Connection resilience**: Buffer recent screen state so reconnecting clients see current terminal state immediately.

### Should-Have
5. **Prompt detection**: Parse terminal output to detect interactive prompts (`[y/n]`, `[Y/N/a/Esc]`) and surface them as tappable buttons on mobile.
6. **Agent state heuristics**: Detect when an AI agent is "thinking" (streaming), "waiting for approval", or "idle" based on output patterns.
7. **Bandwidth adaptation**: On slow mobile connections, reduce update frequency or simplify color output.

### Nice-to-Have
8. **Structured integration layer**: For popular tools (Claude Code, Aider), optionally hook into their output to provide semantic notifications (task complete, error, needs approval).
9. **tmux integration**: Detect when running inside tmux and offer session management features.

---

## Sources

- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference)
- [Claude Code Remote Control Docs](https://code.claude.com/docs/en/remote-control)
- [Claude Code TTY Bug - Issue #9026](https://github.com/anthropics/claude-code/issues/9026)
- [Claude Code Scroll Events - Issue #9935](https://github.com/anthropics/claude-code/issues/9935)
- [Claude Code Interactive Prompts - Issue #27294](https://github.com/anthropics/claude-code/issues/27294)
- [Claude Code PTY Support Feature - Issue #9881](https://github.com/anthropics/claude-code/issues/9881)
- [Claude Code tmux Setup Guide](https://www.blle.co/blog/claude-code-tmux-beautiful-terminal)
- [Beyond SSH: WebSocket for AI Coding Agents](https://clauderc.com/blog/2026-02-28-beyond-ssh-websocket-for-ai-coding/)
- [Best iOS Apps for Remote AI Coding Agents](https://clauderc.com/blog/2026-02-28-best-ios-apps-for-remote-ai-coding-agents/)
- [Deep Dive: How Claude Code Remote Control Works](https://dev.to/chwu1946/deep-dive-how-claude-code-remote-control-actually-works-50p6)
- [MobileCLI](https://www.mobilecli.app/)
- [Gemini CLI Architecture](https://deepwiki.com/google-gemini/gemini-cli/1.1-architecture)
- [Aider Documentation](https://aider.chat/docs/usage/commands.html)
- [ttyd - Terminal Over the Web](https://tsl0922.github.io/ttyd/)
- [Copilot CLI Remote Session Support - Issue #1979](https://github.com/github/copilot-cli/issues/1979)
- [Amux - tmux Multiplexer for Parallel Claude Code Agents](https://news.ycombinator.com/item?id=47104424)

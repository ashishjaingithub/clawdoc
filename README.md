# 🩻 clawdoc

Examine agent sessions. Diagnose failures. Prescribe fixes.

[![CI](https://github.com/openclaw/clawdoc/actions/workflows/ci.yml/badge.svg)](https://github.com/openclaw/clawdoc/actions/workflows/ci.yml)

## Install

```bash
clawhub install clawdoc
```

Or manually:
```bash
git clone https://github.com/openclaw/clawdoc.git ~/.openclaw/skills/clawdoc
cd ~/.openclaw/skills/clawdoc && bash install.sh
```

## Usage

**Slash command** (from any channel):
```
/clawdoc              → headline health check
/clawdoc full         → complete diagnosis with prescriptions
/clawdoc brief        → one-liner for daily brief crons
```

**Direct script usage**:
```bash
# Health check across all sessions (last 7 days)
bash scripts/headline.sh ~/.openclaw/agents/main/sessions/

# Full diagnosis of a single session
bash scripts/diagnose.sh session.jsonl | bash scripts/prescribe.sh

# Per-turn cost breakdown
bash scripts/cost-waterfall.sh session.jsonl | jq '.[0:5]'

# Cross-session pattern recurrence
bash scripts/history.sh ~/.openclaw/agents/main/sessions/
```

**Natural language** (from any OpenClaw channel):
> "What's wrong with my agent?"
> "Why was that session so expensive?"
> "Give me a full diagnosis"

## Example output

```
🩻 clawdoc — 3 findings across 12 sessions (last 7 days)
💸 $47.20 spent — $31.60 was waste (67% recoverable)
🔴 Retry loop on exec burned $18.40 in one session
🟡 Opus running 34 heartbeats ($8.20 → $0.12 on Haiku)
🟡 SOUL.md is 9,200 tokens — 14% of your context window
```

## What it detects

| # | Pattern | Severity | What it catches |
|---|---------|----------|----------------|
| 1 | Infinite retry loop | 🔴 Critical | Same tool called 5+ times consecutively, burning tokens |
| 2 | Non-retryable error retried | 🔴 High | Validation errors re-attempted endlessly |
| 3 | Tool calls as plain text | 🔴 High | Model/provider mismatch — commands not executing |
| 4 | Context window exhaustion | 🟡-🔴 | Tokens approaching limit, session grinding to halt |
| 5 | Sub-agent replay storm | 🟡 Medium | Completion delivered 70+ times to parent |
| 6 | Cost spike attribution | 🟡-🔴 | Per-turn cost waterfall showing where money went |
| 7 | Skill selection miss | 🟢 Low | Required binary not installed |
| 8 | Model routing waste | 🟡 Medium | Opus running heartbeats that Haiku could handle |
| 9 | Cron context accumulation | 🟡 Medium | Cron jobs getting more expensive every run |
| 10 | Compaction damage | 🟡 Medium | Agent forgot context after auto-compaction |
| 11 | Workspace token overhead | 🟡 Medium | Context budget consumed before conversation starts |
| 12 | Task drift | 🟡 Medium | Agent drifts to unrelated work after compaction, or spirals reading without editing |

## Daily Brief integration

Add to your morning cron prompt:
```
Run /clawdoc brief and include the result in today's daily brief.
```

Output: `Yesterday: 8 sessions, $3.40, 1 warning (cron context growth on daily-report)`

## Requirements

- OpenClaw (any recent version)
- `bash` 3.2+ (macOS system bash works; bash 5.x recommended)
- `jq` 1.6+
- Standard POSIX tools: `awk`, `sed`, `grep`, `sort`, `uniq`, `wc`

Verify with: `bash scripts/check-deps.sh`

## How it works

clawdoc reads your local session JSONL files — already on your disk at `~/.openclaw/agents/<agentId>/sessions/`. Shell scripts detect 11 known failure patterns and output structured JSON findings. Your OpenClaw agent reads SKILL.md, runs the scripts, and synthesizes findings into a diagnosis with prescriptions. No data leaves your machine. No API keys required.

## Testing

```bash
make test       # runs 35 tests: detection, edge cases, unit, integration
make lint       # shellcheck all scripts (requires: brew install shellcheck)
make check-deps # verify jq, bash, awk are present
```

## Works with

- **ClawMetry**: ClawMetry shows what happened. clawdoc explains why and how to fix it.
- **self-improving-agent**: Writes findings to `.learnings/LEARNINGS.md` with idempotent recurrence tracking. Suggests promotion to `AGENTS.md` after 3+ recurrences across 2+ sessions.
- **SecureClaw**: clawdoc handles behavioral and cost issues. SecureClaw handles security.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add pattern detectors, design principles, threshold rationale, and the PR process.

## License

MIT — see [LICENSE](LICENSE).

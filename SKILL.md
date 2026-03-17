---
name: clawdoc
version: 0.11.1
description: "Diagnose OpenClaw agent failures, cost spikes, and performance issues with 14 pattern detectors. Use when: task failed unexpectedly, costs seem high, agent burned tokens, debugging session problems, want a health check, reviewing agent performance, agent forgot context, agent kept retrying, agent said commands but didn't execute them, cron jobs getting expensive, heartbeat costs too high, agent drifted off task after compaction, agent stuck reading without editing, agent running find/grep on entire filesystem, agent re-reading same file repeatedly."
user-invocable: true
metadata:
  openclaw:
    emoji: "🩻"
    requires:
      bins:
        - jq
        - bash
        - bc
---

# clawdoc

Examine agent sessions. Diagnose failures. Prescribe fixes.

## Invocation modes

### `/clawdoc` (slash command — default: headline mode)
Produces a compact, tweetable health check:
```
🩻 clawdoc — 3 findings across 12 sessions (last 7 days)
💸 $47.20 spent — $31.60 was waste (67% recoverable)
🔴 Retry loop on exec burned $18.40 in one session
🟡 Opus running 34 heartbeats ($8.20 → $0.12 on Haiku)
🟡 SOUL.md is 9,200 tokens — 14% of your context window
```
Run: `bash {baseDir}/scripts/headline.sh ~/.openclaw/agents/main/sessions`

### `/clawdoc full` or "give me a full diagnosis"
Runs all 14 pattern detectors and produces the complete diagnosis report with evidence and prescriptions.

### `/clawdoc brief` or "clawdoc one-liner for daily brief"
Single-line summary for morning cron integration:
```
Yesterday: 8 sessions, $3.40, 1 warning (cron context growth on daily-report)
```
Run: `bash {baseDir}/scripts/headline.sh --brief ~/.openclaw/agents/main/sessions`

### Natural language triggers
Also activates when user says: "what went wrong", "why did that fail", "debug", "diagnose", "why was that so expensive", "where are my tokens going", "cost breakdown", "health check", "check my agent", "what's wrong", "examine"

## Quick examination — most recent session

```bash
AGENT_DIR=$(ls -dt ~/.openclaw/agents/*/sessions 2>/dev/null | head -1)
AGENT_ID=$(echo "$AGENT_DIR" | rev | cut -d/ -f2 | rev)
LATEST=$(ls -t "$AGENT_DIR"/*.jsonl 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
  echo "No sessions found."
  exit 0
fi

echo "=== Patient: $(basename "$LATEST" .jsonl) ==="
echo "Model: $(head -1 "$LATEST" | jq -r '.model // "unknown"')"
echo "Turns: $(wc -l < "$LATEST")"
echo "Duration: $(head -1 "$LATEST" | jq -r '.timestamp') → $(tail -1 "$LATEST" | jq -r '.timestamp')"
echo ""

# Vitals
TOTAL_COST=$(jq -s '[.[] | .message.usage.cost.total // 0] | add' "$LATEST")
TOTAL_IN=$(jq -s '[.[] | .message.usage.inputTokens // 0] | add' "$LATEST")
TOTAL_OUT=$(jq -s '[.[] | .message.usage.outputTokens // 0] | add' "$LATEST")
MAX_IN=$(jq -s '[.[] | .message.usage.inputTokens // 0] | max' "$LATEST")
echo "Cost: \$$TOTAL_COST"
echo "Tokens: ${TOTAL_IN} input / ${TOTAL_OUT} output"
echo "Peak context: ${MAX_IN} tokens"
echo ""

# Tool call frequency
echo "Tool calls:"
jq -r '.message.content[]? | select(.type == "toolCall") | .name' "$LATEST" 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo ""

# Error count
ERR_COUNT=$(jq -r 'select(.message.role == "toolResult") | .message.content[]? | select(.type == "text") | .text' "$LATEST" 2>/dev/null | grep -ciE "(error|fail|denied|timeout|not found|missing)" || echo 0)
echo "Errors detected: $ERR_COUNT"
echo ""

# Cost waterfall — top 5 most expensive turns
echo "Most expensive turns:"
jq -r 'select(.message.usage.cost.total > 0) | [.timestamp, .message.role, (.message.usage.cost.total | tostring), (.message.usage.inputTokens | tostring)] | @tsv' "$LATEST" 2>/dev/null | sort -t$'\t' -k3 -rn | head -5 | awk -F'\t' '{printf "  %s | %s | $%s | %s input tokens\n", $1, $2, $3, $4}'
```

## Detect infinite retry loops

```bash
jq -r '.message.content[]? | select(.type == "toolCall") | .name' "$LATEST" 2>/dev/null | \
  awk '{if($0==prev){count++}else{if(count>=4)print (count+1)"x " prev " (RETRY LOOP DETECTED)";count=0};prev=$0} END{if(count>=4)print (count+1)"x " prev " (RETRY LOOP DETECTED)"}'
```

## Detect tool-as-text (broken tool calls)

```bash
jq -r 'select(.message.role == "assistant") | .message.content[]? | select(.type == "text") | .text' "$LATEST" 2>/dev/null | \
  grep -cE "^(read |exec |write |search_web |browser_navigate )" && \
  echo "⚠️  Tool commands appearing as plain text — likely model/provider compatibility issue"
```

## Detect context bloat

```bash
echo "Context growth per turn:"
jq -r 'select(.message.usage.inputTokens > 0) | [(.message.usage.inputTokens | tostring)] | @tsv' "$LATEST" 2>/dev/null | \
  awk 'BEGIN{prev=0}{delta=$1-prev; if(prev>0) printf "  %d tokens (+%d, %+.1f%%)\n", $1, delta, (prev>0?delta/prev*100:0); prev=$1}'
```

## Detect model routing waste

```bash
echo "Model usage across recent sessions:"
SESSIONS_JSON=$(dirname "$LATEST")/sessions.json
if [ -f "$SESSIONS_JSON" ]; then
  jq -r 'to_entries[] | select(.key | test("cron:|heartbeat")) | [.key, .value.model // "unknown", (.value.totalTokens // 0 | tostring)] | @tsv' "$SESSIONS_JSON" 2>/dev/null | \
    awk -F'\t' '{printf "  %s → %s (%s tokens)\n", $1, $2, $3}'
fi
```

## Detect cron context accumulation

```bash
echo "Cron session growth:"
for f in $(ls -t "$AGENT_DIR"/*.jsonl 2>/dev/null | head -20); do
  KEY=$(head -1 "$f" | jq -r '.sessionKey // empty')
  if echo "$KEY" | grep -q "cron:"; then
    FIRST_IN=$(jq -r 'select(.message.usage.inputTokens > 0) | .message.usage.inputTokens' "$f" 2>/dev/null | head -1)
    [ -n "$FIRST_IN" ] && echo "  $KEY: starts at $FIRST_IN input tokens ($(basename $f))"
  fi
done
```

## Check workspace overhead

```bash
echo "Workspace file sizes (estimated token cost):"
WORKSPACE=$(dirname "$(dirname "$AGENT_DIR")")
for f in "$WORKSPACE"/{AGENTS,SOUL,TOOLS,MEMORY,IDENTITY,USER,HEARTBEAT,BOOTSTRAP}.md; do
  if [ -f "$f" ]; then
    CHARS=$(wc -c < "$f")
    TOKENS=$((CHARS / 4))
    echo "  $(basename $f): ~${TOKENS} tokens (${CHARS} chars)"
  fi
done
```

## Full diagnosis

When the user wants a comprehensive diagnosis, run ALL checks above, then synthesize findings into this report format:

### Diagnosis report format

```
## 🩻 Diagnosis — [date]

### Patient summary
- Sessions examined: N
- Period: [date range]
- Total spend: $X.XX
- Total tokens: XXk in / XXk out

### Findings

#### 🔴 Critical
[Infinite retry loops, context exhaustion, tool-as-text failures]
Each finding includes: what happened, evidence, estimated cost impact, and specific prescription.

#### 🟡 Warning
[Cost spikes, model routing waste, cron accumulation, compaction damage, workspace overhead]

#### 🟢 Healthy
[What's working well — efficient sessions, good model routing]

### Prescriptions (ranked by cost impact)
1. [Highest-impact fix with specific config change or command]
2. [Second highest]
3. [Third]

### Cost breakdown
[Per-day costs for the examination period]
[Top 3 most expensive sessions with root cause]
```

## Pattern reference

| # | Pattern | Severity | Key indicator |
|---|---------|----------|--------------|
| 1 | Infinite retry loop | 🔴 Critical | Same tool called 5+ times consecutively |
| 2 | Non-retryable error retried | 🔴 High | Validation error → identical retry |
| 3 | Tool calls as text | 🔴 High | Tool names in assistant text, no toolCall blocks |
| 4 | Context window exhaustion | 🟡-🔴 | inputTokens > 70% of contextTokens |
| 5 | Sub-agent replay | 🟡 Medium | Duplicate completion messages in parent |
| 6 | Cost spike | 🟡-🔴 | Session cost > 2x rolling average |
| 7 | Skill selection miss | 🟢 Low | "command not found" after skill activation |
| 8 | Model routing waste | 🟡 Medium | Premium model on heartbeat/cron |
| 9 | Cron context accumulation | 🟡 Medium | Growing inputTokens across cron runs |
| 10 | Compaction damage | 🟡 Medium | Post-compaction tool call repetition |
| 11 | Workspace token overhead | 🟡 Medium | Baseline > 15% of context window |
| 12 | Task drift | 🟡 Medium | Post-compaction directory divergence or 10+ reads without edits |
| 13 | Unbounded walk | 🟠 High | Repeated unscoped find/grep -r flooding output |
| 14 | Tool misuse | 🟡 Medium | Same file read 3+ times without edit, or identical search repeated |

## Self-improving-agent integration

If `.learnings/` directory exists, write findings to `.learnings/LEARNINGS.md` using DR-NNN IDs, Pattern-Key format, and Recurrence-Count tracking. When recurrence hits 3+ across 2+ sessions in 30 days, suggest promotion to AGENTS.md or TOOLS.md.

## Tips

- Session JSONL at `~/.openclaw/agents/<agentId>/sessions/` is the ground truth
- Use `jq -s` (slurp) for aggregations across all lines
- Filter `message.content[]` by `type=="text"` for readable content, `type=="toolCall"` for tool invocations
- `sessions.json` has cumulative token counts — good for quick overviews
- Gateway logs at `/tmp/openclaw/openclaw-YYYY-MM-DD.log` capture provider-level errors the session JSONL may not
- When prescribing config changes, always show the exact JSON path and value

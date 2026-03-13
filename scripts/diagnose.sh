#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"

# diagnose.sh — Detects 11 anti-patterns in an OpenClaw JSONL session file
# Usage: diagnose.sh <path-to-session.jsonl>
# Output: JSON array of findings to stdout; progress on stderr

usage() {
  cat <<EOF
Usage: diagnose.sh [--help|--version] <path-to-jsonl>

Description:
  Runs all 11 pattern detectors against a session JSONL file.

Options:
  --help      Show this help message and exit
  --version   Show version and exit

Example:
  diagnose.sh ~/.openclaw/agents/main/sessions/abc123.jsonl | jq .
EOF
}

check_deps() {
  for dep in jq awk; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Error: required dependency '$dep' not found. Install it and retry." >&2
      exit 1
    fi
  done
}

if [[ $# -ge 1 ]]; then
  case "$1" in
    --help) usage; exit 0 ;;
    --version) echo "$VERSION"; exit 0 ;;
  esac
fi

check_deps

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <session.jsonl>" >&2
  exit 1
fi

JSONL="$1"

if [[ ! -f "$JSONL" ]]; then
  echo "Error: file not found: $JSONL" >&2
  exit 1
fi

FINDINGS=()

add_finding() {
  local json="$1"
  FINDINGS+=("$json")
}

# ---------------------------------------------------------------------------
# Helpers: parse the JSONL once into shell variables where needed
# ---------------------------------------------------------------------------

# Session metadata (line 1)
SESSION_LINE=$(head -1 "$JSONL")
SESSION_MODEL=$(echo "$SESSION_LINE" | jq -r '.model // ""')
SESSION_KEY=$(echo "$SESSION_LINE" | jq -r '.sessionKey // ""')
CONTEXT_TOKENS=128000

# ---------------------------------------------------------------------------
# Detector 1: detect_infinite_retry
# ---------------------------------------------------------------------------
detect_infinite_retry() {
  echo "[diagnose] running detect_infinite_retry..." >&2

  # Extract all toolCall names in message order (one per line), with turn index and cost
  # We emit: <turn_index> <tool_name> <input_snippet_100chars> <cost>
  local tool_seq
  tool_seq=$(jq -r '
    to_entries
    | map(select(.value.type == "message" and .value.message.role == "assistant"))
    | to_entries
    | .[]
    | . as $outer
    | .value.value.message.content[]?
    | select(.type == "toolCall")
    | [
        ($outer.key | tostring),
        .name,
        (.input | tojson | .[0:100]),
        ($outer.value.value.message.usage.cost.total // 0 | tostring)
      ]
    | join("\t")
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$tool_seq" ]]; then return 0; fi

  # Use awk to find runs of >=5 consecutive same tool+input
  local finding
  finding=$(echo "$tool_seq" | awk -F'\t' '
  BEGIN { prev_name=""; prev_input=""; run=1; run_start_idx=0; total_cost=0; first_cost=0 }
  {
    turn=$1; name=$2; input=$3; cost=$4+0
    if (name == prev_name && input == prev_input) {
      run++
      total_cost += cost
    } else {
      # check previous run
      if (run >= 5) {
        printf "%s\t%d\t%.6f\t%s\n", prev_name, run, total_cost, prev_input
      }
      run=1
      total_cost=cost
      prev_name=name
      prev_input=input
    }
  }
  END {
    if (run >= 5) {
      printf "%s\t%d\t%.6f\t%s\n", prev_name, run, total_cost, prev_input
    }
  }
  ')

  if [[ -z "$finding" ]]; then return 0; fi

  # Take the worst (highest run count) finding
  local worst
  worst=$(echo "$finding" | sort -t$'\t' -k2 -rn | head -1)

  local tool_name run_count cost_sum input_snippet
  tool_name=$(echo "$worst" | cut -f1)
  run_count=$(echo "$worst" | cut -f2)
  cost_sum=$(echo "$worst" | cut -f3)
  input_snippet=$(echo "$worst" | cut -f4)

  # Build a human-readable input summary from the snippet
  local cmd_display
  cmd_display=$(echo "$input_snippet" | jq -r 'if type=="object" then (.command // .path // (to_entries[0].value // "") ) else . end' 2>/dev/null || echo "$input_snippet")
  # Fallback: if still empty or null, show raw JSON snippet (truncated) or "(empty input)"
  if [[ -z "$cmd_display" || "$cmd_display" == "null" ]]; then
    local raw_snippet
    raw_snippet=$(echo "$input_snippet" | tr -d '[:space:]')
    if [[ -z "$raw_snippet" || "$raw_snippet" == "{}" ]]; then
      cmd_display="(empty input)"
    else
      cmd_display=$(echo "$input_snippet" | cut -c1-80)
    fi
  fi

  local cost_rounded
  cost_rounded=$(printf "%.2f" "$cost_sum")

  local evidence
  evidence="${tool_name} called ${run_count} times consecutively with $(echo "$cmd_display" | head -c 120)"

  local prescription
  prescription="Your agent called \`${tool_name}\` ${run_count} times in a row, burning \$${cost_rounded}. Add \`timeoutSeconds\` to your cron payload, or restructure the task prompt to include explicit stop conditions."

  add_finding "$(jq -nc \
    --arg pattern "infinite-retry" \
    --argjson pattern_id 1 \
    --arg severity "critical" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$(printf '%.6f' "$cost_sum")" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 2: detect_non_retryable_retry
# ---------------------------------------------------------------------------
detect_non_retryable_retry() {
  echo "[diagnose] running detect_non_retryable_retry..." >&2

  # For each toolResult with a non-retryable error, find the preceding assistant
  # toolCall name and count repeated identical calls.
  local result
  result=$(jq -r '
    [ .[] | select(.type == "message") ] as $msgs
    | $msgs | to_entries[]
    | select(.value.message.role == "toolResult")
    | . as $entry
    | .key as $idx
    | .value.message.content[]? | select(.type == "text") | .text as $err
    | select($err | test("Missing required parameter|Expected .* but received|TypeError|ValidationError|invalid.*parameter"; "i"))
    | if $idx > 0 then
        $msgs[$idx - 1].message as $prev
        | ($prev.content[]? | select(.type == "toolCall") | [.name, (.input | tojson | .[0:100]), $err[0:80]] | @tsv)
      else empty end
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$result" ]]; then return 0; fi

  # Count occurrences per tool name
  local tool_counts
  tool_counts=$(echo "$result" | cut -f1 | sort | uniq -c | sort -rn | head -1)
  if [[ -z "$tool_counts" ]]; then return 0; fi

  local count tool_name
  count=$(echo "$tool_counts" | awk '{print $1}')
  tool_name=$(echo "$tool_counts" | awk '{print $2}')

  if [[ "$count" -lt 2 ]]; then return 0; fi

  local err_snippet
  err_snippet=$(echo "$result" | awk -F'\t' -v t="$tool_name" '$1==t {print $3; exit}' | head -c 80)

  local evidence="${tool_name} called with error '${err_snippet}', retried ${count} times identically"
  local prescription="Your agent retried a tool with the same invalid parameters ${count} times. Restructure the skill that triggers this call to validate inputs before invoking the tool."

  add_finding "$(jq -nc \
    --arg pattern "non-retryable-retry" \
    --argjson pattern_id 2 \
    --arg severity "high" \
    --arg evidence "$evidence" \
    --argjson cost_impact 0 \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 3: detect_tool_as_text
# ---------------------------------------------------------------------------
detect_tool_as_text() {
  echo "[diagnose] running detect_tool_as_text..." >&2

  # Find assistant messages that have text matching tool invocation patterns
  # but NO toolCall block in the same message
  local findings
  findings=$(jq -r '
    .[]
    | select(.type == "message" and .message.role == "assistant")
    | .message as $msg
    | ($msg.content // []) as $content
    | ($content | map(select(.type == "toolCall")) | length) as $tc_count
    | if $tc_count > 0 then empty else
        $content[]
        | select(.type == "text")
        | .text
        | split("\n")[]
        | select(test("^(read|exec|write|search_web|browser_navigate|web_fetch)\\s+"))
      end
  ' <(jq -s '.' "$JSONL") 2>/dev/null | sort | uniq -c | sort -rn) || return 0

  if [[ -z "$findings" ]]; then return 0; fi

  # Take the most common
  local top_count top_line
  top_count=$(echo "$findings" | head -1 | awk '{print $1}')
  top_line=$(echo "$findings" | head -1 | sed 's/^ *[0-9]* *//' | head -c 120)

  local evidence="Agent output '${top_line}' as plain text ${top_count} times without executing"
  local prescription="Agent is outputting tool commands as plain text rather than executing them. Likely a model/provider compatibility issue."

  add_finding "$(jq -nc \
    --arg pattern "tool-as-text" \
    --argjson pattern_id 3 \
    --arg severity "high" \
    --arg evidence "$evidence" \
    --argjson cost_impact 0 \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 4: detect_context_exhaustion
# ---------------------------------------------------------------------------
detect_context_exhaustion() {
  echo "[diagnose] running detect_context_exhaustion..." >&2

  # Extract inputTokens and contextTokens from all assistant messages
  local token_data
  token_data=$(jq -r '
    .[]
    | select(.type == "message" and .message.role == "assistant")
    | [
        (.message.usage.inputTokens // 0 | tostring),
        (.message.usage.contextTokens // 128000 | tostring),
        (.message.usage.cost.total // 0 | tostring)
      ]
    | join("\t")
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$token_data" ]]; then return 0; fi

  local max_input_tokens=0
  local context_tokens=$CONTEXT_TOKENS
  local total_cost=0
  local turn=0
  local max_jump=0
  local max_jump_turn=0
  local window_start_tokens=()

  while IFS=$'\t' read -r input_tok ctx_tok cost; do
    turn=$((turn + 1))
    input_tok=${input_tok:-0}
    ctx_tok=${ctx_tok:-128000}
    cost=${cost:-0}

    # Track context tokens (use the most recent non-zero value)
    if [[ "$ctx_tok" -gt 0 ]]; then
      context_tokens=$ctx_tok
    fi

    total_cost=$(echo "$total_cost + $cost" | bc 2>/dev/null || echo "$total_cost")

    if [[ "$input_tok" -gt "$max_input_tokens" ]]; then
      max_input_tokens=$input_tok
    fi

    # Track 10-turn window for doubling detection
    window_start_tokens+=("$input_tok")
    if [[ ${#window_start_tokens[@]} -gt 10 ]]; then
      local oldest="${window_start_tokens[0]}"
      window_start_tokens=("${window_start_tokens[@]:1}")
      if [[ "$oldest" -gt 0 ]]; then
        local jump=$(( input_tok - oldest ))
        if [[ "$jump" -gt "$max_jump" ]]; then
          max_jump=$jump
          max_jump_turn=$turn
        fi
      fi
    fi
  done <<< "$token_data"

  if [[ "$max_input_tokens" -eq 0 || "$context_tokens" -eq 0 ]]; then return 0; fi

  local pct
  pct=$(echo "scale=1; $max_input_tokens * 100 / $context_tokens" | bc 2>/dev/null || echo "0")
  local pct_int
  pct_int=$(echo "$pct" | cut -d. -f1)

  # Only flag if > 70%
  if [[ "$pct_int" -lt 70 ]]; then
    # Also check 10-turn doubling: if max_input >= 2 * (oldest in any window)
    # We already tracked max_jump; check if any window start was < half max_input
    return 0
  fi

  local severity
  if [[ "$pct_int" -ge 90 ]]; then
    severity="high"
  else
    severity="medium"
  fi

  local ctx_k; ctx_k=$(echo "scale=0; $context_tokens / 1000" | bc 2>/dev/null || echo "$(( context_tokens / 1000 ))")
  local max_k; max_k=$(echo "scale=0; $max_input_tokens / 1000" | bc 2>/dev/null || echo "$(( max_input_tokens / 1000 ))")
  local jump_k; jump_k=$(echo "scale=0; $max_jump / 1000" | bc 2>/dev/null || echo "$(( max_jump / 1000 ))")

  local evidence="Session reached ${max_k}K tokens (${pct}% of ${ctx_k}K context). Largest single jump: +${jump_k}K tokens at turn ${max_jump_turn}."
  local prescription="Run /compact or use exec with tail/head instead of reading full files."

  local total_cost_rounded
  total_cost_rounded=$(printf "%.6f" "$total_cost" 2>/dev/null || echo "0")

  add_finding "$(jq -nc \
    --arg pattern "context-exhaustion" \
    --argjson pattern_id 4 \
    --arg severity "$severity" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$total_cost_rounded" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 5: detect_subagent_replay
# ---------------------------------------------------------------------------
detect_subagent_replay() {
  echo "[diagnose] running detect_subagent_replay..." >&2

  # Only applies if sessionKey matches agent:*:subagent:*
  if ! echo "$SESSION_KEY" | grep -qE '^agent:.+:subagent:.+'; then
    return 0
  fi

  # Find consecutive identical assistant messages (same text content)
  local replay_data
  replay_data=$(jq -r '
    [ .[] | select(.type == "message" and .message.role == "assistant") ]
    | to_entries[]
    | .key as $k
    | .value.message as $m
    | ($m.usage.cost.total // 0) as $cost
    | ($m.content // [] | .[] | select(.type == "text") | .text) as $txt
    | [$k | tostring, $txt, ($cost | tostring)]
    | @tsv
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$replay_data" ]]; then return 0; fi

  # Use awk to find consecutive runs of same text
  local worst
  worst=$(echo "$replay_data" | awk -F'\t' '
  BEGIN { prev_text=""; run=1; total_cost=0; best_run=0; best_cost=0; best_text="" }
  {
    idx=$1; text=$2; cost=$3+0
    if (text == prev_text) {
      run++
      total_cost += cost
    } else {
      if (run > best_run) {
        best_run = run
        best_cost = total_cost
        best_text = prev_text
      }
      run = 1
      total_cost = cost
      prev_text = text
    }
  }
  END {
    if (run > best_run) {
      best_run = run
      best_cost = total_cost
      best_text = prev_text
    }
    if (best_run >= 3) {
      printf "%d\t%.6f\t%s\n", best_run, best_cost, substr(best_text, 1, 80)
    }
  }
  ')

  if [[ -z "$worst" ]]; then return 0; fi

  local run_count cost_sum
  run_count=$(echo "$worst" | cut -f1)
  cost_sum=$(echo "$worst" | cut -f2)

  local evidence="Sub-agent completed but result was delivered ${run_count} times to parent session"
  local prescription="Known sub-agent delivery bug. Monitor sub-agent spawns and report persistent issues to the OpenClaw repo."

  add_finding "$(jq -nc \
    --arg pattern "subagent-replay" \
    --argjson pattern_id 5 \
    --arg severity "medium" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$(printf '%.6f' "$cost_sum")" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 6: detect_cost_spike
# ---------------------------------------------------------------------------
detect_cost_spike() {
  echo "[diagnose] running detect_cost_spike..." >&2

  # Extract per-turn costs with turn index and tool call name
  local turn_costs
  turn_costs=$(jq -r '
    to_entries
    | map(select(.value.type == "message" and .value.message.role == "assistant"))
    | to_entries
    | .[]
    | [
        (.key + 1 | tostring),
        (.value.value.message.usage.cost.total // 0 | tostring),
        (.value.value.message.content // [] | map(select(.type == "toolCall")) | .[0].name // "(no tool)")
      ]
    | join("\t")
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$turn_costs" ]]; then return 0; fi

  local total_cost=0
  local max_turn_cost=0
  local max_turn_num=0
  local max_turn_tool=""

  while IFS=$'\t' read -r turn_num cost tool_name; do
    total_cost=$(echo "$total_cost + $cost" | bc 2>/dev/null || echo "0")
    local cost_f
    cost_f=$(printf '%.6f' "$cost" 2>/dev/null || echo "0")
    local max_f
    max_f=$(printf '%.6f' "$max_turn_cost" 2>/dev/null || echo "0")
    if (( $(echo "$cost_f > $max_f" | bc -l 2>/dev/null || echo 0) )); then
      max_turn_cost=$cost
      max_turn_num=$turn_num
      max_turn_tool=$tool_name
    fi
  done <<< "$turn_costs"

  local max_rounded
  max_rounded=$(printf "%.2f" "$max_turn_cost" 2>/dev/null || echo "0")

  # Determine if we should flag
  local flag=0
  local severity=""
  local cost_impact=0

  # Check single turn > $0.50
  if (( $(echo "$max_turn_cost > 1.00" | bc -l 2>/dev/null || echo 0) )); then
    flag=1; severity="critical"
    cost_impact=$(echo "$max_turn_cost - 0.50" | bc 2>/dev/null || echo "$max_turn_cost")
  elif (( $(echo "$max_turn_cost > 0.50" | bc -l 2>/dev/null || echo 0) )); then
    flag=1; severity="high"
    cost_impact=$(echo "$max_turn_cost - 0.50" | bc 2>/dev/null || echo "$max_turn_cost")
  elif (( $(echo "$total_cost > 1.00" | bc -l 2>/dev/null || echo 0) )); then
    flag=1; severity="medium"
    cost_impact=$total_cost
  fi

  if [[ "$flag" -eq 0 ]]; then return 0; fi

  # Top 3 turns by cost
  local top3
  top3=$(echo "$turn_costs" | sort -t$'\t' -k2 -rn | head -3)
  local top3_total=0
  while IFS=$'\t' read -r _ c _; do
    top3_total=$(echo "$top3_total + $c" | bc 2>/dev/null || echo "$top3_total")
  done <<< "$top3"

  local top3_pct
  if (( $(echo "$total_cost > 0" | bc -l 2>/dev/null || echo 0) )); then
    top3_pct=$(echo "scale=0; $top3_total * 100 / $total_cost" | bc 2>/dev/null || echo "0")
  else
    top3_pct=0
  fi

  local evidence="Turn ${max_turn_num} cost \$${max_rounded} (tool: ${max_turn_tool}). Top 3 turns = ${top3_pct}% of session cost."
  local prescription="Use exec with curl | head -c 2000 instead of web_fetch for large pages, or run /compact after processing web content."

  add_finding "$(jq -nc \
    --arg pattern "cost-spike" \
    --argjson pattern_id 6 \
    --arg severity "$severity" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$(printf '%.6f' "$cost_impact")" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 7: detect_skill_miss
# ---------------------------------------------------------------------------
detect_skill_miss() {
  echo "[diagnose] running detect_skill_miss..." >&2

  # Find toolResult messages with "command not found" style errors
  local findings
  findings=$(jq -r '
    .[]
    | select(.type == "message" and .message.role == "toolResult")
    | .message.content[]?
    | select(.type == "text")
    | .text
    | select(test("command not found|not installed|No such file or directory|is not recognized as"; "i"))
    | .
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$findings" ]]; then return 0; fi

  # Also find the tool call that led to this error — look at preceding assistant
  local cmd_errors
  cmd_errors=$(jq -r '
    to_entries as $all
    | $all[]
    | select(.value.type == "message" and .value.message.role == "toolResult")
    | . as $tr
    | (.value.message.content // [])[] | select(.type == "text")
    | .text as $err
    | select($err | test("command not found|not installed|No such file or directory|is not recognized as"; "i"))
    | # Find preceding assistant message
      ($all | to_entries | map(select(.value.value.type == "message")) ) as $msgs
    | ($msgs | map(select(.value.key == $tr.key)) | .[0].key) as $tr_pos
    | if $tr_pos == null or $tr_pos == 0 then
        ["unknown", $err[0:100]] | @tsv
      else
        ($msgs[$tr_pos - 1].value.value.message.content // [] | .[] | select(.type == "toolCall") | .input | (.command // .path // "") | .[0:80]) as $cmd
        | [$cmd, $err[0:100]]
        | @tsv
      end
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || true

  # Fall back: just use the first error text
  local first_err
  first_err=$(echo "$findings" | head -1 | head -c 100)

  local cmd_snippet
  if [[ -n "$cmd_errors" ]]; then
    cmd_snippet=$(echo "$cmd_errors" | head -1 | cut -f1 | head -c 80)
  fi
  if [[ -z "$cmd_snippet" || "$cmd_snippet" == "unknown" ]]; then
    # Try to extract command name from error text
    cmd_snippet=$(echo "$first_err" | grep -oE '[a-zA-Z][a-zA-Z0-9_-]+' | head -1)
  fi

  local evidence="exec called with '${cmd_snippet}' failed: ${first_err}"
  local prescription="Required binary not installed. Install it or disable the skill."

  add_finding "$(jq -nc \
    --arg pattern "skill-miss" \
    --argjson pattern_id 7 \
    --arg severity "low" \
    --arg evidence "$evidence" \
    --argjson cost_impact 0 \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 8: detect_model_routing_waste
# ---------------------------------------------------------------------------
detect_model_routing_waste() {
  echo "[diagnose] running detect_model_routing_waste..." >&2

  # Check if session key contains cron: or heartbeat AND model is expensive
  local is_cron=0
  if echo "$SESSION_KEY" | grep -qE '(^cron:|heartbeat)'; then
    is_cron=1
  fi

  if [[ "$is_cron" -eq 0 ]]; then return 0; fi

  # Check if model is expensive (opus, sonnet, gpt-4o, gemini-pro)
  local is_expensive=0
  if echo "$SESSION_MODEL" | grep -qiE '(opus|sonnet|gpt-4o|gemini-pro)'; then
    is_expensive=1
  fi

  if [[ "$is_expensive" -eq 0 ]]; then return 0; fi

  # Calculate total cost and turn count
  local session_stats
  session_stats=$(jq -r '
    [ .[] | select(.type == "message" and .message.role == "assistant") ] as $msgs
    | {
        turns: ($msgs | length),
        total_cost: ($msgs | map(.message.usage.cost.total // 0) | add // 0),
        total_input_tokens: ($msgs | map(.message.usage.inputTokens // 0) | add // 0)
      }
    | [(.turns | tostring), (.total_cost | tostring), (.total_input_tokens | tostring)]
    | join("\t")
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$session_stats" ]]; then return 0; fi

  local turns total_cost total_input_tokens
  turns=$(echo "$session_stats" | cut -f1)
  total_cost=$(echo "$session_stats" | cut -f2)
  total_input_tokens=$(echo "$session_stats" | cut -f3)

  local cost_rounded
  cost_rounded=$(printf "%.2f" "$total_cost" 2>/dev/null || echo "0")

  local tokens_k
  tokens_k=$(echo "scale=0; $total_input_tokens / 1000" | bc 2>/dev/null || echo "$(( total_input_tokens / 1000 ))")

  # Savings: haiku would cost ~10% of opus/sonnet
  local cost_impact
  cost_impact=$(echo "scale=6; $total_cost * 0.9" | bc 2>/dev/null || echo "0")

  local evidence="Session on ${SESSION_MODEL} with sessionKey '${SESSION_KEY}' — ${turns} turns, ${tokens_k}K tokens, \$${cost_rounded}"
  local haiku_cost
  haiku_cost=$(printf '%.2f' "$(echo "scale=4; $total_cost * 0.1" | bc 2>/dev/null || echo "0")")
  local prescription="Switching this cron to claude-haiku-4-5 would cost ~\$${haiku_cost} for the same work. Add to openclaw.json: \`\"heartbeat\": { \"model\": \"anthropic/claude-haiku-4-5\" }\`"

  add_finding "$(jq -nc \
    --arg pattern "model-routing-waste" \
    --argjson pattern_id 8 \
    --arg severity "medium" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$(printf '%.6f' "$cost_impact")" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 9: detect_cron_accumulation
# ---------------------------------------------------------------------------
detect_cron_accumulation() {
  echo "[diagnose] running detect_cron_accumulation..." >&2

  # Only for cron sessions
  if ! echo "$SESSION_KEY" | grep -qE '^cron:'; then
    return 0
  fi

  # Extract inputTokens from each assistant turn in order
  local token_seq
  token_seq=$(jq -r '
    .[]
    | select(.type == "message" and .message.role == "assistant")
    | (.message.usage.inputTokens // 0)
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$token_seq" ]]; then return 0; fi

  local first_val=0
  local last_val=0
  local prev_val=0
  local is_monotonic=1
  local count=0

  while read -r val; do
    count=$((count + 1))
    if [[ "$count" -eq 1 ]]; then
      first_val=$val
    fi
    last_val=$val
    if [[ "$prev_val" -gt 0 && "$val" -lt "$prev_val" ]]; then
      is_monotonic=0
    fi
    prev_val=$val
  done <<< "$token_seq"

  if [[ "$count" -lt 2 || "$is_monotonic" -eq 0 ]]; then return 0; fi
  if [[ "$first_val" -eq 0 ]]; then return 0; fi

  # Check if highest (last_val) > 2x lowest (first_val)
  local threshold=$(( first_val * 2 ))
  if [[ "$last_val" -le "$threshold" ]]; then return 0; fi

  local cron_name="${SESSION_KEY#cron:}"
  local evidence="cron:${cron_name} inputTokens grew from ${first_val} to ${last_val} across session — likely accumulating context across runs"
  local prescription="Set session isolation: \`\"session\": { \"isolated\": true }\` so each cron run starts fresh."

  add_finding "$(jq -nc \
    --arg pattern "cron-accumulation" \
    --argjson pattern_id 9 \
    --arg severity "medium" \
    --arg evidence "$evidence" \
    --argjson cost_impact 0 \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 10: detect_compaction_damage
# ---------------------------------------------------------------------------
detect_compaction_damage() {
  echo "[diagnose] running detect_compaction_damage..." >&2

  # Extract per-turn: turn_index, inputTokens, and all toolCall name+input pairs
  local turns_data
  turns_data=$(jq -r '
    [ .[] | select(.type == "message" and .message.role == "assistant") ]
    | to_entries[]
    | .key as $idx
    | .value.message as $m
    | [
        ($idx | tostring),
        ($m.usage.inputTokens // 0 | tostring),
        ($m.usage.cost.total // 0 | tostring),
        ([$m.content[]? | select(.type == "toolCall") | {name: .name, input: (.input | tojson | .[0:100])}] | tojson)
      ]
    | join("\t")
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$turns_data" ]]; then return 0; fi

  # Find compaction event: inputTokens drops by >40% vs previous
  local compaction_idx=-1
  local prev_tokens=0

  while IFS=$'\t' read -r idx tokens cost tool_calls_json; do
    if [[ "$prev_tokens" -gt 0 && "$tokens" -gt 0 ]]; then
      local drop_pct
      drop_pct=$(echo "scale=1; ($prev_tokens - $tokens) * 100 / $prev_tokens" | bc 2>/dev/null || echo "0")
      local drop_int
      drop_int=$(echo "$drop_pct" | cut -d. -f1)
      if [[ "$drop_int" -ge 40 ]]; then
        compaction_idx=$(echo "$idx" | tr -d '"')
        break
      fi
    fi
    prev_tokens=$tokens
  done <<< "$turns_data"

  if [[ "$compaction_idx" -lt 0 ]]; then return 0; fi

  # Collect toolCall name+input from BEFORE compaction
  local pre_tool_set=()
  while IFS=$'\t' read -r idx tokens cost tool_calls_json; do
    if [[ "$idx" -ge "$compaction_idx" ]]; then break; fi
    # Extract each tool call as "name|input" string
    while IFS= read -r tool_entry; do
      pre_tool_set+=("$tool_entry")
    done < <(echo "$tool_calls_json" | jq -r '.[] | [.name, .input] | join("|")' 2>/dev/null || true)
  done <<< "$turns_data"

  if [[ ${#pre_tool_set[@]} -eq 0 ]]; then return 0; fi

  # Check next 5 turns AFTER compaction for repeated tool calls
  local repeated_tools=()
  local post_cost=0
  local post_turn_count=0

  while IFS=$'\t' read -r idx tokens cost tool_calls_json; do
    if [[ "$idx" -le "$compaction_idx" ]]; then continue; fi
    if [[ "$post_turn_count" -ge 5 ]]; then break; fi
    post_turn_count=$((post_turn_count + 1))

    while IFS= read -r tool_entry; do
      for pre in "${pre_tool_set[@]}"; do
        if [[ "$tool_entry" == "$pre" ]]; then
          repeated_tools+=("$(echo "$tool_entry" | cut -d'|' -f1)")
          post_cost=$(echo "$post_cost + $cost" | bc 2>/dev/null || echo "$post_cost")
          break
        fi
      done
    done < <(echo "$tool_calls_json" | jq -r '.[] | [.name, .input] | join("|")' 2>/dev/null || true)
  done <<< "$turns_data"

  if [[ ${#repeated_tools[@]} -eq 0 ]]; then return 0; fi

  # Get the tokens before/after compaction for evidence
  local pre_tokens=0
  local post_tokens=0
  while IFS=$'\t' read -r idx tokens cost tool_calls_json; do
    if [[ "$idx" -eq $((compaction_idx - 1)) ]]; then pre_tokens=$tokens; fi
    if [[ "$idx" -eq "$compaction_idx" ]]; then post_tokens=$tokens; fi
  done <<< "$turns_data"

  local pre_k=$(( pre_tokens / 1000 ))
  local post_k=$(( post_tokens / 1000 ))

  # Unique tool names repeated
  local unique_repeated
  unique_repeated=$(printf '%s\n' "${repeated_tools[@]}" | sort -u | tr '\n' ', ' | sed 's/,$//')

  local evidence="After compaction at turn $((compaction_idx + 1)) (${pre_k}K→${post_k}K tokens), agent re-called: ${unique_repeated} — all already processed before compaction."
  local prescription="Increase compaction.softThresholdTokens, write key findings to MEMORY.md before compaction, or start new sessions for complex multi-step tasks."

  add_finding "$(jq -nc \
    --arg pattern "compaction-damage" \
    --argjson pattern_id 10 \
    --arg severity "medium" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$(printf '%.6f' "$post_cost")" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Detector 11: detect_workspace_overhead
# ---------------------------------------------------------------------------
detect_workspace_overhead() {
  echo "[diagnose] running detect_workspace_overhead..." >&2

  # Find the FIRST assistant message's inputTokens and contextTokens
  local first_turn_data
  first_turn_data=$(jq -r '
    [ .[] | select(.type == "message" and .message.role == "assistant") ]
    | .[0]
    | [
        (.message.usage.inputTokens // 0 | tostring),
        (.message.usage.contextTokens // 128000 | tostring),
        (.message.usage.cost.total // 0 | tostring)
      ]
    | join("\t")
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || return 0

  if [[ -z "$first_turn_data" ]]; then return 0; fi

  local first_input_tokens ctx_tokens
  first_input_tokens=$(echo "$first_turn_data" | cut -f1)
  ctx_tokens=$(echo "$first_turn_data" | cut -f2)

  if [[ "$first_input_tokens" -eq 0 || "$ctx_tokens" -eq 0 ]]; then return 0; fi

  # Check if > 15% of contextTokens
  local threshold; threshold=$(echo "scale=0; $ctx_tokens * 15 / 100" | bc 2>/dev/null || echo "$(( ctx_tokens * 15 / 100 ))")
  if [[ "$first_input_tokens" -le "$threshold" ]]; then return 0; fi

  local pct
  pct=$(echo "scale=1; $first_input_tokens * 100 / $ctx_tokens" | bc 2>/dev/null || echo "0")

  local first_k=$(( first_input_tokens / 1000 ))
  local ctx_k=$(( ctx_tokens / 1000 ))

  # Total session cost
  local total_cost
  total_cost=$(jq -r '
    [ .[] | select(.type == "message" and .message.role == "assistant") ]
    | map(.message.usage.cost.total // 0) | add // 0
  ' <(jq -s '.' "$JSONL") 2>/dev/null) || total_cost=0

  # cost_impact: (first_input_tokens / contextTokens) * total_session_cost
  local cost_impact
  cost_impact=$(echo "scale=6; $first_input_tokens * $total_cost / $ctx_tokens" | bc 2>/dev/null || echo "0")

  local evidence="First turn already has ${first_k}K input tokens (${pct}% of ${ctx_k}K context) before any real work"
  local prescription="System prompt + workspace files are consuming significant context budget before any work starts. Consider trimming verbose workspace files."

  add_finding "$(jq -nc \
    --arg pattern "workspace-overhead" \
    --argjson pattern_id 11 \
    --arg severity "medium" \
    --arg evidence "$evidence" \
    --argjson cost_impact "$(printf '%.6f' "$cost_impact")" \
    --arg prescription "$prescription" \
    '{pattern:$pattern,pattern_id:$pattern_id,severity:$severity,evidence:$evidence,cost_impact:$cost_impact,prescription:$prescription}')"
}

# ---------------------------------------------------------------------------
# Run all detectors
# ---------------------------------------------------------------------------
detect_infinite_retry
detect_non_retryable_retry
detect_tool_as_text
detect_context_exhaustion
detect_subagent_replay
detect_cost_spike
detect_skill_miss
detect_model_routing_waste
detect_cron_accumulation
detect_compaction_damage
detect_workspace_overhead

# ---------------------------------------------------------------------------
# Output JSON array
# ---------------------------------------------------------------------------
if [[ ${#FINDINGS[@]} -eq 0 ]]; then
  echo "[]"
else
  printf '%s\n' "${FINDINGS[@]}" | jq -s '.'
fi

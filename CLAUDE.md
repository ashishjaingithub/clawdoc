# clawdoc — Agent Session Diagnostics
## Engineering Standards for Claude Code Sessions

---

## 🔴 THE IRON LAW — READ THIS FIRST

**A task is NOT done until every test passes.**

clawdoc detects failure patterns in OpenClaw agent sessions. Its users run it when
something has gone wrong and they need to diagnose it. If clawdoc has a bug — a false
positive, a false negative, or a crashed detection script — it fails people exactly when
they need it most.

**The test suite has 57 tests for a reason. Keep them all green.**

---

## Project Structure

```
clawdoc/
  scripts/
    examine.sh            ← Full session examination
    diagnose.sh           ← Pattern detection runner
    prescribe.sh          ← Prescription generation
    headline.sh           ← Compact health check
    cost-waterfall.sh     ← Cost breakdown
    history.sh            ← Cross-session pattern recurrence
    check-deps.sh         ← Dependency verification
  tests/
    test-detection.sh     ← Full test suite (57 tests)
    fixtures/             ← Synthetic JSONL session files for testing
  SKILL.md                ← OpenClaw skill definition
  CHANGELOG.md
  Makefile                ← make test | make lint | make check-deps
```

---

## Test Commands — Memorize These

```bash
# FULL TEST SUITE — run after every change (57 tests)
make test

# SHELLCHECK LINTING — run when modifying any .sh file
make lint

# VERIFY DEPENDENCIES — run when changing check-deps.sh
make check-deps

# RUN A SINGLE DETECTION TEST (from test-detection.sh)
bash tests/test-detection.sh 2>&1 | grep -A2 "TEST 7"

# CHECK A SPECIFIC SCRIPT MANUALLY
bash scripts/diagnose.sh tests/fixtures/retry-loop.jsonl
```

---

## Test Pass Requirement

`make test` must exit 0 with all tests passing.
`make lint` must exit 0 with shellcheck reporting no errors.
`make check-counts` must exit 0 (verifies detector/test/fixture/version counts in docs match reality).

All three must pass before any commit. There are no coverage thresholds for shell scripts,
but every detection pattern must have at least 3 tests:
1. A true positive (the pattern is present, must detect it)
2. A true negative (the pattern is absent, must NOT flag it)
3. An edge case (borderline count, pattern almost triggers)

---

## Definition of Done — Every Box, Every Time

Before calling ANY task complete:

- [ ] `make test` — all tests pass
- [ ] `make lint` — shellcheck passes with no errors
- [ ] `make check-counts` — all hardcoded counts in docs match code reality
- [ ] If adding a new detection pattern: added to `diagnose.sh` AND `templates/patterns.json` AND `SKILL.md` pattern table AND `README.md` pattern table AND 3 tests + fixture in `tests/`
- [ ] If modifying an existing pattern: existing tests still pass AND edge cases reconsidered
- [ ] If modifying `prescribe.sh`: test that each Critical/Warning finding produces a prescription
- [ ] If modifying `headline.sh`: test that output matches the documented format exactly
- [ ] CHANGELOG.md updated with the change

---

## Pre-commit Gate

Add a `.git/hooks/pre-commit` script to enforce testing:
```bash
#!/bin/bash
echo "Running clawdoc test suite..."
make test
if [ $? -ne 0 ]; then
  echo "Tests failed. Commit blocked."
  exit 1
fi
make lint
if [ $? -ne 0 ]; then
  echo "Shellcheck failed. Commit blocked."
  exit 1
fi
echo "All checks passed."
```

To install: `cp .husky/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`

---

## How the Test Suite Works

`tests/test-detection.sh` runs each detection script against synthetic fixtures in `tests/fixtures/`. Each fixture is a minimal JSONL file crafted to contain (or not contain) a specific pattern.

**Fixture naming convention:**
```
tests/fixtures/
  retry-loop-5x.jsonl           ← triggers retry loop detection (5 consecutive calls)
  retry-loop-4x.jsonl           ← does NOT trigger (below threshold)
  tool-as-text.jsonl            ← triggers tool-as-text detection
  context-exhaustion-70pct.jsonl← triggers at 70% token threshold
  no-issues.jsonl               ← clean session, no patterns should trigger
  cron-accumulation.jsonl       ← growing inputTokens across cron runs
```

**Test assertion pattern:**
```bash
# TRUE POSITIVE — pattern must be detected
result=$(bash scripts/diagnose.sh tests/fixtures/retry-loop-5x.jsonl)
assert_contains "$result" "RETRY LOOP DETECTED" "retry loop 5x should be detected"

# TRUE NEGATIVE — pattern must NOT be detected
result=$(bash scripts/diagnose.sh tests/fixtures/retry-loop-4x.jsonl)
assert_not_contains "$result" "RETRY LOOP DETECTED" "retry loop 4x should not trigger"
```

---

## Three-Role Protocol for Significant Changes

### Role 1 — Developer
1. Before touching any script, read `tests/test-detection.sh` to understand what the tests assert
2. Write the new test(s) in `test-detection.sh` and create the fixture JSONL(s) first
3. Implement the detection or change in the script
4. `make test` — all tests pass

### Role 2 — Reviewer (re-read your work as a skeptic)
- Does the detection script handle empty JSONL files without crashing?
- Does it handle JSONL files with only 1 line?
- Does it handle sessions where `model` field is missing?
- Does the regex handle edge cases (Unicode in tool names, escaped quotes in text)?
- Is the threshold hardcoded or configurable? Should it be?
- Does `jq` fail gracefully when a field is absent vs. null vs. empty string?

### Role 3 — QA (your job is to break it)
- Run `diagnose.sh` against an empty file: `touch /tmp/empty.jsonl && bash scripts/diagnose.sh /tmp/empty.jsonl`
- Run against a file with only one line
- Run against a file with malformed JSON on one line
- Run `headline.sh` with a directory containing 0 session files
- Run `headline.sh` with a directory containing 100 session files (performance test)
- Run `cost-waterfall.sh` against a session where all cost fields are null

---

## Shell Scripting Standards

```bash
# ✅ GOOD — defensive, uses quotes, checks for null
TOOL_CALLS=$(jq -r '.message.content[]? | select(.type == "toolCall") | .name' "$LATEST" 2>/dev/null || echo "")
if [ -z "$TOOL_CALLS" ]; then
  echo "No tool calls found."
  exit 0
fi

# ❌ BAD — unquoted variables, no null check, will crash on empty input
TOOL_CALLS=$(jq -r '.message.content[] | .name' $LATEST)
echo $TOOL_CALLS | wc -l
```

**Required shellcheck compliance.** Every script must pass `shellcheck -x`:
- Always quote variables: `"$VAR"` not `$VAR`
- Always check if files exist before processing: `[ -f "$FILE" ]`
- Use `2>/dev/null` on jq calls where missing fields are expected
- Use `set -e` at the top of scripts that should fail fast

---

## Pattern Thresholds — Documented Here

| # | Pattern | Threshold | Notes |
|---|---------|-----------|-------|
| 1 | Retry loop | 5+ consecutive identical tool calls | Same tool name + input |
| 2 | Non-retryable retry | 2+ retries of a validation error | Regex-matched error text |
| 3 | Tool as text | 1+ line matching `^toolname\s+` without toolCall block | |
| 4 | Context exhaustion | inputTokens > 70% of contextTokens | >90% upgrades to high severity |
| 5 | Sub-agent replay | 3+ identical assistant messages in subagent session | Only fires on `subagent:` sessionKey |
| 6 | Cost spike | Turn > $0.50 (high), > $1.00 (critical), session > $1.00 | Configurable via `CLAWDOC_COST_TURN_HIGH`, `CLAWDOC_COST_TURN_CRITICAL`, `CLAWDOC_COST_SESSION` |
| 7 | Skill miss | toolResult matches `command not found` pattern | |
| 8 | Model routing waste | cron/heartbeat sessionKey + opus/sonnet/gpt-4o model | |
| 9 | Cron accumulation | Monotonic token growth, last > 2x first | Only fires on `cron:` sessionKey |
| 10 | Compaction damage | >40% token drop + repeated tool calls post-compaction | Uses shared `find_compaction_idx` helper |
| 11 | Workspace overhead | First-turn inputTokens > 15% of contextTokens | |
| 12 | Task drift | 3+ calls to new dirs (>50% post-compaction) OR 10+ consecutive reads | Two sub-detectors |
| 13 | Unbounded walk | 3+ unscoped recursive exec commands OR 3+ consecutive output doublings | Two sub-detectors |
| 14 | Tool misuse | Same file read 3+ times without intervening edit OR same search 3+ times | Write/edit resets read counter |

**If you change a threshold, update this table AND the test fixtures AND run `make check-counts`.**

---

## Anti-Patterns — NEVER Do These

- ❌ Never use `jq` without `2>/dev/null` when processing external files
- ❌ Never use unquoted `$VARIABLES` in shell scripts
- ❌ Never process user input without sanitizing for shell injection
- ❌ Never add a detection pattern without corresponding test fixtures
- ❌ Never ignore shellcheck warnings — fix them
- ❌ Never commit with `make test` failing

---

*Constitution alignment: Principles II (TDD), IV (Continuous Quality) — clawdoc/CLAUDE.md v1.0 — 2026-03-13*

---

## 🛡️ Self-Evaluating Guardian Protocol

This section tells Claude how to act as its own quality guardian — continuously
evaluating the codebase, identifying drift from standards, and self-healing before
any bug reaches a commit.

### SESSION START PROTOCOL — Run This Every Time, Before Touching Any Code

At the beginning of every coding session, run the full health check:

```bash
bash scripts/health-check.sh
```

If `health-check.sh` does not exist, run these manually:
1. `make test` — confirm the baseline is green before you change anything
2. `make test` — note current coverage; your changes must not lower it
3. `make lint` — confirm no pre-existing type errors
4. `make lint` — confirm no pre-existing lint violations

**If the baseline is already broken: fix it first. Do not layer new changes on top of a broken baseline.**

### CONTINUOUS EVALUATION — After Every File Edit

After every file you write or modify:
1. The PostToolUse hook in `.claude/settings.json` runs the test suite automatically
2. Read the output carefully — do not ignore failures, warnings, or coverage drops
3. If a test fails because of your change: **stop, fix it before the next edit**
4. If coverage drops below threshold: write the missing tests before moving on

This is the feedback loop. Use it.

### SESSION END PROTOCOL — Before Stopping Work

Before ending any session or declaring a task complete:
1. Run `bash scripts/health-check.sh` (full suite)
2. Confirm: all tests green ✅
3. Confirm: coverage at or above thresholds ✅
4. Confirm: no TypeScript/lint errors ✅
5. Confirm: pre-commit hook would not block ✅

If any item is red: fix it now. Do not leave a broken baseline for the next session.

### DRIFT DETECTION — Evaluating Code Against Standards

During any session, if you notice the codebase deviating from these standards, **fix
the drift proactively** — even if you were not asked to:

| Drift Pattern | Action to Take |
|---|---|
| File in `src/lib/` with no corresponding test | Create the test file |
| Function with no error handling | Add try/catch or explicit error return |
| API route with no input validation | Add Zod schema validation |
| External API call not mocked in existing test | Fix the test |
| `any` type in TypeScript | Replace with proper type |
| Silent catch block (`catch {}` or `catch (e) {}`) | Add logging and re-throw or return error |
| TODO/FIXME comment older than current sprint | Implement or remove it |
| Test that only asserts `toHaveBeenCalled()` without checking return value | Fix the assertion |

### SELF-HEALING PROTOCOL — When Tests Fail After Your Change

If your change broke a test, take these steps in order:
1. **Read the failure message completely** — do not skim
2. **Identify whether the test is right or your code is right**
   - If the test asserts the correct expected behavior: fix your code
   - If the test was testing implementation details (not behavior): fix the test
3. **Fix the root cause, not the symptom** — do not delete a failing test or change assertions to make a test pass without understanding why
4. **Re-run the test in isolation** to confirm the fix works
5. **Re-run the full suite** to confirm nothing else broke

### GUARDIAN MINDSET — How to Think in Every Session

You are simultaneously:
- The **developer** writing the feature (get it working)
- The **reviewer** checking your own work (find what could go wrong)
- The **QA engineer** trying to break it (find the edge cases)
- The **guardian** ensuring standards are maintained (check for drift)

These four perspectives are not sequential — run them in parallel throughout the session.
When you write a function, immediately ask: "how would a QA engineer break this?"
When you write a test, immediately ask: "is this testing behavior or implementation?"
When you finish a task, immediately ask: "have I lowered the quality bar anywhere?"

The answer to all three questions must be satisfactory before the task is marked done.


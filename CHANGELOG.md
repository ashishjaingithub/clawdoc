# Changelog

All notable changes to clawdoc are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] — 2026-03-14

### Added
- **Pattern 12: Task drift detection** — two sub-detectors:
  - Post-compaction directory divergence: flags when agent drifts to entirely new directories after context compaction (threshold: 3+ calls to new dirs comprising >50% of post-compaction activity)
  - Exploration spiral: flags when agent makes 10+ consecutive read/search tool calls without any edits
- 3 new test fixtures: `17-task-drift-compaction.jsonl`, `18-task-drift-exploration.jsonl`, `19-task-drift-negative.jsonl`
- 3 new test assertions (38 total tests)
- **Configurable cost spike thresholds** via environment variables:
  - `CLAWDOC_COST_TURN_HIGH` (default: 0.50) — per-turn cost for high severity
  - `CLAWDOC_COST_TURN_CRITICAL` (default: 1.00) — per-turn cost for critical severity
  - `CLAWDOC_COST_SESSION` (default: 1.00) — total session cost threshold
  - Raise these for Opus-class models where normal turns cost more

### Fixed
- **SIGPIPE crash** on session metadata extraction — `head -1` under `set -o pipefail` caused silent failures on some JSONL files; replaced with `read` builtin
- **Headline path leaking** — `headline.sh` now strips absolute paths (`/Users/name/...` → `~/...`) from evidence in headline output to avoid leaking filesystem info in shared Slack channels

### Improved
- **Contextual prescriptions** — all 12 detectors now produce prescriptions that reference the specific tool, turn, file, cost, and error from the diagnosis instead of generic advice
- **Richer evidence** — diagnoses now include turn ranges, error messages between retries, token growth trajectories, and narrative explanations of what happened

---

## [1.0.0] — 2026-03-13

Initial release.

### Added
- **11 pattern detectors** covering every major failure mode in OpenClaw sessions:
  - Pattern 1: Infinite retry loop (same tool called 5+ times consecutively)
  - Pattern 2: Non-retryable error retried (validation error → identical retry)
  - Pattern 3: Tool calls emitted as plain text (model/provider compatibility failure)
  - Pattern 4: Context window exhaustion (inputTokens > 70% of context limit)
  - Pattern 5: Sub-agent replay storm (duplicate completions delivered to parent)
  - Pattern 6: Cost spike attribution (turn > $0.50 or session cost unusually high)
  - Pattern 7: Skill selection miss ("command not found" after skill activation)
  - Pattern 8: Model routing waste (premium model on cron/heartbeat sessions)
  - Pattern 9: Cron context accumulation (session cost grows across sequential runs)
  - Pattern 10: Compaction damage (post-compaction tool call repetition)
  - Pattern 11: Workspace token overhead (baseline > 15% of context window)
- **6 shell scripts**: `examine.sh`, `diagnose.sh`, `cost-waterfall.sh`, `headline.sh`, `prescribe.sh`, `history.sh`
- **Tweetable headline output** with recoverable waste percentage
- **Brief mode** (`--brief`) for daily brief cron integration
- **self-improving-agent integration**: writes findings to `.learnings/LEARNINGS.md` with recurrence tracking and idempotent updates
- **Cross-session recurrence tracking** via `history.sh` with promotion suggestions at 3+ occurrences across 2+ sessions
- **13 synthetic test fixtures** covering all patterns plus multi-pattern and edge cases
- **35-test suite**: detection assertions, edge cases (empty session, malformed JSONL, single-turn), unit tests for all scripts, integration pipeline test
- **SKILL.md** for OpenClaw agent integration (`/clawdoc` slash command)
- `install.sh`, `check-deps.sh`, `Makefile`
- `--help` and `--version` on all 6 scripts
- Dependency checks on all scripts

---

## Future

See section 11 of `clawdoc-spec-v2.md` for planned extensions (plugin mode, OTEL integration, Canvas dashboard, auto-remediation).

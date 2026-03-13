# Changelog

All notable changes to clawdoc are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

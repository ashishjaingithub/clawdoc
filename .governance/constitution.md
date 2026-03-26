<!--
Sync Impact Report:
- Version Change: 1.0.0 -> 1.1.0
- Modified Principles: Added Principle VI (Agentic Safety)
- Added Sections: Agent Layering + Determinism in Architecture Guidelines; Model Selection in root CLAUDE.md
- Removed Sections: None
- Follow-up TODOs: None
-->
# Global Agentic Constitution

## Core Principles

### I. Simplicity First
Code should be as simple as possible. Avoid premature optimization and over-engineering. Complexity must be justified.

### II. Test-Driven Development (NON-NEGOTIABLE)
Writing tests before implementation is mandatory. Follow the Red-Green-Refactor cycle: write a failing test, implement the feature, and then refactor.

### III. Clear Documentation
All public modules, functions, and complex logic must be documented clearly to facilitate onboarding and maintainability.

### IV. Continuous Quality
All changes must pass automated tests and linting before being reviewed or merged into the main branch.

### V. Iterative Development
Build features in small, reviewable increments rather than large monolithic changes. Each increment should deliver testable value.

### VI. No Silent Failures (NON-NEGOTIABLE)
Every failure in every system must surface visibly to the founder — in the chat window, in a Slack message, or as a blocking exit code. **Silent failures are worse than no monitoring at all** because they create false confidence.

Specific requirements:
- **Scripts**: Never use `2>/dev/null` to swallow errors in critical paths. Redirect stderr only where the error is genuinely irrelevant and log it elsewhere instead.
- **Hooks**: Advisory hooks must still print clearly to stderr so output appears in the chat. A hook that prints nothing on failure is a silent failure.
- **CI**: `continue-on-error: true` is banned in CI steps that check correctness (tests, security scans, secret detection). Only use it for steps that generate supplementary reports.
- **Subprocesses**: Any subprocess invocation that can fail silently must either check its exit code explicitly or pipe stderr to a log that will be reviewed.
- **Test runners**: A test runner that silently catches exceptions and exits 0 is worse than no test runner. Test runners must exit non-zero on any unexpected error.
- **Alerting**: All alerting paths must have a fallback output (e.g., print to CI summary log) even when the primary channel (Slack) is unavailable. Never assume the notification channel is reachable.

*This principle exists because this factory is operated by one person with no operations team. The founder will not see a problem that is not surfaced. An unnoticed failure is an unresolved failure.*

### VII. Agentic Safety (NON-NEGOTIABLE)
AI/LLM components have unique failure modes that standard testing does not catch. All agentic code must:
- **Validate LLM outputs** before use — never treat raw model text as trusted structured data; parse through Zod/Pydantic schemas.
- **Defend against prompt injection** — never insert unsanitized user input directly into system prompts.
- **Fail loudly** — prefer explicit errors over silent degradation when a model returns unexpected output.
- **Bound costs** — every LLM call must use the least capable model that satisfies the task (see Model Selection in root CLAUDE.md); every call must set explicit `max_tokens`.
- **Pin model versions** — always specify the exact model version string (e.g., `claude-haiku-20241022`); never use unpinned aliases.
- **Log all AI interactions** — log model name, task label, input tokens, and output tokens for every LLM call; never include secrets or PII within logged prompts.
- **Cost-attribute every call** — every LLM call must log a `task` label so per-feature costs can be audited.
- **Gate irreversible actions** — All Tier 3+ actions per the Irreversibility Classification (see `agentic-standards/irreversibility-classification.md`) require explicit human confirmation via environment variable or HITL checkpoint before execution. Tier 3 actions without the required env var gate must not be merged.

## Architecture Guidelines

- **Modular Design**: Separate concerns into distinct modules.
- **Single Source of Truth**: Avoid data duplication where possible.
- **Error Handling**: Fail fast and log errors with appropriate context.
- **Agent Layering**: In agentic systems, maintain strict separation — `nodes/scenes` → `tools` → `services` → external APIs. Side effects belong only at the service layer. Nodes must be pure functions.
- **Determinism**: Anything producing consistent output across runs (daily puzzles, reproducible test results) must use seeded PRNGs. Never use `Math.random()` or `random.random()` in deterministic paths.

## Development Workflow

- **Branching**: Use feature branches (e.g., `feature/description`).
- **Commits**: Follow conventional commits (`feat:`, `fix:`, `docs:`).
- **Code Review**: All pull requests require at least one approval. For changes touching auth, webhooks, or LLM prompt construction, invoke the `security-reviewer` subagent before merging.

## Governance

- **Supremacy**: This Constitution supersedes all other practices and guidelines.
- **Amendments**: Amendments must be proposed via PR and reviewed by the repository owner (@ashishjain). Changes to Principle II (TDD) or Principle VI (Agentic Safety) require explicit written rationale in the PR description.
- **Compliance**: All PRs and code reviews must verify compliance with these principles.

---

## Amendment Procedure

### When Amendments Are Needed
Any change to the principles, enforcement levels, or governance policies in this constitution requires a formal amendment. Bug fixes and clarifications that do not change intent may be submitted as regular PRs.

### Amendment Process
1. **Propose**: Open a GitHub Issue labeled `constitution-amendment` with:
   - Principle(s) affected and current text
   - Proposed new text
   - Motivation and context
   - Alternatives considered
   - Impact assessment (which projects are affected, what changes in behavior)

2. **Review Window**: 72 hours minimum for community review (or immediate for security-critical amendments)

3. **Approval**: Repository owner (@ashishjain) reviews and approves by merging a PR with the trailer:
   ```
   Amendment-Approved: @ashishjain
   Amendment-Date: YYYY-MM-DD
   Amendment-Reason: <one-line summary>
   ```

4. **Version Bump**: Each amendment increments the minor version (e.g., v1.1.0 → v1.2.0)

5. **Amendment Log**: Add an entry to the Amendment Log at the bottom of this document

### Amendment Log
| Version | Date | Principle Changed | Summary | Approved By |
|---------|------|------------------|---------|-------------|
| v1.1.0 | 2026-03-04 | Initial ratification | Constitution established | @ashishjain |
| v1.2.0 | 2026-03-18 | All | Phase governance, guardian protocol, CI gates added | @ashishjain |
| v1.3.0 | 2026-03-19 | New Principle VI | No Silent Failures added as NON-NEGOTIABLE; Agentic Safety renumbered to VII | @ashishjain |

---

**Version**: 1.3.0 | **Ratified**: 2026-03-04 | **Last Amended**: 2026-03-19

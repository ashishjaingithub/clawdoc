# Testing Standards — All Projects

## Coverage Thresholds (non-negotiable)

| Metric | Minimum | Core modules* |
|--------|---------|---------------|
| Lines | 70% | 80% |
| Functions | 70% | 80% |
| Branches | 60% | 80% |

*Core modules: `pipeline.ts`, `schema.ts`, `services/`, `tools/`, agent nodes

## Mandatory Test Types

1. **Unit tests** — every function, utility, and component in isolation
2. **Integration tests** — every API endpoint, DB operation, webhook handler
3. **E2E tests** — critical user flows (hunter, gramRover use Playwright)

## TDD Workflow (Red-Green-Refactor)

```
Write failing test (RED) → verify it fails → implement minimal code (GREEN)
→ verify it passes → refactor → verify coverage
```

Never write implementation before the test. A task is NOT done until all tests pass.

## Test Isolation Rules

- Each test must be fully independent — no shared mutable state
- Mock only external dependencies (APIs, databases from other systems), never the system under test
- Use project-specific simulation modes:
  - `SIMULATE_APIS=true` for veya
  - `DRY_RUN=true` for hunter
  - In-memory Dexie adapter for gramRover (do NOT mock Dexie directly)
- Use real fixture data, not generated mocks for data processing pipelines

## Required Coverage Areas

For every new function or method, cover:
- Happy path (valid input → expected output)
- Failure path (invalid/missing input → correct error thrown)
- Boundary values (zero, empty array, null, undefined, max values)
- Error propagation (errors bubble up correctly, not swallowed)

## Anti-Patterns (Never)

- `expect(true).toBe(true)` — meaningless assertion
- Testing implementation details instead of behavior
- Shared mutable state between tests
- `// @ts-ignore` in test files
- Leaving `console.log` in tests
- Skipping error path tests ("we'll add those later")
- Modifying a test to make it pass (fix the implementation, not the test)

## LLM Eval Testing

Unit tests verify deterministic logic. **Evals** test AI output quality — they are complementary, not substitutes.

| When to write unit tests | When to write evals |
|--------------------------|---------------------|
| Parsing/formatting LLM responses | Quality of LLM-generated content |
| Deterministic business logic | Accuracy of AI classification |
| Input validation, schema checks | Relevance of AI-suggested results |

**Eval standards:**
- Golden cases must be checked in alongside feature implementation
- Evals live in `tests/evals/` — never mixed into the unit test suite (they are slow and non-deterministic)
- A failing eval is HIGH severity but does NOT block commits; a failing unit test DOES block commits
- When changing how an LLM response is parsed or post-processed, update golden cases if the output shape changes

Projects with evals: `hunter` (`src/evals/`), `summerCampSync` (`tests/evals/`)

## Regression Test Requirement

**Every bug fix must include a regression test** — no exceptions.

The test must:
1. Fail on the buggy code before the fix
2. Pass after the fix
3. Have a name that references the bug: `it('should not X when Y — regression for issue #<N>')`

Fixes without regression tests are **blocked at code review**.

## Snapshot / Golden-File Testing

Use snapshot tests for complex outputs (serialized objects, generated HTML, formatted reports):

```typescript
// Vitest snapshot — write once, review the diff in every PR that updates it
expect(formatReport(data)).toMatchSnapshot()
// To update: npx vitest --update-snapshots  ← requires manual review of diff
```

Rules: snapshot files are reviewed in every PR — a snapshot diff is a behavior diff. Never use `--update-snapshots` in CI.

## API Contract Testing

For services with multiple consumers (veya, hunter, cribsheet):
- Define request/response schema with Zod/Pydantic — this is the contract
- Consumer tests must import and validate against the schema
- Breaking schema changes require a new endpoint version — never mutate an existing endpoint silently

## Mutation Testing (Core Modules — Quarterly)

Run on `src/engine/` (dashy), `src/lib/` (appy), `src/services/` (veya):
```bash
npx stryker run   # JS/TS projects
mutmut run        # Python projects
```
Target: <30% mutation survival on core modules. >50% survival means tests are not asserting behavior.

## Pre-Commit Enforcement

All projects use Husky pre-commit hooks. Tests must pass before any commit is accepted.
Run tests manually before committing: use the project's test command (see each CLAUDE.md).

The `Stop` hook in `.claude/settings.json` enforces test passage before Claude marks any task complete.

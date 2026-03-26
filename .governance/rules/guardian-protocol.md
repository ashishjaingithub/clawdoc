# Self-Evaluating Guardian Protocol

This file defines the shared session lifecycle protocol for all projects. Each project's
`CLAUDE.md` includes a **project-specific Drift Detection table** but references this file
for the standard session rituals.

---

## SESSION START — Run Before Touching Any Code

```bash
bash scripts/health-check.sh
```

If `health-check.sh` does not exist, run the project's baseline commands manually
(see the "Test Commands" section in each project's `CLAUDE.md`):

1. Run the full unit test suite — confirm the baseline is **green** before you change anything
2. Run tests with coverage — note current coverage; your changes must not lower it
3. Run the type/lint checker — confirm no pre-existing errors

**If the baseline is already broken: fix it first. Do not layer new changes on top of a broken baseline.**

---

## CONTINUOUS EVALUATION — After Every File Edit

After every file you write or modify:

1. The PostToolUse hook in `.claude/settings.json` runs the test suite automatically
2. Read the output carefully — do not ignore failures, warnings, or coverage drops
3. If a test fails because of your change: **stop, fix it before the next edit**
4. If coverage drops below threshold: write the missing tests before moving on

This is the feedback loop. Use it.

---

## SESSION END — Before Stopping Work

Before ending any session or declaring a task complete:

1. Run `bash scripts/health-check.sh` (full suite)
2. Confirm: all tests green ✅
3. Confirm: coverage at or above thresholds ✅
4. Confirm: linter/type checker passes ✅
5. Confirm: pre-commit hook would not block ✅
6. Confirm: no hardcoded secrets or API keys ✅ (secret-scan hook also checks this automatically)
7. Confirm: if a bug was fixed, a regression test exists ✅
8. Confirm: if an LLM call was added/changed — model is pinned, `max_tokens` set, cost log present ✅
9. Confirm: no PII in log statements ✅

If any item is red: fix it now. The `Stop` hook in `.claude/settings.json` enforces tests and TypeScript automatically; the remaining gates are your responsibility.

---

## COST BUDGET AWARENESS

When working on tasks that involve LLM calls:
- Prefer `claude-haiku-20241022` for extraction, classification, summarization
- Use `claude-sonnet-20241022` as the default for reasoning tasks
- Only escalate to `claude-opus-20240229` when Sonnet genuinely fails — document why in a code comment
- If a session involves more than ~50 LLM calls total, pause and verify the task design is efficient

---

## SELF-HEALING — When Tests Fail After Your Change

1. **Read the failure message completely** — do not skim
2. **Identify whether the test is right or your code is right**
   - If the test asserts the correct expected behavior: fix your code
   - If the test was testing implementation details (not behavior): fix the test
3. **Fix the root cause, not the symptom** — do not delete a failing test or change assertions to make a test pass without understanding why
4. **Re-run the test in isolation** to confirm the fix works
5. **Re-run the full suite** to confirm nothing else broke

---

## GUARDIAN MINDSET — Every Session

You are simultaneously:
- The **developer** writing the feature (get it working)
- The **reviewer** checking your own work (find what could go wrong)
- The **QA engineer** trying to break it (find the edge cases)
- The **guardian** ensuring standards are maintained (check for drift)

These four perspectives are not sequential — run them in parallel throughout the session.

- When you write a function, immediately ask: "how would a QA engineer break this?"
- When you write a test, immediately ask: "is this testing behavior or implementation?"
- When you finish a task, immediately ask: "have I lowered the quality bar anywhere?"

The answer to all three questions must be satisfactory before the task is marked done.

---

## DRIFT DETECTION

Each project's `CLAUDE.md` contains a **project-specific Drift Detection table** listing the
drift patterns most likely to occur in that codebase. During any session, if you notice the
codebase deviating from those standards, **fix the drift proactively** — even if you were
not asked to.

See the project's `CLAUDE.md` for the specific table.

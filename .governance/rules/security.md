# Security Standards — All Projects

## Pre-Commit Mandatory Checks

Before every commit, verify:
- [ ] No hardcoded credentials, API keys, tokens, or passwords in source
- [ ] All user inputs validated (Zod schemas on all API boundaries)
- [ ] SQL queries parameterized (no string concatenation)
- [ ] No unescaped output rendered to DOM
- [ ] Rate limiting present on all public API endpoints
- [ ] Error messages do not leak internal paths, stack traces, or credentials

## Secret Management

- All secrets in environment variables — never hardcoded, never committed
- `.env` files in `.gitignore` — verify with `git status` before committing
- Validate required env vars at application startup (fail fast if missing)
- Rotate credentials immediately if accidentally committed

## LLM / Prompt Injection Security

This repo uses Anthropic, Gemini, and Ollama. LLM components have unique attack surfaces:

### Prompt Injection Defense
- **Never concatenate unsanitized user input into system prompts.** A user who controls prompt content can override instructions.
- Separate system instructions from user content structurally (use the `system` parameter, not the `user` message, for instructions).
- Validate and sanitize any content fetched from external sources (web pages, emails, API responses) before inserting into prompts.

```typescript
// NEVER — user input can escape context and override system prompt
const prompt = `You are a helpful assistant. Answer this: ${userInput}`

// ALWAYS — user content in user role, instructions in system
const response = await client.messages.create({
  system: 'You are a helpful assistant. Answer only factual questions.',
  messages: [{ role: 'user', content: sanitize(userInput) }],
})
```

### LLM Output Validation
- Always parse structured LLM output through Zod/Pydantic before use.
- Treat model output as untrusted external data — it can contain unexpected shapes, injected instructions, or garbage.
- Never `eval()` or dynamically execute LLM-generated code.

### Model API Security
- API keys for Anthropic/Gemini/OpenAI must never appear in client-side bundles.
- Set `ANTHROPIC_API_KEY`, `GEMINI_API_KEY` only in server environment — validate at startup.
- Implement per-user or per-session rate limiting on routes that call LLMs.

## Project-Specific Attack Surfaces

| Project | Key Risks | Required Controls |
|---------|-----------|-------------------|
| veya | Twilio/Retell webhook auth, call_id deduplication, **LLM output before side effects** | Verify webhook signatures; idempotency keys on all tool invocations; **Zod-validate every LLM response before CRM write/SMS/calendar event** |
| hunter | LLM prompt injection, email header injection | Sanitize user content before LLM context; validate email headers |
| appy | Chrome extension permissions, resume PII, local file access | Minimal extension permissions (MV3); never fabricate resume content |
| gramRover | ZIP file traversal, malicious JSON payloads | Validate zip paths; schema-validate all parsed Instagram data |
| aidose | Anthropic API key management, unattended operation | Rotate API keys regularly; log all generation operations |
| cribsheet | Image upload validation, vision server inputs | Validate MIME type and file size; reject non-image uploads |
| summerCampSync | Gemini API key exposure in client bundle | API key must never be in client-side code |
| cracked | Anthropic hint generation, localStorage manipulation | Mock Anthropic in tests; validate localStorage data before use |

## OWASP Top 10 Response Protocol

When a vulnerability is found:
1. Stop all other work immediately
2. Invoke the `security-reviewer` agent
3. Fix critical issues before any other commit
4. Rotate any exposed credentials
5. Review rest of codebase for similar patterns

## Dependency Security

### Automated Scanning (CI Gate — not optional)

Run on every commit via CI. Findings at HIGH or CRITICAL severity **block merge**:
```bash
npm audit --audit-level=high    # Node.js projects
pip-audit --fail-on CRITICAL    # Python projects (aidose, cribsheet vision server)
```

### Secret Scanning in Git History

Run before any new contributor onboarding or when a credential is suspected leaked:
```bash
# Detect secrets committed to history
git log --all --full-history -- '**/*.ts' '**/*.js' '**/*.py' | \
  grep -iE 'sk-ant-|AIza|AKIA|BEGIN PRIVATE KEY'
```

The `secret-scan.sh` PostToolUse hook catches new secrets at edit time. Use the above to audit history.

### License Compliance

Run before adding new dependencies to any project:
```bash
npx license-checker --onlyAllow 'MIT;Apache-2.0;BSD-2-Clause;BSD-3-Clause;ISC;CC0-1.0' --excludePrivatePackages
```
Reject GPL, LGPL, AGPL, and proprietary licenses without legal review.

### Credential Rotation Schedule

| Credential | Rotation interval | Owner |
|---|---|---|
| Anthropic API key | Every 90 days | @ashishjain |
| Gemini API key | Every 90 days | @ashishjain |
| Twilio auth token | Every 180 days | @ashishjain |
| HubSpot API key | Every 90 days | @ashishjain |
| JWT secrets | Every 180 days or on personnel change | @ashishjain |
| DB passwords | Every 180 days | @ashishjain |

**Rotate immediately** if a credential is accidentally committed, even if removed from HEAD (git history retains it).

## PII Handling Standards

Projects in this repo handle personally identifiable information:

| Project | PII Types | Classification |
|---------|-----------|---------------|
| appy | Resume content, job applications, email | **Restricted** |
| veya | Caller phone numbers, call transcripts | **Restricted** |
| hunter | Lead names, company data, email | **Confidential** |
| gramRover | Instagram username, location data | **Confidential** |
| cribsheet | Room photos (may contain people/belongings) | **Confidential** |
| aidose | Instagram content | **Internal** |

**Rules for Restricted data:**
1. Never log PII in plaintext — hash or redact before logging
2. Never include PII in error messages returned to clients
3. Never send PII to third-party analytics without explicit user consent
4. Enforce data retention: delete Restricted data after its purpose is fulfilled
5. All Restricted data at rest must use field-level encryption or encrypted DB volumes

**PII Detection in logs** — before any log statement containing user-supplied data:
```typescript
// BAD — logs raw PII
logger.info({ phone: caller.phone }, 'Incoming call')

// GOOD — hash for correlation, never log raw
logger.info({ phone_hash: hashPhone(caller.phone) }, 'Incoming call')
```

Address HIGH and CRITICAL findings before deployment. Document accepted LOW/MEDIUM findings.

# Irreversibility Classification for Agent Actions

**Version**: 1.3.0
**Last Reviewed**: 2026-03-18
**Owner**: @ashishjain

---

## Overview

Not all agent actions carry the same risk. This classification maps every external action type in the agenticLearning workspace to an irreversibility tier and specifies the required human oversight level for each.

The goal is to ensure that the consequence of an error is proportionate to the oversight applied. Trivially reversible actions need no special gate. Catastrophic actions require two humans to authorize. Everything in between has a defined, mandatory checkpoint.

This document is **non-negotiable governance**. Per the [Constitution](constitution.md) Principle VI (Agentic Safety), all Tier 3+ actions require explicit human confirmation via environment variable or HITL checkpoint before execution.

---

## Tiers

| Tier | Name | Definition | HITL Requirement |
|------|------|------------|------------------|
| 0 | Trivially Reversible | Local, in-process, or ephemeral actions with no external state change. Can be undone instantly. | None |
| 1 | Reversible | Persistent state change with a clear and accessible rollback path. Undo is possible with minimal effort. | Code review adequate |
| 2 | Moderately Reversible | External or semi-permanent state change. Can be corrected, but correction requires deliberate effort and may leave a trace. | Confirmation on first occurrence or for high-impact variants |
| 3 | Highly Irreversible | Action reaches an external party in real time. Once dispatched, the receiving party is affected. Technical deletion does not undo the impact. | Explicit HITL before every execution — env var gate required |
| 4 | Catastrophic | Affects large numbers of external parties simultaneously, or permanently destroys data with no recovery path. | Two-person authorization required; automated execution prohibited |

---

## Action Registry

| Action | Project | Tier | Current HITL | Gap |
|--------|---------|------|-------------|-----|
| Console.log statement | all | 0 | console-log-check hook (warns) | None |
| Local file edit | all | 0 | None | None |
| Git commit | all | 0 | None | None |
| Git push | all | 0 | git-push-guard (warn only) | None |
| BullMQ job enqueue | veya | 1 | None | None — job can be removed from queue before processing |
| Image generation (Anthropic API call) | aidose | 1 | CostGuard | Adequate — cost bounded; no external state change |
| Lead research web fetch | hunter | 1 | None | Read-only; injection risk documented in hunter threat model |
| PostgreSQL write (veya) | veya | 1 | None | None — rollback available via transaction |
| Local image file write (Pillow) | aidose | 1 | None | None — local artifact |
| HubSpot contact score update (<=3 pts) | veya / hunter | 2 | None | Acceptable — low-impact update; audit log required |
| HubSpot contact score update (>3 pts) | veya / hunter | 2 | `HUNTER_CONFIRM_CRM_SCORE_UPDATE=true` gate in `hunter/backend/src/services/hubspot.ts:updateContactScore` | **IMPLEMENTED 2026-03-18** — gate fires when delta >3 pts; exact lowercase string check |
| CRM lead creation (new contact) + deal | hunter | 2 | `HUNTER_CONFIRM_CRM_WRITE=true` gate in `processReplies.ts` | **IMPLEMENTED 2026-03-18** — gate wraps `upsertContact` + `createDeal`; defaults off |
| HubSpot contact email/phone update | veya / hunter | 2 | `HUNTER_CONFIRM_CRM_FIELD_UPDATE=true` gate in `hunter/backend/src/services/hubspot.ts:upsertContact` | **IMPLEMENTED 2026-03-18** — gate wraps PATCH path (existing contact updates only); new contact creation unaffected |
| Google Calendar booking | veya | 3 | `VEYA_CONFIRM_BOOKING=true` gate in `calendar.js:bookSlot` | `VEYA_CONFIRM_BOOKING=true` required — **IMPLEMENTED** |
| Twilio SMS send | veya | 3 | `VEYA_CONFIRM_SMS=true` gate in `notifications.js:sendSms` | `VEYA_CONFIRM_SMS=true` required — **IMPLEMENTED** |
| Retell call initiation | veya | 3 | `VEYA_CONFIRM_CALL=true` gate in `retell.js:transferCall` | `VEYA_CONFIRM_CALL=true` required — **IMPLEMENTED** |
| Hunter email send (DRY_RUN=false) | hunter | 3 | DRY_RUN env var (binary gate) + pre-send audit log | Pre-send audit log implemented — **IMPLEMENTED 2026-03-18** |
| Instagram post publish | aidose | 3 | `AIDOSE_CONFIRM_POST=true` gate in `queue_manager.py:mark_as_posted` | `AIDOSE_CONFIRM_POST=true` required — **IMPLEMENTED** |
| GDPR personal data erasure (veya call records) | veya | 3 | `VEYA_CONFIRM_GDPR_ERASE=true` gate in `veya/src/routes/gdpr.js` | **IMPLEMENTED 2026-03-18** — POST /api/gdpr/erase; anonymizes call_events rows |
| GDPR lead data erasure (hunter leads) | hunter | 3 | `HUNTER_CONFIRM_GDPR_ERASE=true` gate in `hunter/backend/src/routes/gdpr.ts` | **IMPLEMENTED 2026-03-18** — POST /api/v1/gdpr/erase; anonymizes leads rows |
| Mass email blast (>50 recipients) | hunter | 4 | None | **GAP: must be prohibited in automation; two-person sign-off required** |
| Account deletion (any platform) | any | 4 | N/A — prohibited in automation | Automated deletion is prohibited; must be manual |
| Instagram account deactivation | aidose | 4 | N/A — prohibited in automation | Automated deactivation is prohibited; must be manual |

---

## Tier 0 — Trivially Reversible: Details

Actions in this tier require no special handling. They include:

- **Console/log output**: Ephemeral. No external state.
- **Local file writes**: Reversible by editing or deleting the file.
- **Git commits**: Reversible via `git revert` or `git reset`. The pre-push guard provides a final review window.
- **In-memory computation**: No persistence; no external effect.

No action is required for Tier 0 items.

---

## Tier 1 — Reversible: Details

Actions in this tier write to a persistent store but have a clear rollback path:

- **Database writes with transactions**: Rollback is available within a transaction window. In PostgreSQL (veya), row-level locking and explicit transaction management provide rollback.
- **BullMQ job enqueue**: A job can be removed from the queue via the Bull dashboard or `queue.remove()` before a worker picks it up. After a worker starts, the job may still be retried or failed deliberately.
- **Image generation (API call)**: The API call costs tokens/credits but produces only a local artifact. The artifact can be discarded.
- **Web fetch (lead research)**: Read-only. No external state is modified. The injection risk is documented in the hunter threat model but does not change the irreversibility tier of the action itself.

Code review is the adequate control at this tier.

---

## Tier 2 — Moderately Reversible: Details

Actions in this tier modify external state that can be corrected, but correction leaves a trace and requires deliberate effort:

- **CRM updates**: HubSpot maintains a full audit history of contact record changes. A wrong update can be reverted, but the history is permanent. The original incorrect value is visible in the change log.
- **New lead creation**: A CRM contact can be deleted, but any email correspondence associated with it is permanent.

> **Note**: Calendar event creation was previously listed here but is classified as **Tier 3** — see the Action Registry and Tier 3 section. Invitees receive notification immediately; a cancellation is itself an external communication.

**Required control**: Confirmation on first occurrence for new contacts. Confirmation for high-impact field changes (email, phone, contact score change >3 points).

---

## Tier 3 — Highly Irreversible: Details

Actions at this tier deliver immediate real-world effects to external parties who cannot be "un-notified":

- **SMS send**: The recipient receives the message on their phone. There is no recall mechanism. The sender's number is logged in the recipient's message history permanently.
- **Email send**: The email arrives in the recipient's inbox. Even if retracted (supported by some clients), the notification was delivered. Reputation impact is immediate and cannot be undone.
- **Calendar booking**: The invitation appears in the attendee's calendar and generates a notification. Cancellations require a second communication that may itself be damaging.
- **Retell call initiation**: A real person answers their phone. The call happened. There is no way to "un-call" someone.
- **Instagram post**: The post is immediately visible to all followers and appears in hashtag feeds. Screenshots may have been taken before deletion. Deletion does not remove it from third-party scrapers or caches.

**Required control**: Explicit HITL via environment variable gate before every execution. See implementation pattern below.

> **Deployment Requirement**: New code paths that introduce or extend Tier 3 actions MUST be deployed behind `isFeatureEnabled()` from `packages/shared-types/src/feature-flags.ts`. The flag defaults to `false` in production.

---

## Tier 4 — Catastrophic: Details

Actions at this tier are prohibited from being executed by automated agents under any circumstances:

- **Mass email blast**: Sending emails to more than 50 recipients simultaneously via the agent pipeline is prohibited. If bulk outreach is needed, it must be executed via a dedicated bulk-send tool with explicit human authorization at the list level, not generated by an LLM.
- **Account deletion**: Deleting any external account (Instagram, HubSpot, Twilio, Google) is prohibited in automation. These actions must be performed manually by the account owner.

**Required control**: Two-person authorization required for any Tier 4 operation. No automated execution path should exist.

---

## Implementation Pattern for Tier 3 Actions

All Tier 3 actions in the agenticLearning workspace must follow this pattern before any external action is dispatched. Deviating from this pattern is a security defect that will be flagged as HIGH severity by the `code-reviewer` agent.

```typescript
// Required pattern for ALL Tier 3 actions (TypeScript)
async function executeIrreversibleAction(action: Tier3Action): Promise<void> {
  // 1. Log intent — write BEFORE any external call
  logger.info(
    { action: action.type, target: action.target, tier: 3 },
    'TIER-3 ACTION: About to execute irreversible action'
  );

  // 2. Check explicit confirmation env var — MUST be the lowercase string "true".
  // Any other truthy value ("1", "yes", "TRUE", "True") is rejected.
  // This prevents accidental authorization from environment variable type coercion.
  if (process.env[action.confirmEnvVar] !== 'true') {
    throw new Error(
      `Tier-3 action requires ${action.confirmEnvVar}=true in environment. ` +
      `Action: ${action.type}. Target: ${action.target}. ` +
      `Set this variable explicitly in your production environment to authorize this action. ` +
      `The value must be exactly the lowercase string "true" — "1", "yes", "TRUE" are not accepted.`
    );
  }

  // 3. Execute the action
  const result = await action.execute();

  // 4. Audit log — write AFTER execution with outcome
  logger.info(
    { action: action.type, target: action.target, tier: 3, success: true, resultId: result?.id },
    'TIER-3 ACTION: Completed successfully'
  );
}
```

```python
# Required pattern for ALL Tier 3 actions (Python — for aidose)
import os
import logging

logger = logging.getLogger(__name__)

def execute_irreversible_action(action):
    """Execute a Tier 3 irreversible action with mandatory HITL gate."""
    # 1. Log intent — write BEFORE any external call
    logger.info(
        "TIER-3 ACTION: About to execute irreversible action "
        "action=%s target=%s tier=3",
        action.action_type, action.target
    )

    # 2. Check explicit confirmation env var
    confirm_var = action.confirm_env_var
    if os.environ.get(confirm_var) != "true":
        raise RuntimeError(
            f"Tier-3 action requires {confirm_var}=true in environment. "
            f"Action: {action.action_type}. Target: {action.target}. "
            f"Set this variable explicitly in your production environment "
            f"to authorize this action."
        )

    # 3. Execute the action
    result = action.execute()

    # 4. Audit log — write AFTER execution with outcome
    logger.info(
        "TIER-3 ACTION: Completed successfully "
        "action=%s target=%s tier=3 result_id=%s",
        action.action_type, action.target, getattr(result, 'id', None)
    )

    return result
```

### Environment Variable Registry for Tier 3 Gates

| Variable | Project | Action Gated | Must Be Set To |
|----------|---------|-------------|----------------|
| `VEYA_CONFIRM_SMS` | veya | Twilio SMS send | `true` |
| `VEYA_CONFIRM_BOOKING` | veya | Google Calendar booking | `true` |
| `VEYA_CONFIRM_CALL` | veya | Retell call initiation | `true` |
| `HUNTER_CONFIRM_SEND` | hunter | Email send (all recipients) | `true` |
| `HUNTER_CONFIRM_CRM_WRITE` | hunter | HubSpot upsertContact + createDeal on qualified replies | `true` |
| `HUNTER_CONFIRM_CRM_SCORE_UPDATE` | hunter | HubSpot contact score update (>3 pts delta) | `true` |
| `HUNTER_CONFIRM_CRM_FIELD_UPDATE` | hunter | HubSpot email/phone field update on existing contact | `true` |
| `VEYA_CONFIRM_GDPR_ERASE` | veya | GDPR Article 17 personal data erasure (call records) | `true` |
| `HUNTER_CONFIRM_GDPR_ERASE` | hunter | GDPR Article 17 lead data erasure | `true` |
| `AIDOSE_CONFIRM_POST` | aidose | Instagram post publish | `true` |

These variables must be set explicitly in production environment configuration. They must **never** be set in `.env.example`, `.env.test`, or any development default configuration files. Setting them must require a deliberate human action.

> **Exception**: `HUNTER_CONFIRM_CRM_WRITE` is documented in `hunter/backend/.env.example` as `HUNTER_CONFIRM_CRM_WRITE=false` (explicitly off) to make its existence discoverable. The value `false` is not an authorization — it is a reminder that opt-in is required.

---

## Remediation Plan

### Tier 3 Actions Without HITL — Priority HIGH — Target: 2026-Q2

**Status as of 2026-03-18**: All items (1–5) are COMPLETE.

**1. veya — SMS send (Twilio)** ✅ IMPLEMENTED 2026-03-18
- `VEYA_CONFIRM_SMS=true` env var gate added to `veya/src/services/notifications.js:sendSms`.
- Gate is skipped when `SIMULATE_APIS=true` (test mode) so existing tests continue to pass.
- Remaining: add structured pre-send log entry and regression test.

**2. veya — Calendar booking (Google Calendar)** ✅ IMPLEMENTED 2026-03-18
- `VEYA_CONFIRM_BOOKING=true` env var gate added to `veya/src/services/calendar.js:bookSlot`.
- Gate is skipped when `SIMULATE_APIS=true` (test mode) so existing tests continue to pass.
- Remaining: add structured pre-booking log entry and regression test.

**3. veya — Retell call initiation** ✅ IMPLEMENTED 2026-03-18
- `VEYA_CONFIRM_CALL=true` env var gate added to `veya/src/services/retell.js:transferCall`.
- Gate is skipped when `SIMULATE_APIS=true` (test mode) so existing tests continue to pass.
- Remaining: add structured pre-call log entry and regression test.

**4. hunter — Email send (DRY_RUN=false)** ✅ IMPLEMENTED 2026-03-18
- Structured pre-send audit log added to all three transport layers: `gmail.ts`, `smtp.ts`, `resend.ts`.
- Gate upgraded: `DRY_RUN` must be exactly `'false'` (not merely `!== 'true'`); any other value blocks the send and logs `{ dryRun: true }`.
- Before each real send, logs: `{ action: "email_send_pre_audit", recipientDomain, subjectHash (SHA256 first 8 chars), sendId (uuid), tier: 3, gate: "DRY_RUN=false", transport }`.
- Remaining: add regression test asserting sends are blocked when `DRY_RUN !== 'false'`.

**5. aidose — Instagram post publish** ✅ IMPLEMENTED 2026-03-18
- `AIDOSE_CONFIRM_POST=true` env var gate added to `aidose/modules/queue_manager.py:mark_as_posted`.
- Remaining: add structured pre-post log entry and regression test; add draft staging step (see aidose threat model HITL gap R1).

### Tier 2 Actions Needing Improvement — Priority MEDIUM

**Status as of 2026-03-18**: All items are COMPLETE.

- ~~**HubSpot contact score update >3 pts**: Add a confirmation flag or human-review queue entry before committing.~~ ✅ **RESOLVED 2026-03-18** — `HUNTER_CONFIRM_CRM_SCORE_UPDATE=true` gate implemented in `hunter/backend/src/services/hubspot.ts:updateContactScore`. Gate fires only when delta >3 pts; ≤3 pt updates pass through unconditionally.
- ~~**HubSpot contact email/phone update**: Cross-reference against a verified data source before writing.~~ ✅ **RESOLVED 2026-03-18** — `HUNTER_CONFIRM_CRM_FIELD_UPDATE=true` gate implemented in `hunter/backend/src/services/hubspot.ts:upsertContact`. Gate wraps the PATCH path (existing contact updates); new contact creation is governed by the existing `HUNTER_CONFIRM_CRM_WRITE` gate in `processReplies.ts`.
- ~~**New CRM lead creation**: Log as first-occurrence event; add to a review queue for manual verification.~~ ✅ **RESOLVED 2026-03-18** — `HUNTER_CONFIRM_CRM_WRITE=true` gate implemented in `hunter/backend/src/agent/nodes/processReplies.ts` wrapping `upsertContact` + `createDeal`.

---

## Compliance Verification

The `code-reviewer` and `security-reviewer` subagents must check the following during every code review that touches an action in this registry:

1. Is the action tier correctly identified for the implementation?
2. For Tier 3 actions: is the env var gate implemented? Is the pre-action log entry present? Is there a regression test for the gate?
3. For Tier 4 actions: is there any automated execution path? If so, block the PR.
4. Are the env var names consistent with the registry table above?
5. Are confirmation env vars excluded from all development default configuration files?

---

*Irreversibility Classification v1.2.0 — 2026-03-18*

# Structured Logging Standard

**Scope**: All Live-phase projects (veya, hunter). Recommended for Iterate-phase projects.
**Loaded when**: working with `**/src/server*`, `**/src/index*`, `**/src/services/**`, `**/src/workers/**`

## Mandate

All production log entries MUST be valid JSON with these required fields:

```json
{
  "level": "info|warn|error|debug",
  "ts": "2026-03-18T21:00:00.000Z",
  "msg": "Human-readable message",
  "project": "veya|hunter|aidose",
  "trace_id": "optional-correlation-id"
}
```

Error logs MUST additionally include:
```json
{
  "err": {
    "type": "TypeError|ValidationError|...",
    "message": "...",
    "stack": "..."
  },
  "context": {
    "call_id": "...",
    "user_id": "...",
    "action": "sendSms|bookSlot|..."
  }
}
```

## Required Libraries

- **Node.js**: [pino](https://github.com/pinojs/pino) — `const log = require('pino')(); log.info({ trace_id }, 'message')`
- **Python**: [structlog](https://www.structlog.org/) — `structlog.get_logger().info("message", trace_id=trace_id)`

## Anti-Patterns (code-reviewer flags these as HIGH)

```javascript
// ❌ WRONG — console.log is not structured
console.log('SMS sent to', phone);
console.error(error);

// ✅ CORRECT — pino structured log
log.info({ action: 'sms.sent', phone: maskPhone(phone), trace_id }, 'SMS sent');
log.error({ err, action: 'sms.failed', trace_id }, 'SMS send failed');
```

## PII in Logs

**Never log raw PII**. Use masking functions before logging:
- Phone numbers: `maskPhone(number)` → `+1555***1234`
- Email addresses: `maskEmail(email)` → `j***@example.com`
- Lead names: `maskName(name)` → `J*** D***`

The `hunter/src/lib/langsmith-mask.js` masking utilities can be reused for log masking.

## Audit Log Requirements

Tier 3 actions MUST produce an audit log entry with:
```json
{
  "level": "info",
  "ts": "...",
  "msg": "Tier3 action executed",
  "project": "veya",
  "action": "sms.sent",
  "authorized_by": "VEYA_CONFIRM_SMS=true",
  "target": "+1555***1234",
  "result": "success|failure",
  "trace_id": "..."
}
```

## Enforcement

- `console-log-check.sh` hook warns on `console.log` in production code
- code-reviewer flags unstructured logging as **HIGH** severity
- Live-phase CI fails if pino/structlog is not in dependencies

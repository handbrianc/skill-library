---
name: repo-health--phase-7-security
description: "INTERNAL SUBSKILL of repo-health. Security review — CVE scan, static analysis, credential exposure. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 7 — Security Review

## Step 7.1 — Third-Party Vulnerability Scan

```bash
./skills/repo-health/scripts/scan-security.sh --vuln-scan
```

Aggregate CVE findings: **Severity, Package, Current Version, Fixed Version, CWE**.

**Any package with a known CVE → CRITICAL regardless of the CVE's reported severity.** A dependency with any CVE is an exploitable attack surface. Do NOT downgrade to HIGH or lower. This finding MUST be addressed in the remediation loop (Phase 10).

## Step 7.2 — Static Code Security Scan

```bash
./skills/repo-health/scripts/scan-security.sh --vuln-scan
```

### Patterns to Flag

| Pattern | Severity | Example |
| ------------------------------- | -------- | --------------------------------- |
| SQL string concatenation | CRITICAL | `db.query("SELECT * FROM u WHERE id=" + id)` |
| eval(user_input) | CRITICAL | `eval(req.body.code)` |
| innerHTML without sanitize | CRITICAL | `el.innerHTML = userData` |
| Command injection | CRITICAL | `exec(userCmd)` |
| Hardcoded password/secret | CRITICAL | `password: "hunter2"` |
| JWT none algorithm | CRITICAL | `{ algorithm: "none" }` |
| Insecure random | MEDIUM | `Math.random()` for tokens |
| Path traversal | CRITICAL | `fs.readFile(userPath)` |
| XXE | CRITICAL | XML parsing without safe settings |
| Deserialization of untrusted | CRITICAL | `pickle.load(userData)` |
| Missing rate limiting | MEDIUM | Auth endpoints without ratelimit |
| Missing CSRF protection | CRITICAL | Stateful POST without token |
| Insecure cookie flags | MEDIUM | Cookie without httpOnly, secure |
| Server info disclosure | LOW | Banner exposing version in header |

## Step 7.3 — Credential Exposure

```bash
./skills/repo-health/scripts/scan-security.sh --credential-exposure
```

Any committed secret = **CRITICAL** — escalate to immediate remediation.

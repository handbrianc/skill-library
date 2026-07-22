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

## Step 7.2 — Static Code Security Scan

```bash
./skills/repo-health/scripts/scan-security.sh --vuln-scan
```

### Patterns to Flag

| Pattern | Severity | Example |
| ------------------------------- | -------- | --------------------------------- |
| SQL string concatenation | CRITICAL | `db.query("SELECT * FROM u WHERE id=" + id)` |
| eval(user_input) | CRITICAL | `eval(req.body.code)` |
| innerHTML without sanitize | HIGH | `el.innerHTML = userData` |
| Command injection | CRITICAL | `exec(userCmd)` |
| Hardcoded password/secret | HIGH | `password: "hunter2"` |
| JWT none algorithm | HIGH | `{ algorithm: "none" }` |
| Insecure random | MEDIUM | `Math.random()` for tokens |
| Path traversal | HIGH | `fs.readFile(userPath)` |
| XXE | HIGH | XML parsing without safe settings |
| Deserialization of untrusted | CRITICAL | `pickle.load(userData)` |
| Missing rate limiting | MEDIUM | Auth endpoints without ratelimit |
| Missing CSRF protection | HIGH | Stateful POST without token |
| Insecure cookie flags | MEDIUM | Cookie without httpOnly, secure |
| Server info disclosure | LOW | Banner exposing version in header |

## Step 7.3 — Credential Exposure

```bash
./skills/repo-health/scripts/scan-security.sh --credential-exposure
```

Any committed secret = **CRITICAL** — escalate to immediate remediation.

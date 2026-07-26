---
name: repo-health--phase-0-environment
description: "INTERNAL SUBSKILL of repo-health. Environment readiness gate — validates baseline tools and prerequisites. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 0 — Environment Readiness (Gate)

**Goal:** Validate baseline tools required for all audits (bash, git, node/npm, jq, find)
and report language/project-specific tools as informational. If any required baseline
tool is missing, **abort immediately**.

## Required Environment

- Bash >= 4.0
- Node.js >= 18
- Git installed and accessible
- `jq` for JSON parsing
- GNU `find` with `-maxdepth` support
- GNU `grep` with BRE alternation support (`\|`)
- `timeout`/`gtimeout` (macOS: `brew install coreutils`)
- For security: `npm audit`, Grype or Syft
- For coverage: project's test runner with coverage reporter
- For complexity: `eslint --quiet` with `complexity` rule, or `tsq`

## Run

```bash
./skills/repo-health/scripts/scan-environment.sh --check-tools
```

**If any core utility prints `MISSING/BROKEN`, or any helper script prints `SKILL_ERR` / `SKILL_MISSING`:**

- Collect all missing/malformed items into a single block
- **ABORT — do not proceed to PHASE 1**
- Report using this template:

```markdown
## 🚫 ENVIRONMENT GAP — Cannot Proceed

The following tools are missing or broken. Install them before re-running:

| Tool | Status | Install Command |
| ---- | ------ | --------------- |
| bash | MISSING | (system package manager) |
| ...  | ...    | ...             |
```

Optional language/test/security tools may print `MISSING (optional)` — only treat them as
blocking if the repo's stack requires them.

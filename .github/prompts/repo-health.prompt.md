---
description: Repository health audit — report mode (findings only) by default; append "fix" to remediate
argument-hint: '[fix] — optional, default: report mode'
agent: agent
---
STEP 1 — RESOLVE MODE FROM THE ARGUMENTS. The text the user typed after the
`/repo-health` command name in their message is the argument string. Apply the FIRST
rule that matches:

- Argument contains `fix`, `mode=fix`, `remediate`, or `fix findings` → **mode=fix**
- Argument is empty, `report`, or anything else → **mode=report** (DEFAULT)

State the resolved mode in one line before doing anything else. If you cannot find any
argument text in the user's message, use mode=report.

STEP 2 — RUN THE AUDIT. Follow the repo-health workflow defined in `skills/repo-health/SKILL.md`.
Read this repository's copy if it exists; otherwise read the globally installed copy at
`~/.copilot/skills/repo-health/SKILL.md`. Then read the phase subskills
(`skills/repo-health--phase-*/SKILL.md`) and the scripts under `skills/repo-health/scripts/`
from the same location as the SKILL.md you used (run scripts from the audited repo root).

Mode behavior:

- **mode=report (DEFAULT)** — full audit + graded findings report. No code changes;
  do not run fix scripts with write access.
- **mode=fix** — additionally run the Phase 10 remediation loop (fix → re-audit → loop
  until only NITPICKs remain; changes left uncommitted for review).

Never auto-fix unless mode=fix was resolved.

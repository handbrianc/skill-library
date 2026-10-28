---
description: Repository health audit in FIX mode — audit + remediation loop (fixes findings, re-audits, loops)
argument-hint: '[optional extra instructions]'
agent: agent
---
Run the repo-health audit defined in `skills/repo-health/SKILL.md` with **mode=fix**,
explicitly set — do not resolve the mode from context or arguments.

Read this repository's copy of the SKILL.md if it exists; otherwise read the globally
installed copy at `~/.copilot/skills/repo-health/SKILL.md`. Then read the phase subskills
(`skills/repo-health--phase-*/SKILL.md`) and the scripts under `skills/repo-health/scripts/`
from the same location as the SKILL.md you used (run scripts from the audited repo root).

**mode=fix means:** full audit (Phases 0-9) + synthesis/classification/grade, then the
Phase 10 remediation loop — fix findings, re-audit, and iterate until only NITPICKs
remain, leaving all changes uncommitted for review.

Any extra text after the command is additional instruction context for the run, not a
mode selection.

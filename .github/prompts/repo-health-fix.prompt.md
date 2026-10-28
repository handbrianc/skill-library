---
description: Repository health audit in FIX mode — audit + remediation loop (fixes findings, re-audits, loops)
argument-hint: '[optional extra instructions]'
agent: agent
---
Run the repo-health audit defined in [skills/repo-health/SKILL.md](../../skills/repo-health/SKILL.md)
on this repository with **mode=fix**, explicitly set — do not resolve the mode from
context or arguments.

Read the SKILL.md first and follow it as the workflow, including its phase subskills
(`skills/repo-health--phase-*/SKILL.md`) and the scripts under `skills/repo-health/scripts/`
(run them from the audited repo root).

**mode=fix means:** full audit (Phases 0-9) + synthesis/classification/grade, then the
Phase 10 remediation loop — fix findings, re-audit, and iterate until only NITPICKs
remain, leaving all changes uncommitted for review.

Any extra text after the command is additional instruction context for the run, not a
mode selection.

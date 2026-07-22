---
name: repo-health
description: "Comprehensive repository health audit — code quality, linting, docs, specs, tests, security, SBOM, 12-Factor App compliance, and technical debt review. Use when user says 'review this repo', 'audit this project', 'health check', 'quality gate', or requests a full codebase analysis. NOT for PR-scoped or incremental reviews."
---

# Repository Health Audit Orchestrator

A rigorous, deterministic repository audit covering nine dimensions. Produces a prioritized, actionable plan.

> **Prerequisite:** Run `npx gitnexus analyze --force` on the target repo before starting.

## Critical Constraints

### MUST DO
- Produce a prioritized, actionable plan before considering the audit complete
- Flag as CRITICAL any finding that is security-relevant or blocking release
- Run actual scanners/tool commands — do not speculate about outcomes
- Preserve the original commit (operate on HEAD, never mixed working tree + staging)
- **Run PHASE 0 before all other phases** — abort if any required tool is missing

### MUST NOT DO
- Never suppress type errors with `as any`, `@ts-ignore`, or `@ts-expect-error`
- Never delete failing tests to make a build pass
- Never commit changes without running `gitnexus_detect_changes()`
- Never edit any symbol without first running `gitnexus_impact(target, direction: "upstream")`
- Never use find-and-replace for renames — use `gitnexus_rename`
- Never treat an N/A dimension as a failure — document rationale

## Scope

**In scope:** Code quality, documentation, OpenSpec alignment, test suite health, security posture, supply-chain (SBOM/licenses), 12-Factor compliance, linter configuration, technical debt.

**Out of scope:** Infrastructure-as-code, CI/CD pipelines themselves, external services.

## Phase Reference

| # | Dimension | Subskill |
|---|-----------|----------|
| 0 | Environment Readiness (Gate) | `repo-health--phase-0-environment` |
| 1 | Project Discovery | `repo-health--phase-1-discovery` |
| 2 | Code Quality | `repo-health--phase-2-code-quality` |
| 3 | Technical Debt | `repo-health--phase-3-tech-debt` |
| 4 | Documentation | `repo-health--phase-4-docs` |
| 5 | OpenSpec Specifications | `repo-health--phase-5-specs` |
| 6 | Test Suite Health | `repo-health--phase-6-tests` |
| 7 | Security Review | `repo-health--phase-7-security` |
| 8 | SBOM & License Audit | `repo-health--phase-8-sbom` |
| 9 | 12-Factor App Compliance | `repo-health--phase-9-12factor` |
| 10 | Action Plan Synthesis | `repo-health--phase-10-action-plan` |

**Dependency diagram:** Phase 3 needs Phase 2 + Phase 6 results. Phase 10 needs all prior phases.

## Workflow

1. Ask the user which dimension(s) to audit (or offer "full audit" for all)
2. **Load the helpers subskill** for grading rubric + script reference: `skill(name="repo-health--helpers")`
3. Run PHASE 0 first (gate). If it fails, abort.
4. For each selected dimension, load the subskill via `skill(name="repo-health--phase-{N}-{name}")` and follow its instructions
5. After all phases complete, run PHASE 10 to synthesize results
6. Output the consolidated action plan

## Helper Scripts

Scripts referenced by subskills live in `skills/repo-health/scripts/`. See the `repo-health--helpers` subskill for the full script listing and grading rubric.

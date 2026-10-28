## Skill Loading Precedence

OpenCode resolves skills from two locations (in priority order):

1. **User-installed** (`~/.config/opencode/skills/`) — shared across all projects
2. **Project-local** (`skills/`) — vendored skill folders in this repository

User-installed skills override project-local copies of the same name. When adding a
skill to this repo, also install it locally to
`~/.config/opencode/skills/<skill-name>/` to test before contributing.

## Background Task Rules

- You are using background execution blocks.
- DO NOT emit your final summary or exit the process while a background task ID is active.
- Use `background_output` to explicitly poll task statuses until they return a completed exit code.
- Implement a task tracking checklist. Mark tasks as complete only after reviewing the background logs.

## repo-health Audit (any agent, incl. GitHub Copilot)

This repo vendors the `repo-health` audit skill at `skills/repo-health/`. OpenCode loads
it via its skill loader (`skill(...)`, `@repo-health`); other agents — GitHub Copilot,
Claude Code, Gemini CLI, etc. — have no skill loader. **Read the file instead:**

1. **Entry point:** read `skills/repo-health/SKILL.md` and follow it as the workflow.
   Phase subskills live in `skills/repo-health--phase-*/SKILL.md`; deterministic scripts
   in `skills/repo-health/scripts/` (run from the audited repo root).
2. **Mode parameter** — resolved from the user's request words; no flags needed:
   - `report` (DEFAULT): full audit + graded findings report. No code changes.
   - `fix`: additionally run the Phase 10 remediation loop (fix → re-audit → loop until
     only NITPICKs remain; changes left uncommitted). Triggered by "fix findings",
     "remediate issues", "auto-fix everything", or explicit `mode=fix`.
   - Ambiguous request → `report`. Never auto-fix unless the user asked for fixes.
3. **VS Code Copilot Chat shortcut:** prompt files `.github/prompts/repo-health.prompt.md`
   (`/repo-health [fix]`) and `.github/prompts/repo-health-fix.prompt.md`
   (`/repo-health-fix`) register this audit as slash commands. The installer also places
   these prompt files in the VS Code user prompts folder so the commands work globally.

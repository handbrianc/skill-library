# Contributing to Skill Library

This repo distributes reusable OpenCode skill markdown files. No production code, no build system.

> **CI/CD:** Every PR against `main` is automatically validated by GitHub Actions. See [.github/workflows/validate.yml](.github/workflows/validate.yml).

## Skill Location

Skills live at `skills/<skill-name>/SKILL.md`. User-installed skills at
`~/.config/opencode/skills/` override project-local copies.

## Skill Anatomy

Every skill lives in its own directory under `skills/` and contains a `SKILL.md` file with this structure:

```markdown
---
name: my-skill
description: "One-line description for skill catalog. Use when user says '<trigger phrase>', '<another trigger>', ...
---
# Skill Title

Detailed instructional content for the agent...
```text

### Frontmatter Schema

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier (kebab-case). Matches directory name. |
| `description` | Yes | Enumerates trigger phrases verbatim. Agents search this to find relevant skills. |

### Writing Good Triggers

The `description` field determines when your skill activates. Triggers should be:

- **Literal phrases** users actually say — `"debug this"`, `"why is X failing"`
- **Lowercase** to maximize fuzzy match
- **Varied** — include synonyms and common phrasings
- **Specific** — avoid generic triggers like "help" or "code"

Example:

```yaml
description: "Use when the user asks about debugging, troubleshooting, or diagnosing issues. Triggers: 'debug this', 'why is X not working', 'hanging', 'trace this bug', 'silent failure', 'HTTP 200 but empty'."
```text

### Skill Content Guidelines

1. **Use imperative voice** — "Parse the input", "Identify the issue", "Deliver the result"
2. **Be concrete** — give explicit steps, not abstract philosophy
3. **Include examples** — show both good and bad responses
4. **Specify constraints** — what NOT to do is often as important as what to do
5. **Keep it lean** — if your skill exceeds 500 lines, consider splitting

## Quality Checklist

Before opening a PR, verify:

- [ ] `name` field matches directory name
- [ ] `description` includes 3+ realistic trigger phrases
- [ ] Triggers are lowercase and literal (not interpreted)
- [ ] SKILL.md has clear structure with headings
- [ ] Includes MUST DO / MUST NOT DO sections for critical constraints
- [ ] No placeholder text (`TODO`, `FILL IN`, etc.)
- [ ] No credentials, secrets, or project-specific paths hardcoded
- [ ] Installs cleanly: `ln -s skills/my-skill ~/.config/opencode/skills/my-skill`
- [ ] Loads without errors when OpenCode activates the skill
- [ ] If editing `AGENTS.md`, `CLAUDE.md`, or `README.md`, run `npx gitnexus analyze` afterward and regenerate the `<!-- gitnexus:start -->…<!-- gitnexus:end -->` block with fresh statistics (never paste stale counts)
- [ ] Run `bash tests/run-tests.sh` and confirm all tests pass

## Automated Validation

Before submitting a PR, run the full validation suite:

```bash
# Quick validation (runs all checks except shellcheck)
python3 scripts/validate-frontmatter.py --ci   # Schema + frontmatter + triggers
python3 scripts/detect-placeholders.py --ci     # No TODO/FIXME in skill bodies
python3 scripts/detect-trigger-conflicts.py --ci # No overlapping trigger phrases

# Bash script tests (requires bats: npm install -g bats)
bats tests/bats/test-fix-common.bats
bats tests/bats/test-fix-rollback.bats
bats tests/bats/test-scan-tests.bats

# Or run everything at once
bash tests/run-tests.sh
```text

All validations must pass before merging.

## Testing a Skill Locally

1. Create the skill directory: `mkdir -p skills/my-new-skill`
2. Write `skills/my-new-skill/SKILL.md`
3. Symlink to user skills: `ln -sf "$(pwd)/skills/my-new-skill" ~/.config/opencode/skills/my-new-skill`
4. Trigger your skill by saying one of your described phrases
5. Verify the skill activates and behaves correctly
6. Remove the symlink when done testing: `rm ~/.config/opencode/skills/my-new-skill`

## Submission Process

1. Fork the repository
2. Create a feature branch: `git checkout -b skill/add-my-skill`
3. Add your skill to `skills/<my-skill>/SKILL.md`
4. Optionally add tests/helpers under `skills/<my-skill>/` (supported: `.claude/`, `scripts/`, `references/`)
5. Open a pull request to `main`
6. Respond to review feedback

## Review Criteria

Maintainers evaluate PRs on:

- **Relevance** — Does the skill solve a real agent workflow gap?
- **Trigger coverage** — Will users discover this skill naturally?
- **Clarity** — Can an agent follow the instructions unambiguously?
- **Safety** — Does the skill prevent destructive or irreversible actions?
- **Completeness** — Are edge cases and error states covered?

## What to Contribute

- New skill packages addressing underserved agent use cases
- Improvements to existing skill documentation
- Bug fixes to skill instructions
- Better trigger phrases based on observed user behavior

## What NOT to Contribute

- Production application code (this is a distribution repo)
- Skills duplicating existing functionality

## Directory Structure

```text
skills/
└── <skill-name>/
    ├── SKILL.md              # REQUIRED — skill instruction markdown
    ├── scripts/              # OPTIONAL — helper scripts
    ├── references/           # OPTIONAL — supporting docs/data
    └── .claude/              # OPTIONAL — Claude Code integration
```text

Root-level directories:

```text
scripts/              # Validation and utility scripts
tests/                # bats test suites and fixtures
.github/workflows/    # CI/CD pipeline definitions
```text

Avoid adding large binary files, credentials, or dependency installations (`node_modules/`, `venv/`) to the repo.

Questions or ideas? Open an issue or PR — contributions welcome!

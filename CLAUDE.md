> **GitNexus instructions are maintained in [`AGENTS.md`](AGENTS.md).** See that file for
> impact analysis requirements, code intelligence workflows, and CLI references.

## Project Conventions

**What this repo is:** A skill-distribution template that packages reusable OpenCode
agent-skills as vendored markdown files. Nothing to build, run, or test — skills are
static `.md` files consumed directly by OpenCode.

**Contributing a new skill:**

1. Create `skills/<name>/SKILL.md` following the frontmatter schema in `CONTRIBUTING.md`.
2. Write realistic 3+ trigger phrases in the `description` field.
3. Add `### MUST DO` / `### MUST NOT DO` sections for critical constraints.
4. Test locally: `ln -sf "$(pwd)/skills/<name>" ~/.config/opencode/skills/<name>"` then activate by speaking a trigger phrase.
5. Remove the symlink when done testing.

**CI/CD:** PRs are validated via GitHub Actions — frontmatter schema compliance, shellcheck
on all bash scripts, markdown linting, placeholder detection, and trigger phrase conflict
checks. See [.github/workflows/validate.yml](.github/workflows/validate.yml). There is no
build pipeline — skills are plain markdown files.

<<<<<<< HEAD
**Package consumers:** The `@gitnexus` group syncs from this repo as a package source.
If you change skill structure or add mandatory files, update `skills/repo-health/` or
`skills/spec-compliance/` scripts accordingly.
=======
**Package consumers:** The `@gitnexus` group syncs from this repo as a package source. If you change skill structure or add mandatory files, update `skills/repo-health/` or `skills/spec-compliance/` scripts accordingly.


>>>>>>> origin/main

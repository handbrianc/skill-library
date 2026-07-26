> **GitNexus instructions are maintained in [`AGENTS.md`](AGENTS.md).** See that file for impact analysis requirements, code intelligence workflows, and CLI references.

## Project Conventions

**What this repo is:** A skill-distribution template that packages reusable OpenCode agent-skills as vendored markdown files. Nothing to build, run, or test — skills are static `.md` files consumed directly by OpenCode.

**Contributing a new skill:**
1. Create `skills/<name>/SKILL.md` following the frontmatter schema in `CONTRIBUTING.md`.
2. Write realistic 3+ trigger phrases in the `description` field.
3. Add `### MUST DO` / `### MUST NOT DO` sections for critical constraints.
4. Test locally: `ln -sf "$(pwd)/skills/<name>" ~/.config/opencode/skills/<name>"` then activate by speaking a trigger phrase.
5. Remove the symlink when done testing.

**No CI, no tests:** PRs are reviewed manually. This repo deliberately has no build pipeline, no test runner, and no published package — skills live as plain markdown files in this repo.

**Package consumers:** The `@gitnexus` group syncs from this repo as a package source. If you change skill structure or add mandatory files, update `skills/repo-health/` or `skills/spec-compliance/` scripts accordingly.



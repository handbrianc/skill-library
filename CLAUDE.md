<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **skill-library** (212 symbols, 208 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/skill-library/context` | Codebase overview, check index freshness |
| `gitnexus://repo/skill-library/clusters` | All functional areas |
| `gitnexus://repo/skill-library/processes` | All execution flows |
| `gitnexus://repo/skill-library/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `~/.config/opencode/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `~/.config/opencode/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `~/.config/opencode/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `~/.config/opencode/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `~/.config/opencode/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `~/.config/opencode/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

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

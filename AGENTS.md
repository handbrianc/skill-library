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

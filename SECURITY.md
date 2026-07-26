# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 2.x     | ✅ Supported       |
| 1.x     | ❌ Unsupported     |

## Reporting a Vulnerability

This repository distributes static OpenCode skill files (.md) and Bash helper scripts.
There are no compiled binaries, no network-facing services, and no dependency supply
chain beyond the skill files themselves.

**If you discover a security concern:**

1. **Do not** open a public GitHub issue for active vulnerabilities.
2. Open a regular issue or pull request for non-sensitive concerns (logic bugs,
   documentation gaps) on the [issue tracker](https://github.com/anomalyco/opencode/issues).
3. For sensitive vulnerabilities (credential exposure, code injection risks,
   supply-chain attacks in script logic), please email the maintainers directly or
   open a GitHub Security Advisory at the upstream repository.

## Disclosure Timeline

- **Non-sensitive issues**: Addressed within 30 days via public PR.
- **Sensitive issues**: Acknowledged within 72 hours; fix released within 14 days of confirmation.

## Credentials and Secrets

This repository should never contain active credentials. See `.gitignore` for the list
of files that are never committed. If you find exposed secrets (API keys, tokens,
passwords) in any commit:

- **Immediately** rotate the compromised credential.
- Open a security-advisory issue to coordinate removal from git history.
- Use `git filter-branch` or `bfg-repo-cleaner` to purge the secret from history.

## Scope

The following are **in scope** for security review:

- Bash helper scripts under `skills/repo-health/scripts/` — shell injection, unsafe `eval`, insecure temp-file handling.
- Skill content that executes commands on the agent's host.

The following are **out of scope**:

- The OpenCode agent platform itself (report to the OpenCode project).
- Third-party tools invoked by helper scripts (npm, git, jq, etc.).

## Contact

Preferred: [GitHub Issues](https://github.com/anomalyco/opencode/issues)
Alternative: Open a pull request with your fix.

#!/usr/bin/env python3
"""
detect-placeholders.py — Check SKILL.md bodies for placeholder text.

Scans all skills/*/SKILL.md files for common placeholder patterns
(TODO, FIXME, FILL IN, coming soon, PLACEHOLDER) in the body content
(after frontmatter). Skips code blocks.

Usage:
  python3 scripts/detect-placeholders.py
  python3 scripts/detect-placeholders.py --ci   # exit 1 on any finding

Exit codes:
  0 — no placeholders
  1 — one or more placeholders found
"""

import os
import re
import sys

REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")
CI_MODE = "--ci" in sys.argv
PLACEHOLDERS = ["TODO", "FIXME", "FILL IN", "coming soon", "PLACEHOLDER"]

ERRORS = []


def check_skill_placeholders(skill_path):
    rel_path = os.path.relpath(skill_path, REPO_ROOT)
    try:
        with open(skill_path) as f:
            content = f.read()
    except IOError as e:
        print(f"  ERROR: Cannot read {rel_path}: {e}", file=sys.stderr)
        return

    # Strip frontmatter
    parts = content.split("---", 2)
    body = parts[2] if len(parts) >= 3 else content

    # Track whether we're in a code block
    in_code_block = False
    for i, line in enumerate(body.split("\n"), 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue
        # Skip comments
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        for ph in PLACEHOLDERS:
            if ph in line:
                ERRORS.append(f"  PLACEHOLDER '{ph}' in {rel_path}:{i}")
                break


def main():
    if not os.path.isdir(SKILLS_DIR):
        print(f"  ERROR: No skills/ directory at {SKILLS_DIR}", file=sys.stderr)
        sys.exit(1)

    for entry in sorted(os.listdir(SKILLS_DIR)):
        skill_dir = os.path.join(SKILLS_DIR, entry)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if os.path.isdir(skill_dir) and os.path.isfile(skill_md):
            check_skill_placeholders(skill_md)

    if ERRORS:
        print(f"\nFound {len(ERRORS)} placeholder(s) in skill content:")
        for e in ERRORS:
            print(e)
        if CI_MODE:
            sys.exit(1)
    else:
        print("  ✓ No placeholders found in skill content")


if __name__ == "__main__":
    main()

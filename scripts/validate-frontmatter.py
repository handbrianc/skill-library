#!/usr/bin/env python3
"""
validate-frontmatter.py — SKILL.md frontmatter schema validator.

Checks every skills/<name>/SKILL.md for:
  - Valid YAML frontmatter between --- delimiters
  - Required fields: name, description
  - name matches the directory basename
  - subskill-of (if present) references an existing skill
  - description contains ≥3 comma-separated trigger phrases
  - No placeholder text (TODO, FIXME, FILL IN) in frontmatter

Usage:
  python3 scripts/validate-frontmatter.py              # validate all skills
  python3 scripts/validate-frontmatter.py --ci          # exit 1 on any failure
  python3 scripts/validate-frontmatter.py skills/my-skill/SKILL.md  # single file

Exit codes:
  0 — all valid
  1 — one or more validation failures (with --ci)
"""

import os
import re
import sys
import yaml


REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")
CI_MODE = "--ci" in sys.argv

ERRORS = []


def err(msg, path=""):
    tag = f" [{path}]" if path else ""
    ERRORS.append(f"  ✖ {msg}{tag}")
    if CI_MODE:
        print(f"ERROR:{msg}{tag}", file=sys.stderr)


def get_skill_names():
    """Return set of all valid skill names from skills/ directories."""
    names = set()
    if not os.path.isdir(SKILLS_DIR):
        return names
    for entry in os.listdir(SKILLS_DIR):
        skill_dir = os.path.join(SKILLS_DIR, entry)
        if os.path.isdir(skill_dir) and os.path.isfile(os.path.join(skill_dir, "SKILL.md")):
            names.add(entry)
    return names


def validate_skill(skill_path, all_skill_names):
    """
    Validate a single SKILL.md file.
    Returns True if valid, False otherwise.
    """
    rel_path = os.path.relpath(skill_path, REPO_ROOT)
    dir_name = os.path.basename(os.path.dirname(skill_path))

    # Read file
    try:
        with open(skill_path, "r") as f:
            content = f.read()
    except IOError as e:
        err(f"Cannot read file: {e}", rel_path)
        return False

    # Check YAML frontmatter delimiters
    if not content.startswith("---"):
        err("SKILL.md must start with YAML frontmatter (---)", rel_path)
        return False

    parts = content.split("---", 2)
    if len(parts) < 3:
        err("Unclosed YAML frontmatter: expected opening and closing ---", rel_path)
        return False

    frontmatter_yaml = parts[1]
    body = parts[2]

    # Parse YAML
    try:
        fm = yaml.safe_load(frontmatter_yaml)
    except yaml.YAMLError as e:
        err(f"YAML parse error: {e}", rel_path)
        return False

    if not isinstance(fm, dict):
        err("Frontmatter must be a YAML mapping (dictionary)", rel_path)
        return False

    is_valid = True

    # --- Check required fields ---
    required_fields = ["name", "description"]
    for field in required_fields:
        if field not in fm:
            err(f"Missing required frontmatter field: '{field}'", rel_path)
            is_valid = False

    # --- name field ---
    if "name" in fm:
        name_val = str(fm["name"])
        if name_val != dir_name:
            err(
                f"frontmatter 'name' ({name_val!r}) does not match directory name ({dir_name!r})",
                rel_path,
            )
            is_valid = False

    # --- subskill-of references ---
    if "subskill-of" in fm:
        parent = str(fm["subskill-of"])
        if parent not in all_skill_names:
            # Try with -- suffix to allow repo-health--phase-0 vs repo-health
            valid_parent = any(
                s.startswith(parent) or parent.startswith(s)
                for s in all_skill_names
            )
            if not valid_parent:
                err(
                    f"frontmatter 'subskill-of' references '{parent}' which is not a valid skill directory",
                    rel_path,
                )
                is_valid = False

    # --- description field ---
    if "description" in fm:
        desc = str(fm["description"])
        # Check for placeholders
        placeholders = ["TODO", "FIXME", "FILL IN", "coming soon", "TBD"]
        for ph in placeholders:
            if ph.lower() in desc.lower():
                err(f"frontmatter 'description' contains placeholder '{ph}'", rel_path)
                is_valid = False

        # Count trigger phrases — subskills are internal; exempt from trigger count
        is_subskill = "subskill-of" in fm
        if not is_subskill:
            # Prefer extracting explicitly quoted trigger phrases to avoid counting prose.
            triggers = set()
            triggers.update(t.strip() for t in re.findall(r"'([^']+)'", desc))
            triggers.update(t.strip() for t in re.findall(r'"([^"]+)"', desc))

            # Fallback: parse a dedicated "Triggers:" section if present.
            if not triggers:
                m = re.search(r"(?:triggers?|examples?):(.*)$", desc, flags=re.IGNORECASE)
                if m:
                    for item in re.split(r"[;,]", m.group(1)):
                        item = item.strip().strip("'\".")
                        if item:
                            triggers.add(item)

            trigger_count = sum(1 for t in triggers if len(t) > 3)
            if trigger_count < 3:
                err(
                    f"frontmatter 'description' has only {trigger_count} trigger phrase(s); need ≥3",
                    rel_path,
                )
                is_valid = False

    # --- Check body for placeholders ---
    body_placeholders = ["TODO", "FIXME", "FILL IN", "coming soon"]
    for ph in body_placeholders:
        # Simple check: word boundary for common placeholders
        if re.search(rf"\b{re.escape(ph)}\b", body, re.IGNORECASE):
            # Skip false positives: "TODO" in code blocks or URL examples
            if not is_in_code_block(body, ph):
                err(f"Body contains placeholder '{ph}'", rel_path)
                is_valid = False

    return is_valid


def is_in_code_block(content, phrase):
    """Heuristic: check if phrase appears only inside code blocks."""
    lines = content.split("\n")
    in_code = False
    for line in lines:
        if line.strip().startswith("```"):
            in_code = not in_code
        if not in_code and phrase.lower() in line.lower():
            return False
    return True


def main():
    all_skill_names = get_skill_names()

    if not all_skill_names:
        err(f"No skills found in {SKILLS_DIR}")
        sys.exit(1)

    # Allow single-file validation
    targets = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(targets) == 0:
        # Validate all skills
        for name in sorted(all_skill_names):
            skill_path = os.path.join(SKILLS_DIR, name, "SKILL.md")
            validate_skill(skill_path, all_skill_names)
    else:
        for target in targets:
            if os.path.isfile(target):
                validate_skill(target, all_skill_names)
            elif os.path.isdir(target):
                for root, dirs, files in os.walk(target):
                    for fn in files:
                        if fn == "SKILL.md":
                            validate_skill(os.path.join(root, fn), all_skill_names)
            else:
                err(f"Path not found: {target}")

    # Summary
    total = len(ERRORS)
    if total:
        print(f"\n{'─' * 50}")
        print(f"  {total} validation error(s) found")
        print(f"{'─' * 50}")
        for e in ERRORS:
            print(e)
        if CI_MODE:
            sys.exit(1)
        print("\nRun with --ci to exit non-zero on failures.")
    else:
        print("  ✓ All skills validated successfully")

    sys.exit(1 if total and CI_MODE else 0)


if __name__ == "__main__":
    main()

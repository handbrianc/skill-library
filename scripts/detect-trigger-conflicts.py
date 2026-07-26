#!/usr/bin/env python3
"""
detect-trigger-conflicts.py — Check for overlapping trigger phrases across skills.

Reads all skills/*/SKILL.md files, extracts trigger phrases from the
'description' frontmatter field, and reports any that conflict (i.e., the
same phrase appears in multiple skill descriptions).

Conflict severity:
  - Exact match: same phrase in ≥2 skills (HIGH)
  - Substring: one skill's phrase is a substring of another's (MEDIUM)
  - Near-duplicate: word-overlap similarity > 80% (LOW)
Usage:
  python3 scripts/detect-trigger-conflicts.py
  python3 scripts/detect-trigger-conflicts.py --ci   # exit 1 on any conflict

Exit codes:
  0 — no conflicts
  1 — one or more conflicts
"""

import os
import re
import sys
import yaml


REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SKILLS_DIR = os.path.join(REPO_ROOT, "skills")
CI_MODE = "--ci" in sys.argv

CONFLICTS = []


def get_all_trigger_phrases():
    """
    Parse all skills/*/SKILL.md files and extract trigger phrases.
    Returns {phrase: [skill_name, ...]} mapping.
    """
    phrases = {}  # lowercase phrase -> [skill names]

    if not os.path.isdir(SKILLS_DIR):
        return phrases

    for entry in sorted(os.listdir(SKILLS_DIR)):
        skill_dir = os.path.join(SKILLS_DIR, entry)
        skill_md = os.path.join(skill_dir, "SKILL.md")
        if not os.path.isdir(skill_dir) or not os.path.isfile(skill_md):
            continue

        try:
            with open(skill_md) as f:
                content = f.read()
        except IOError:
            continue

        # Extract YAML frontmatter
        if not content.startswith("---"):
            continue
        parts = content.split("---", 2)
        if len(parts) < 3:
            continue

        try:
            fm = yaml.safe_load(parts[1])
        except yaml.YAMLError:
            continue

        if not isinstance(fm, dict) or "description" not in fm:
            continue

        desc = str(fm["description"])

        # Extract trigger phrases: look for single/double-quoted strings,
        # and comma-separated items that look like trigger commands
        # Patterns: 'trigger phrase', "trigger phrase", or comma-separated triggers
        found_triggers = set()

        # Pattern 1: single-quoted phrases
        for m in re.finditer(r"'([^']+)'", desc):
            t = m.group(1).strip().lower()
            if len(t) > 3:
                found_triggers.add(t)

        # Pattern 2: double-quoted phrases
        for m in re.finditer(r'"([^"]+)"', desc):
            t = m.group(1).strip().lower()
            if len(t) > 3:
                found_triggers.add(t)

        # Pattern 3: comma-separated items in "Triggers:" lists
        trigger_section = re.split(
            r"(?:triggers?|examples?):", desc, flags=re.IGNORECASE
        )
        if len(trigger_section) > 1:
            for part in trigger_section[1:]:  # use split result, not re.split
                items = re.split(r"[;,]", part)
                for item in items:
                    item = item.strip().strip("'\".").lower()
                    if len(item) > 3:
                        found_triggers.add(item)

        # Register phrases
        for phrase in found_triggers:
            if phrase not in phrases:
                phrases[phrase] = []
            phrases[phrase].append(entry)

    return phrases


def detect_conflicts(phrases):
    """
    Analyze trigger phrases for conflicts.
    Returns list of (severity, message) tuples.
    """
    conflicts = []

    # 1. Exact matches across skills
    for phrase, skills in sorted(phrases.items()):
        if len(skills) >= 2:
            conflicts.append((
                "HIGH",
                f"Exact trigger phrase '{phrase}' found in {len(skills)} skills: {', '.join(skills)}"
            ))

    # 2. Substring conflicts
    skill_phrases = {}  # skill -> set of phrases
    for phrase, skills in phrases.items():
        for s in skills:
            if s not in skill_phrases:
                skill_phrases[s] = set()
            skill_phrases[s].add(phrase)

    skill_list = sorted(skill_phrases.keys())
    for i, s1 in enumerate(skill_list):
        for s2 in skill_list[i + 1:]:
            for p1 in skill_phrases[s1]:
                for p2 in skill_phrases[s2]:
                    if p1 == p2:
                        continue
                    if p1 in p2 or p2 in p1:
                        conflicts.append((
                            "MEDIUM",
                            f"Substring conflict: '{p1}' ({s1}) overlaps with '{p2}' ({s2})"
                        ))

    # 3. Near-duplicate phrases (word overlap > 80%)
    all_phrases = sorted(phrases.keys())
    for i, p1 in enumerate(all_phrases):
        for p2 in all_phrases[i + 1:]:
            if p1 == p2:
                continue
            words1 = set(p1.split())
            words2 = set(p2.split())
            if len(words1) > 1 and len(words2) > 1:
                intersection = words1 & words2
                union = words1 | words2
                if len(intersection) / len(union) > 0.8:
                    skills_p1 = phrases[p1]
                    skills_p2 = phrases[p2]
                    conflicts.append((
                        "LOW",
                        f"Near-duplicate: '{p1}' ({', '.join(skills_p1)}) ~ '{p2}' ({', '.join(skills_p2)})"
                    ))

    return conflicts


def main():
    phrases = get_all_trigger_phrases()
    conflicts = detect_conflicts(phrases)

    # Stats
    total_phrases = sum(len(skills) for skills in phrases.values())
    unique_phrases = len(phrases)
    total_skills = len(set(
        s for skills in phrases.values() for s in skills
    ))

    print(f"  Skills scanned: {total_skills}")
    print(f"  Total trigger phrases: {total_phrases}")
    print(f"  Unique trigger phrases: {unique_phrases}")
    print()

    if not conflicts:
        print("  ✓ No trigger phrase conflicts detected")
        sys.exit(0)

    print(f"  Found {len(conflicts)} trigger phrase conflict(s):")
    print()
    for severity, msg in conflicts:
        icon = {"HIGH": "🔴", "MEDIUM": "🟠", "LOW": "🟡"}.get(severity, "⚪")
        print(f"    {icon} [{severity}] {msg}")

    if CI_MODE:
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()

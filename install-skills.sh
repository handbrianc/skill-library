#!/usr/bin/env bash
#
# install-skills.sh — Install skills from this repo into agent skill directories.
#
# Installs every skill under ./skills/ into the user's OpenCode directory
# (~/.config/opencode/skills/<skill-name>/) and, by default, into the personal
# GitHub Copilot skills directory (~/.copilot/skills/), which the Copilot
# extension in VS Code (plus Copilot CLI and the Copilot app) reads automatically.
# From .github/prompts/*.prompt.md it also generates a global wrapper skill under
# ~/.copilot/skills/ (e.g. repo-health-fix) so the /repo-health-fix slash command
# works in every VS Code harness, the Copilot CLI and the Copilot app.
# Supports symlinks (for development) or copy (for stable deployment).
#
# Usage:
#   ./install-skills.sh              # Interactive — prompts per existing skill
#   ./install-skills.sh --symlink    # Symlink instead of copy (dev mode)
#   ./install-skills.sh --force      # Overwrite existing without prompting
#   ./install-skills.sh --dry-run    # Show what would be done
#   ./install-skills.sh --list       # List installable skills and exit
#   ./install-skills.sh --skip       # Skip existing, only install new
#   ./install-skills.sh --no-copilot # Skip ~/.copilot/skills (skills AND wrapper)
#   ./install-skills.sh --dest ~/some/dir
#                                    # Install ONLY to the given path
#                                    # (overrides both default destinations)
#

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills"
DEFAULT_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
COPILOT_DEST="$HOME/.copilot/skills"
PROMPTS_SOURCE="$SCRIPT_DIR/.github/prompts"

# Files an older installer version copied into the VS Code user prompts folder
# (and, in some setups, ~/.copilot/prompts/). Removed on install — these exact
# filenames only, never glob-deleted. VS Code's prompt→skills migration would
# otherwise conflict with the installed/generated skills.
LEGACY_PROMPT_FILES=(
  "repo-health.prompt.md"
  "repo-health-fix.prompt.md"
)

# ── Help ────────────────────────────────────────────────────────────────────

usage() {
  sed -n '3,25p' "$0" | sed 's/^# \?//'
}

# ── Parse args ──────────────────────────────────────────────────────────────

MODE="copy"       # copy | symlink
FORCE=false
DRY_RUN=false
LIST_ONLY=false
SKIP_EXISTING=false
NO_COPILOT=false
CUSTOM_DEST=""
WRAPPERS_INSTALLED=()   # wrapper skill names actually generated (for hints)

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    -s|--symlink)  MODE="symlink" ; shift ;;
    -f|--force)    FORCE=true ; shift ;;
    -d|--dry-run)  DRY_RUN=true ; shift ;;
    -l|--list)     LIST_ONLY=true ; shift ;;
    -S|--skip)     SKIP_EXISTING=true ; shift ;;
    -n|--no-copilot) NO_COPILOT=true ; shift ;;
    -D|--dest)
      shift
      CUSTOM_DEST="$(realpath -m "$1")"
      shift
      ;;
    *)  echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
done

# ── Destinations ─────────────────────────────────────────────────────────────

# An explicit --dest is the only target; otherwise install to the default
# OpenCode destination and (unless --no-copilot) the personal Copilot one.
if [[ -n "$CUSTOM_DEST" ]]; then
  DESTS=("$CUSTOM_DEST")
else
  DESTS=("$DEFAULT_DEST")
  $NO_COPILOT || DESTS+=("$COPILOT_DEST")
fi

# The prompt files are NOT installed globally anymore. Each *.prompt.md becomes
# a generated Copilot wrapper skill under ~/.copilot/skills/ instead (see the
# wrapper section below); the files themselves stay in this repo, where they
# still register the commands for this workspace's Chat view.
PROMPT_FILES=()
for prompt_src in "$PROMPTS_SOURCE"/*.prompt.md; do
  if [[ -f "$prompt_src" ]]; then
    PROMPT_FILES+=("$prompt_src")
  fi
done

# ── Discover skills ─────────────────────────────────────────────────────────

if [[ ! -d "$SKILLS_SOURCE" ]]; then
  echo "Error: No skills/ directory found at $SKILLS_SOURCE" >&2
  exit 1
fi

SKILLS=()
for dir in "$SKILLS_SOURCE"/*/; do
  name="$(basename "$dir")"
  if [[ -f "$dir/SKILL.md" ]]; then
    SKILLS+=("$name")
  fi
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  echo "No skills found (no directories with SKILL.md under $SKILLS_SOURCE)." >&2
  exit 1
fi

# ── List mode ────────────────────────────────────────────────────────────────

if $LIST_ONLY; then
  echo "Installable skills (source: $SKILLS_SOURCE)"
  echo "Destinations:"
  for dest in "${DESTS[@]}"; do
    echo "  - $dest"
  done
  echo "Mode: $MODE"
  echo
  for name in "${SKILLS[@]}"; do
    has_scripts=
    if [[ -d "$SKILLS_SOURCE/$name/scripts" ]]; then
      has_scripts=" ($(find "$SKILLS_SOURCE/$name/scripts" -type f | wc -l) scripts)"
    fi
    printf "  %-20s %s\n" "$name" "$has_scripts"
  done
  exit 0
fi

# ── Pre-flight checks ───────────────────────────────────────────────────────

if ! $DRY_RUN; then
  for dest in "${DESTS[@]}"; do
    mkdir -p "$dest"
    if [[ ! -w "$dest" ]]; then
      echo "Error: Destination $dest is not writable." >&2
      exit 1
    fi
  done
fi

# ── Install ──────────────────────────────────────────────────────────────────

install_into() {
  local dest="$1"
  local name src dst reply
  local installed=0
  local skipped=0
  local failed=0

  for name in "${SKILLS[@]}"; do
    src="$SKILLS_SOURCE/$name"
    dst="$dest/$name"

    # ── Check if destination exists ─────────────────────────────────
    if [[ -e "$dst" || -L "$dst" ]]; then
      if $DRY_RUN; then
        echo "  [dry-run] $name  ->  $dst  (would replace existing, mode: $MODE)"
        ((installed++)) || true
        continue
      fi
      if $SKIP_EXISTING; then
        echo "  [skip]   $name  (already exists at $dst)"
        ((skipped++)) || true
        continue
      fi
      if ! $FORCE; then
        echo "  [exist]  $name  already installed at $dst"
        echo "           Use --force to overwrite, --skip to skip existing,"
        echo "           or remove it manually: rm -rf \"$dst\""
        echo -n "           Overwrite at $dest? [y/N] "
        read -r reply < /dev/tty 2>/dev/null || true
        case "${reply:-n}" in
          y|Y|yes|YES) ;;
          *) echo "           Skipping $name." ; ((skipped++)) || true ; continue ;;
        esac
      fi
      # Remove existing (handle both symlink and directory)
      rm -rf "$dst"
    fi

    # ── Install ────────────────────────────────────────────────────
    if $DRY_RUN; then
      echo "  [dry-run] $name  ->  $dst  (mode: $MODE)"
      ((installed++)) || true
      continue
    fi

    if [[ "$MODE" == "symlink" ]]; then
      # Resolve full path to the source so the symlink is absolute
      ln -sf "$src" "$dst"
      echo "  [link]   $name  ->  $dst"
    else
      cp -a "$src" "$dst"
      echo "  [copy]   $name  ->  $dst"
    fi
    ((installed++)) || true

    # ── Post-install sanity ─────────────────────────────────────────
    if [[ ! -f "$dst/SKILL.md" ]]; then
      echo "  Warning: SKILL.md not found at $dst/SKILL.md — skill may be incomplete." >&2
    fi
  done

  # ── Summary (per destination) ────────────────────────────────────────────

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Destination:    $dest"
  echo "  Mode:           $MODE"
  echo "  Installed:      $installed"
  echo "  Skipped:        $skipped"
  echo "  Failed:         $failed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

cleanup_legacy_prompt_files() {
  # Remove the .prompt.md files older installer versions placed into the VS Code
  # user prompts folders (<UD_ROOT>/<variant>/User/prompts) and, if present,
  # ~/.copilot/prompts/. Exact filenames only; emptied dirs are removed after.
  local ud_root dir file removed
  local -a prompt_dirs=()

  case "$(uname -s)" in
    Darwin)
      ud_root="$HOME/Library/Application Support" ;;
    MINGW*|MSYS*|CYGWIN*)
      ud_root="${APPDATA:-}" ;;
    *)
      ud_root="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
  esac
  if [[ -n "$ud_root" ]]; then
    prompt_dirs=(
      "$ud_root/Code/User/prompts"
      "$ud_root/Code - Insiders/User/prompts"
      "$ud_root/VSCodium/User/prompts"
    )
  fi
  prompt_dirs+=("$HOME/.copilot/prompts")

  for dir in "${prompt_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    removed=false
    for file in "${LEGACY_PROMPT_FILES[@]}"; do
      if [[ -e "$dir/$file" || -L "$dir/$file" ]]; then
        if $DRY_RUN; then
          echo "  [dry-run] rm $dir/$file"
        else
          rm -f "$dir/$file"
          echo "  [cleanup] removed $dir/$file (replaced by generated wrapper skill)"
        fi
        removed=true
      fi
    done
    if $removed && ! $DRY_RUN && [[ "$dir" == */User/prompts ]]; then
      # Only the VS Code user prompts dirs get emptied-and-removed
      rmdir --ignore-fail-on-non-empty "$dir" 2>/dev/null || true
    fi
  done
}

install_wrapper_skills() {
  # Generate a Copilot wrapper skill per .github/prompts/*.prompt.md under
  # ~/.copilot/skills/ so the /<name> slash command works in every VS Code
  # harness, the Copilot CLI and the Copilot app. Wrappers are manual-invoke
  # only (disable-model-invocation: true) and always copied, regardless of MODE.
  local src name dst reply description arg_hint existing
  local installed=0
  local skipped=0
  local failed=0

  if [[ ${#PROMPT_FILES[@]} -eq 0 ]]; then
    echo "Error: no *.prompt.md files found in $PROMPTS_SOURCE" >&2
    return 0
  fi

  for src in "${PROMPT_FILES[@]}"; do
    # Derive the skill name: basename minus .prompt.md, lowercased, spaces → hyphens
    name="$(basename "$src" .prompt.md)"
    name="$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]-')"
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      echo "Warning: skipping $(basename "$src") — derived skill name '$name' is not a valid Copilot skill name (lowercase letters, digits, hyphens)." >&2
      continue
    fi

    # Never touch a destination that belongs to a real repo skill — that skill
    # itself serves the /<name> command (e.g. the repo-health audit skill).
    for existing in "${SKILLS[@]}"; do
      if [[ "$existing" == "$name" ]]; then
        echo "Warning: skipping wrapper '$name' ($(basename "$src")) — collides with repo skill 'skills/$name'; the installed skill serves /$name itself." >&2
        continue 2
      fi
    done

    # Extract description / argument-hint from the prompt's YAML frontmatter
    # (raw remainder after the key, any quoting kept)
    description="$(awk '
      { sub(/\r$/, "") }
      NR==1 && /^---[ \t]*$/ { infm=1; next }
      infm && /^---[ \t]*$/ { exit }
      infm && /^description:/ { sub(/^description:[ \t]*/, ""); print; exit }
    ' "$src")"
    [[ -n "$description" ]] || description="Manual wrapper: $name audit command."
    arg_hint="$(awk '
      { sub(/\r$/, "") }
      NR==1 && /^---[ \t]*$/ { infm=1; next }
      infm && /^---[ \t]*$/ { exit }
      infm && /^argument-hint:/ { sub(/^argument-hint:[ \t]*/, ""); print; exit }
    ' "$src")"

    dst="$COPILOT_DEST/$name"

    # ── Check if destination exists ─────────────────────────────────
    if [[ -e "$dst" || -L "$dst" ]]; then
      if $DRY_RUN; then
        echo "  [dry-run] $name  ->  $dst  (would replace existing, mode: copy)"
        ((installed++)) || true
        continue
      fi
      if $SKIP_EXISTING; then
        echo "  [skip]   $name  (already exists at $dst)"
        ((skipped++)) || true
        continue
      fi
      if ! $FORCE; then
        echo "  [exist]  $name  already installed at $dst"
        echo "           Use --force to overwrite, --skip to skip existing,"
        echo "           or remove it manually: rm -rf \"$dst\""
        echo -n "           Overwrite at $COPILOT_DEST? [y/N] "
        read -r reply < /dev/tty 2>/dev/null || true
        case "${reply:-n}" in
          y|Y|yes|YES) ;;
          *) echo "           Skipping $name." ; ((skipped++)) || true ; continue ;;
        esac
      fi
      # Remove existing (wrapper skills are directories)
      rm -rf "$dst"
    fi

    # ── Install ────────────────────────────────────────────────────
    if $DRY_RUN; then
      echo "  [dry-run] $name  ->  $dst  (mode: copy)"
      ((installed++)) || true
      continue
    fi

    mkdir -p "$dst"
    {
      printf '%s\n' '---'
      printf 'name: %s\n' "$name"
      printf 'description: %s\n' "$description"
      if [[ -n "$arg_hint" ]]; then
        printf 'argument-hint: %s\n' "$arg_hint"
      fi
      printf '%s\n' 'disable-model-invocation: true'
      printf '%s\n' '---'
      # Prompt body: everything after the frontmatter close, verbatim
      # (with no frontmatter at all, the whole file is the body)
      awk '
        { sub(/\r$/, "") }
        NR==1 && /^---[ \t]*$/ { infm=1; next }
        infm && /^---[ \t]*$/ { infm=0; body=1; next }
        infm { next }
        { print }
      ' "$src"
    } > "$dst/SKILL.md"
    echo "  [copy]   $name  ->  $dst"
    ((installed++)) || true
    WRAPPERS_INSTALLED+=("$name")

    # ── Post-install sanity ─────────────────────────────────────────
    if [[ ! -f "$dst/SKILL.md" ]]; then
      echo "  Warning: SKILL.md not found at $dst/SKILL.md — wrapper may be incomplete." >&2
    fi
  done

  # ── Summary (per destination) ────────────────────────────────────────────

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Destination:    $COPILOT_DEST  (Copilot wrapper skills generated from .github/prompts — /name slash commands, all harnesses)"
  echo "  Mode:           copy"
  echo "  Installed:      $installed"
  echo "  Skipped:        $skipped"
  echo "  Failed:         $failed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

for dest in "${DESTS[@]}"; do
  install_into "$dest"
done

# ── Legacy prompt cleanup + Copilot wrapper skills ───────────────────────────
# Runs unless --dest or --no-copilot. Output reads top-down: skills → cleanup
# → wrappers.

if [[ -z "$CUSTOM_DEST" ]] && ! $NO_COPILOT; then
  cleanup_legacy_prompt_files
  install_wrapper_skills
fi

if $DRY_RUN; then
  echo "Dry-run complete. Run without --dry-run to actually install."
  exit 0
fi

# ── Final hints ─────────────────────────────────────────────────────────────

if [[ "$MODE" == "symlink" ]]; then
  echo "⚠  Symlinked — if you remove or move this repo, the skills will break."
fi

echo "Skills installed. Read automatically from:"
for dest in "${DESTS[@]}"; do
  if [[ "$dest" == "$COPILOT_DEST" ]]; then
    echo "  $dest  (GitHub Copilot personal skills — VS Code extension, CLI, app)"
  else
    echo "  $dest"
  fi
done

if [[ -z "$CUSTOM_DEST" ]] && ! $NO_COPILOT; then
  echo
  if [[ ${#WRAPPERS_INSTALLED[@]} -gt 0 ]]; then
    echo "Copilot wrapper skills generated (manual invoke only — disable-model-invocation: true):"
    for wname in "${WRAPPERS_INSTALLED[@]}"; do
      echo "  $COPILOT_DEST/$wname  (/$wname)"
    done
  else
    echo "No Copilot wrapper skills were generated from $PROMPTS_SOURCE."
  fi
  echo "  /repo-health is served by the audit skill itself; /repo-health-fix by its"
  echo "  wrapper. In this workspace, .github/prompts/*.prompt.md still register the"
  echo "  commands for the Chat view (Local)."
fi

if [[ -z "$CUSTOM_DEST" ]] && ! $NO_COPILOT; then
  echo
  echo "OpenCode reads skills from:"
  echo "  1. $DEFAULT_DEST (user-installed, highest priority)"
  echo "  2. \$PWD/skills/ (project-local)"
fi
echo

echo "To verify:"
for dest in "${DESTS[@]}"; do
  echo "  ls -la \"$dest\""
done

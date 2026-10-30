#!/usr/bin/env pwsh
#
# install-skills.ps1 — Install skills from this repo into agent skill directories.
# (Windows port of install-skills.sh: same flags, same behavior.)
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
#   .\install-skills.ps1              # Interactive — prompts per existing skill
#   .\install-skills.ps1 --symlink    # Symlink instead of copy (dev mode)
#   .\install-skills.ps1 --force      # Overwrite existing without prompting
#   .\install-skills.ps1 --dry-run    # Show what would be done
#   .\install-skills.ps1 --list       # List installable skills and exit
#   .\install-skills.ps1 --skip       # Skip existing, only install new
#   .\install-skills.ps1 --no-copilot # Skip ~/.copilot/skills (skills AND wrapper)
#   .\install-skills.ps1 --dest C:\some\dir
#                                     # Install ONLY to the given path
#                                     # (overrides both default destinations)
#
# Windows notes:
#   Run from cmd or a pinned shortcut:
#     powershell -ExecutionPolicy Bypass -File .\install-skills.ps1
#   --symlink needs Developer Mode or an elevated prompt; the installer
#   automatically falls back to a directory junction (no elevation needed).
#   The bundled .sh scripts keep working from any directory: bash (Git Bash
#   or WSL) runs them regardless of Windows file attributes, so no chmod
#   equivalent is needed after a copy install.
#
# Installed copies are self-contained: after a copy install, script references
# inside each installed SKILL.md are rewritten to absolute paths under the
# install destination and every bundled script is made executable, so the
# skills work from any working directory (VS Code, Copilot CLI/app and other
# harnesses run the agent in your project, not in this repo). Symlink mode is
# dev mode and keeps repo-relative paths.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ── Config ──────────────────────────────────────────────────────────────────

$ScriptDir = $PSScriptRoot
$SkillsSource = [System.IO.Path]::Combine($ScriptDir, 'skills')
$XdgConfigHome = $env:XDG_CONFIG_HOME
if (-not $XdgConfigHome) { $XdgConfigHome = [System.IO.Path]::Combine($HOME, '.config') }
$DefaultDest = [System.IO.Path]::Combine($XdgConfigHome, 'opencode', 'skills')
$CopilotDest = [System.IO.Path]::Combine($HOME, '.copilot', 'skills')
$PromptsSource = [System.IO.Path]::Combine($ScriptDir, '.github', 'prompts')

# Intermediate token used when rewriting script references in installed
# SKILL.md files. Relative references are consumed into this token first and
# expanded to the real destination only in a final pass — that keeps the
# rewrite idempotent (a second run over already-rewritten files matches
# nothing) and immune to destinations whose path ends in "/skills".
$SkillRootToken = '__INSTALLED_SKILL_ROOT__'
$Script:RewriteOps = $null          # rewrite operations for the active destination
$ScriptOwner = @{}                  # script basename -> owning skill, or __AMBIGUOUS__

# Files an older installer version copied into the VS Code user prompts folder
# (and, in some setups, ~/.copilot/prompts/). Removed on install — these exact
# filenames only, never glob-deleted. VS Code's prompt→skills migration would
# otherwise conflict with the installed/generated skills.
$LegacyPromptFiles = @(
  'repo-health.prompt.md',
  'repo-health-fix.prompt.md'
)

$OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

# ── Help ────────────────────────────────────────────────────────────────────

function Show-Usage {
  # Echo the header comment block (same trick as the bash installer's
  # `sed -n '3,…p'`, so usage and docs cannot drift apart).
  param([switch]$ToStdErr)
  $lines = [System.Collections.Generic.List[string]]@()
  $own = [System.IO.File]::ReadAllLines($PSCommandPath)
  for ($i = 2; $i -lt $own.Count; $i++) {
    if ($own[$i] -notmatch '^#') { break }
    $text = $own[$i] -replace '^# ?', ''
    if ($ToStdErr) { [Console]::Error.WriteLine($text) } else { Write-Output $text }
  }
}

function Write-ErrLine {
  param([string]$Message)
  [Console]::Error.WriteLine($Message)
}

function ConvertTo-AbsolutePath {
  # Windows equivalent of `realpath -m`: absolute, normalized, works for
  # paths that do not exist yet.
  param([string]$Value)
  if ([System.IO.Path]::IsPathRooted($Value)) {
    return [System.IO.Path]::GetFullPath($Value)
  }
  return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).ProviderPath, $Value))
}

# ── Parse args ──────────────────────────────────────────────────────────────

$Mode = 'copy'      # copy | symlink
$Force = $false
$DryRun = $false
$ListOnly = $false
$SkipExisting = $false
$NoCopilot = $false
$CustomDest = ''
$WrappersInstalled = [System.Collections.Generic.List[string]]@()   # wrapper names generated

for ($i = 0; $i -lt $args.Count; $i++) {
  $arg = [string]$args[$i]
  if ($arg -ceq '-h' -or $arg -ceq '--help')     { Show-Usage; exit 0 }
  elseif ($arg -ceq '-s' -or $arg -ceq '--symlink')    { $Mode = 'symlink' }
  elseif ($arg -ceq '-f' -or $arg -ceq '--force')      { $Force = $true }
  elseif ($arg -ceq '-d' -or $arg -ceq '--dry-run')    { $DryRun = $true }
  elseif ($arg -ceq '-l' -or $arg -ceq '--list')       { $ListOnly = $true }
  elseif ($arg -ceq '-S' -or $arg -ceq '--skip')       { $SkipExisting = $true }
  elseif ($arg -ceq '-n' -or $arg -ceq '--no-copilot') { $NoCopilot = $true }
  elseif ($arg -ceq '-D' -or $arg -ceq '--dest') {
    $i++
    if ($i -ge $args.Count) {
      Write-ErrLine "Error: $arg requires a path argument."
      Write-ErrLine ''
      Show-Usage -ToStdErr
      exit 1
    }
    $CustomDest = ConvertTo-AbsolutePath ([string]$args[$i])
  }
  else {
    Write-ErrLine "Unknown option: $arg"
    Write-ErrLine ''
    Show-Usage -ToStdErr
    exit 1
  }
}

# ── Destinations ─────────────────────────────────────────────────────────────

# An explicit --dest is the only target; otherwise install to the default
# OpenCode destination and (unless --no-copilot) the personal Copilot one.
if ($CustomDest -ne '') {
  $Dests = @($CustomDest)
} else {
  $Dests = @($DefaultDest)
  if (-not $NoCopilot) { $Dests += $CopilotDest }
}

# The prompt files are NOT installed globally anymore. Each *.prompt.md becomes
# a generated Copilot wrapper skill under ~/.copilot/skills/ instead (see the
# wrapper section below); the files themselves stay in this repo, where they
# still register the commands for this workspace's Chat view.
$PromptFiles = @()
if (Test-Path -LiteralPath $PromptsSource -PathType Container) {
  $PromptFiles = @(Get-ChildItem -LiteralPath $PromptsSource -Filter '*.prompt.md' -File | ForEach-Object { $_.FullName })
  [System.Array]::Sort($PromptFiles, [System.StringComparer]::Ordinal)
}

# ── Discover skills ─────────────────────────────────────────────────────────

if (-not (Test-Path -LiteralPath $SkillsSource -PathType Container)) {
  Write-ErrLine "Error: No skills/ directory found at $SkillsSource"
  exit 1
}

$Skills = @()
$skillNames = @(Get-ChildItem -LiteralPath $SkillsSource -Directory | ForEach-Object { $_.Name })
[System.Array]::Sort($skillNames, [System.StringComparer]::Ordinal)
foreach ($name in $skillNames) {
  if (Test-Path -LiteralPath ([System.IO.Path]::Combine($SkillsSource, $name, 'SKILL.md')) -PathType Leaf) {
    $Skills += $name
  }
}

if ($Skills.Count -eq 0) {
  Write-ErrLine "No skills found (no directories with SKILL.md under $SkillsSource)."
  exit 1
}

# ── List mode ────────────────────────────────────────────────────────────────

if ($ListOnly) {
  Write-Output "Installable skills (source: $SkillsSource)"
  Write-Output 'Destinations:'
  foreach ($dest in $Dests) { Write-Output "  - $dest" }
  Write-Output "Mode: $Mode"
  Write-Output ''
  foreach ($name in $Skills) {
    $hasScripts = ''
    $scriptsDir = [System.IO.Path]::Combine($SkillsSource, $name, 'scripts')
    if (Test-Path -LiteralPath $scriptsDir -PathType Container) {
      $count = @(Get-ChildItem -LiteralPath $scriptsDir -Recurse -File).Count
      $hasScripts = " ($count scripts)"
    }
    Write-Output ('  ' + $name.PadRight(20) + ' ' + $hasScripts)
  }
  exit 0
}

# ── Pre-flight checks ───────────────────────────────────────────────────────

if (-not $DryRun) {
  foreach ($dest in $Dests) {
    if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
      New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    # Write probe (the Windows stand-in for bash's `-w` check).
    $probe = [System.IO.Path]::Combine($dest, '.write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
      [System.IO.File]::WriteAllText($probe, 'x')
      [System.IO.File]::Delete($probe)
    } catch {
      Write-ErrLine "Error: Destination $dest is not writable."
      exit 1
    }
  }
}

# ── Link-aware removal / existence helpers ───────────────────────────────────

function Test-AnyPath {
  # `-e "$dst" || -L "$dst"` equivalent: also true for dangling links.
  param([string]$Path)
  return $null -ne (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Remove-SkillPath {
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return }
  if ($item.LinkType) {
    # Junction or symlink: unlink the link itself, never recurse into the
    # target (Windows PowerShell 5.1's Remove-Item -Recurse could).
    [System.IO.Directory]::Delete($Path) | Out-Null
  } else {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Get-RemoveHint {
  param([string]$Path)
  if ($OnWindows) { return 'Remove-Item -Recurse -Force "' + $Path + '"' }
  return 'rm -rf "' + $Path + '"'
}

# ── Install ──────────────────────────────────────────────────────────────────

function Install-Into {
  param([string]$Dest)
  $installed = 0
  $skipped = 0
  $failed = 0

  foreach ($name in $Skills) {
    $src = [System.IO.Path]::Combine($SkillsSource, $name)
    $dst = [System.IO.Path]::Combine($Dest, $name)

    # ── Check if destination exists ─────────────────────────────────
    if (Test-AnyPath $dst) {
      if ($DryRun) {
        Write-Output "  [dry-run] $name  ->  $dst  (would replace existing, mode: $Mode)"
        $installed++
        continue
      }
      if ($SkipExisting) {
        Write-Output "  [skip]   $name  (already exists at $dst)"
        $skipped++
        continue
      }
      if (-not $Force) {
        Write-Output "  [exist]  $name  already installed at $dst"
        Write-Output '           Use --force to overwrite, --skip to skip existing,'
        Write-Output "           or remove it manually: $(Get-RemoveHint $dst)"
        $reply = ''
        try { $reply = Read-Host "           Overwrite at $Dest? [y/N]" } catch { $reply = '' }
        if ($reply -cne 'y' -and $reply -cne 'Y' -and $reply -cne 'yes' -and $reply -cne 'YES') {
          Write-Output ('           Skipping ' + $name + '.')
          $skipped++
          continue
        }
      }
      # Remove existing (handle both link and directory)
      Remove-SkillPath $dst
    }

    # ── Install ────────────────────────────────────────────────────
    if ($DryRun) {
      Write-Output "  [dry-run] $name  ->  $dst  (mode: $Mode)"
      $installed++
      continue
    }

    if ($Mode -eq 'symlink') {
      # Absolute source, like the bash installer's `ln -sf "$src" "$dst"`.
      # On Windows a symbolic link needs Developer Mode or elevation; fall
      # back to a directory junction, which needs neither.
      $linked = $false
      try {
        New-Item -ItemType SymbolicLink -Path $dst -Value $src -ErrorAction Stop | Out-Null
        $linked = $true
        Write-Output "  [link]   $name  ->  $dst"
      } catch {
        if ($OnWindows) {
          try {
            New-Item -ItemType Junction -Path $dst -Value $src -ErrorAction Stop | Out-Null
            $linked = $true
            Write-Output "  [link]   $name  ->  $dst  (junction fallback — symlink needs Developer Mode or elevation)"
          } catch {
            Write-Output "  [error]  $name — could not create symlink or junction at $dst (enable Developer Mode or run elevated)"
            $failed++
          }
        } else {
          Write-Output "  [error]  $name — symlink creation failed at $dst"
          $failed++
        }
      }
      if (-not $linked) { continue }
    } else {
      Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
      Write-Output "  [copy]   $name  ->  $dst"
    }
    $installed++

    # ── Post-install sanity ─────────────────────────────────────────
    if (-not (Test-Path -LiteralPath ([System.IO.Path]::Combine($dst, 'SKILL.md')) -PathType Leaf)) {
      Write-ErrLine "  Warning: SKILL.md not found at $([System.IO.Path]::Combine($dst, 'SKILL.md')) — skill may be incomplete."
    }
  }

  # ── Summary (per destination) ────────────────────────────────────────────

  Write-Output ''
  Write-Output '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  Write-Output "  Destination:    $Dest"
  Write-Output "  Mode:           $Mode"
  Write-Output "  Installed:      $installed"
  Write-Output "  Skipped:        $skipped"
  Write-Output "  Failed:         $failed"
  Write-Output '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  Write-Output ''
}

# ── Make installed scripts runnable from any working directory ───────────────
#
# Installed SKILL.md files are read by agents whose working directory is the
# user's project (VS Code, Copilot CLI/app, any harness) — never this repo.
# Repo-relative script references like ./skills/repo-health/scripts/scan-
# environment.sh, or the bare ./install-missing-tools.sh entries of the
# phase-0 auto-install table, would fail there with "No such file or
# directory". After a copy install this step:
#   1. rewrites every script reference in the installed SKILL.md to an
#      absolute path under the install destination, and
#   2. makes every bundled script executable (POSIX only — on Windows bash
#      runs .sh files regardless of file attributes),
# so all supporting scripts are runnable from any directory at any time.
# Symlink mode is dev mode (the files still live in this repo) and is left
# as-is.
#
# Idempotency: the patterns only match repo-relative references —
#   ./skills/<skill>/…,  skills/<skill>/…  (never directly preceded by '/'),
#   and ./<script>.sh when that script name ships with exactly one installed
# skill. They cannot re-match the absolute paths a previous run produced,
# because in those a '/' always sits directly before "skills" (the
# destination ends in /skills) or before the script name (/scripts/…). A
# placeholder token absorbs the relative references first and is expanded to
# the destination only after every relative pattern has been consumed.

function Build-ScriptOwnerMap {
  # $ScriptOwner[<script-basename>] = owning skill directory name, or the
  # __AMBIGUOUS__ sentinel when two installed skills ship the same script name.
  # Bare ./<script>.sh references are then left untouched; explicit
  # skills/<skill>/scripts/ references are rewritten regardless.
  # ($script: prefix — plain assignment would create a function-local table.)
  $script:ScriptOwner = @{}
  foreach ($name in $Skills) {
    $scriptsDir = [System.IO.Path]::Combine($SkillsSource, $name, 'scripts')
    if (-not (Test-Path -LiteralPath $scriptsDir -PathType Container)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $scriptsDir -Recurse -File -Filter '*.sh')) {
      $base = $file.Name
      if ($script:ScriptOwner.ContainsKey($base) -and $script:ScriptOwner[$base] -ne $name) {
        $script:ScriptOwner[$base] = '__AMBIGUOUS__'
      } elseif (-not $script:ScriptOwner.ContainsKey($base)) {
        $script:ScriptOwner[$base] = $name
      }
    }
  }
}

function Build-RewriteOps {
  # Build the ordered rewrite operations for one destination.
  # $1 = destination root whose installed skill copies references must point at.
  # Mirrors the bash installer's sed program, with the char-guard pattern
  # expressed as a one-char lookbehind so the guard character is preserved
  # (sed's captured \1, same effect).
  param([string]$Dest)
  $ops = [System.Collections.Generic.List[object]]@()
  # Repo-relative references, three spellings: "./skills/<skill>/…",
  # "skills/<skill>/…" at line start, and "skills/<skill>/…" after a
  # non-'/' character (inside `…`, after "source ", "see ", …). The non-'/'
  # guard keeps already-absolute "<dest>/skills/<skill>/…" paths untouched.
  foreach ($name in $Skills) {
    $target = "$SkillRootToken/$name/scripts/"
    $suffix = [regex]::Escape("$name/scripts/")
    $ops.Add(@{ Pattern = [regex]::Escape("./skills/$name/scripts/"); Replacement = $target })
    $ops.Add(@{ Pattern = '(?m)^skills/' + $suffix; Replacement = $target })
    $ops.Add(@{ Pattern = '(?<=[^/])skills/' + $suffix; Replacement = $target })
  }
  # Bare ./<script>.sh references (e.g. the phase-0 auto-install table),
  # only when the script name is unique across the installed skills.
  foreach ($script in $ScriptOwner.Keys) {
    $owner = $ScriptOwner[$script]
    if ($owner -eq '__AMBIGUOUS__') { continue }
    # [regex]::Escape("./…") — the "./" prefix must be escaped too; an
    # unescaped '.' would match any character ("…/scripts/x.sh" ends with
    # "s/x.sh" and would corrupt already-absolute references).
    $ops.Add(@{ Pattern = [regex]::Escape("./$script"); Replacement = "$SkillRootToken/$owner/scripts/$script" })
  }
  $Script:RewriteOps = $ops
}

function Rewrite-Text {
  # Apply the active rewrite operations, then expand the token to the real
  # destination — only after every relative pattern has been consumed.
  # Literal token expansion (String.Replace), so a destination containing
  # regex metacharacters or '&' cannot corrupt the output.
  param([string]$Text)
  foreach ($op in $Script:RewriteOps) {
    $Text = [regex]::Replace($Text, $op.Pattern, $op.Replacement.Replace('$', '$$'))
  }
  return $Text.Replace($SkillRootToken, $Dest)
}

function Rewrite-MdFile {
  # Rewrite script references in one installed markdown file, in place.
  # Returns $true only when the file changed (so callers can count rewrites).
  # ReadAllText/WriteAllText preserve line endings and write UTF-8 without BOM.
  param([string]$Path)
  $old = [System.IO.File]::ReadAllText($Path)
  $new = Rewrite-Text $old
  if ([string]::Equals($new, $old, [System.StringComparison]::Ordinal)) { return $false }
  [System.IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding($false)))
  return $true
}

function Drop-RewriteOps {
  $Script:RewriteOps = $null
}

function Make-ScriptsRunnable {
  # Post-install step per destination. See the section comment above.
  param([string]$Dest)
  if ($DryRun) {
    Write-Output "  [dry-run] would rewrite script paths in installed SKILL.md files to absolute paths under $Dest and chmod +x every script"
    return
  }
  if ($Mode -eq 'symlink') {
    Write-Output '  [note]   symlink mode — SKILL.md keeps repo-relative script paths (dev mode; run audits from this repo)'
    return
  }
  Build-RewriteOps $Dest
  $mdCount = 0
  foreach ($name in $Skills) {
    $md = [System.IO.Path]::Combine($Dest, $name, 'SKILL.md')
    if (-not (Test-Path -LiteralPath $md -PathType Leaf)) { continue }
    if (Rewrite-MdFile $md) { $mdCount++ }
  }
  Drop-RewriteOps
  if ($OnWindows) {
    # No executable bit on NTFS; bash (Git Bash/WSL) runs .sh files as-is.
    Write-Output "  [scripts] $mdCount SKILL.md file(s) now use absolute script paths; scripts run via bash (no chmod on Windows)"
  } else {
    # Executable bit on every bundled script (a +x on the sourced lib/*.sh
    # files is harmless and keeps "every script is runnable" uniformly true).
    $chmod = Get-Command chmod -ErrorAction SilentlyContinue
    if ($chmod) {
      foreach ($scriptsDir in (Get-ChildItem -LiteralPath $Dest -Recurse -Directory -Filter 'scripts')) {
        foreach ($file in (Get-ChildItem -LiteralPath $scriptsDir.FullName -Recurse -File -Filter '*.sh')) {
          & chmod +x $file.FullName 2>$null
        }
      }
    }
    Write-Output "  [scripts] $mdCount SKILL.md file(s) now use absolute script paths; all scripts executable"
  }
}

function Cleanup-LegacyPromptFiles {
  # Remove the .prompt.md files older installer versions placed into the VS Code
  # user prompts folders (<UD_ROOT>/<variant>/User/prompts) and, if present,
  # ~/.copilot/prompts/. Exact filenames only; emptied dirs are removed after.
  $promptDirs = @()
  if ($OnWindows) {
    $udRoot = $env:APPDATA
  } else {
    $udRoot = $env:XDG_CONFIG_HOME
    if (-not $udRoot) { $udRoot = [System.IO.Path]::Combine($HOME, '.config') }
  }
  if ($udRoot) {
    $promptDirs += @(
      [System.IO.Path]::Combine($udRoot, 'Code', 'User', 'prompts'),
      [System.IO.Path]::Combine($udRoot, 'Code - Insiders', 'User', 'prompts'),
      [System.IO.Path]::Combine($udRoot, 'VSCodium', 'User', 'prompts')
    )
  }
  $promptDirs += [System.IO.Path]::Combine($HOME, '.copilot', 'prompts')

  foreach ($dir in $promptDirs) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    $removed = $false
    foreach ($file in $LegacyPromptFiles) {
      $path = [System.IO.Path]::Combine($dir, $file)
      if (Test-AnyPath $path) {
        if ($DryRun) {
          Write-Output "  [dry-run] rm $path"
        } else {
          [System.IO.File]::Delete($path)
          Write-Output "  [cleanup] removed $path (replaced by generated wrapper skill)"
        }
        $removed = $true
      }
    }
    if ($removed -and -not $DryRun -and $dir.EndsWith([System.IO.Path]::Combine('User', 'prompts'))) {
      # Only the VS Code user prompts dirs get emptied-and-removed
      try { [System.IO.Directory]::Delete($dir) } catch { }
    }
  }
}

function Get-PromptMeta {
  # Extract description / argument-hint from a prompt's YAML frontmatter
  # (raw remainder after the key, any quoting kept) and the body (everything
  # after the frontmatter close, verbatim, with no frontmatter at all the
  # whole file is the body). Mirrors the bash installer's two awk passes:
  # CR line endings are normalized to LF in the body.
  param([string]$Path)
  $text = [System.IO.File]::ReadAllText($Path)
  $lines = $text -split '\r?\n'
  $description = ''
  $argHint = ''
  $bodyStart = 0
  if ($lines.Count -gt 0 -and $lines[0] -match '^---[ \t]*$') {
    for ($i = 1; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^---[ \t]*$') { $bodyStart = $i + 1; break }
      if ($lines[$i] -match '^description:[ \t]*(.*)$' -and $description -eq '') {
        $description = $Matches[1]
      } elseif ($lines[$i] -match '^argument-hint:[ \t]*(.*)$' -and $argHint -eq '') {
        $argHint = $Matches[1]
      }
    }
    if ($bodyStart -eq 0) { $bodyStart = $lines.Count }   # unterminated frontmatter → empty body
  }
  if ($bodyStart -gt 0) {
    $bodyLines = @()
    for ($i = $bodyStart; $i -lt $lines.Count; $i++) { $bodyLines += $lines[$i] }
  } else {
    $bodyLines = $lines
  }
  $body = $bodyLines -join "`n"
  if ($body -ne '' -and -not $body.EndsWith("`n")) { $body += "`n" }
  return @{ Description = $description; ArgHint = $argHint; Body = $body }
}

function Install-WrapperSkills {
  # Generate a Copilot wrapper skill per .github/prompts/*.prompt.md under
  # ~/.copilot/skills/ so the /<name> slash command works in every VS Code
  # harness, the Copilot CLI and the Copilot app. Wrappers are manual-invoke
  # only (disable-model-invocation: true) and always copied, regardless of MODE.
  $installed = 0
  $skipped = 0
  $failed = 0

  if ($PromptFiles.Count -eq 0) {
    Write-ErrLine "Error: no *.prompt.md files found in $PromptsSource"
    return
  }

  # Wrappers are used in foreign workspaces where this repo is absent, so the
  # script references in their bodies must point at the installed repo-health
  # copy under ~/.copilot/skills/.
  if (-not $DryRun) {
    Build-RewriteOps $CopilotDest
  }

  foreach ($src in $PromptFiles) {
    # Derive the skill name: basename minus .prompt.md, lowercased, spaces → hyphens
    $fileName = [System.IO.Path]::GetFileName($src)
    $name = $fileName.Substring(0, $fileName.Length - '.prompt.md'.Length)
    $name = $name.ToLowerInvariant().Replace(' ', '-')
    if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
      Write-ErrLine "Warning: skipping $fileName — derived skill name '$name' is not a valid Copilot skill name (lowercase letters, digits, hyphens)."
      continue
    }

    # Never touch a destination that belongs to a real repo skill — that skill
    # itself serves the /<name> command (e.g. the repo-health audit skill).
    $collides = $false
    foreach ($existing in $Skills) {
      if ($existing -ceq $name) {
        Write-ErrLine "Warning: skipping wrapper '$name' ($fileName) — collides with repo skill 'skills/$name'; the installed skill serves /$name itself."
        $collides = $true
        break
      }
    }
    if ($collides) { continue }

    $meta = Get-PromptMeta $src
    $description = $meta.Description
    if ($description -eq '') { $description = "Manual wrapper: $name audit command." }
    $argHint = $meta.ArgHint

    $dst = [System.IO.Path]::Combine($CopilotDest, $name)

    # ── Check if destination exists ─────────────────────────────────
    if (Test-AnyPath $dst) {
      if ($DryRun) {
        Write-Output "  [dry-run] $name  ->  $dst  (would replace existing, mode: copy)"
        $installed++
        continue
      }
      if ($SkipExisting) {
        Write-Output "  [skip]   $name  (already exists at $dst)"
        $skipped++
        continue
      }
      if (-not $Force) {
        Write-Output "  [exist]  $name  already installed at $dst"
        Write-Output '           Use --force to overwrite, --skip to skip existing,'
        Write-Output "           or remove it manually: $(Get-RemoveHint $dst)"
        $reply = ''
        try { $reply = Read-Host "           Overwrite at $CopilotDest? [y/N]" } catch { $reply = '' }
        if ($reply -cne 'y' -and $reply -cne 'Y' -and $reply -cne 'yes' -and $reply -cne 'YES') {
          Write-Output ('           Skipping ' + $name + '.')
          $skipped++
          continue
        }
      }
      # Remove existing (wrapper skills are directories)
      Remove-SkillPath $dst
    }

    # ── Install ────────────────────────────────────────────────────
    if ($DryRun) {
      Write-Output "  [dry-run] $name  ->  $dst  (mode: copy)"
      $installed++
      continue
    }

    $dstDir = $dst
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    $mdLines = [System.Collections.Generic.List[string]]@(
      '---',
      "name: $name",
      "description: $description"
    )
    if ($argHint -ne '') { $mdLines.Add("argument-hint: $argHint") }
    $mdLines.Add('disable-model-invocation: true')
    $mdLines.Add('---')
    $content = ($mdLines -join "`n") + "`n" + $meta.Body
    $mdPath = [System.IO.Path]::Combine($dstDir, 'SKILL.md')
    [System.IO.File]::WriteAllText($mdPath, $content, (New-Object System.Text.UTF8Encoding($false)))
    # Same treatment as installed skills: the wrapper's script references must
    # resolve in any workspace, not just in this repo.
    Rewrite-MdFile $mdPath | Out-Null
    Write-Output "  [copy]   $name  ->  $dst"
    $installed++
    $WrappersInstalled.Add($name)

    # ── Post-install sanity ─────────────────────────────────────────
    if (-not (Test-Path -LiteralPath $mdPath -PathType Leaf)) {
      Write-ErrLine "  Warning: SKILL.md not found at $mdPath — wrapper may be incomplete."
    }
  }

  # ── Summary (per destination) ────────────────────────────────────────────

  Write-Output ''
  Write-Output '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  Write-Output "  Destination:    $CopilotDest  (Copilot wrapper skills generated from .github/prompts — /name slash commands, all harnesses)"
  Write-Output '  Mode:           copy'
  Write-Output "  Installed:      $installed"
  Write-Output "  Skipped:        $skipped"
  Write-Output "  Failed:         $failed"
  Write-Output '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  Write-Output ''
  Drop-RewriteOps
}

# ── Main flow ────────────────────────────────────────────────────────────────

Build-ScriptOwnerMap

foreach ($dest in $Dests) {
  Install-Into $dest
  Make-ScriptsRunnable $dest
}

# ── Legacy prompt cleanup + Copilot wrapper skills ───────────────────────────
# Runs unless --dest or --no-copilot. Output reads top-down: skills → cleanup
# → wrappers.

if ($CustomDest -eq '' -and -not $NoCopilot) {
  Cleanup-LegacyPromptFiles
  Install-WrapperSkills
}

if ($DryRun) {
  Write-Output 'Dry-run complete. Run without --dry-run to actually install.'
  exit 0
}

# ── Final hints ─────────────────────────────────────────────────────────────

if ($Mode -eq 'symlink') {
  Write-Output '⚠  Symlinked — if you remove or move this repo, the skills will break.'
}

Write-Output 'Skills installed. Read automatically from:'
foreach ($dest in $Dests) {
  if ($dest -eq $CopilotDest) {
    Write-Output "  $dest  (GitHub Copilot personal skills — VS Code extension, CLI, app)"
  } else {
    Write-Output "  $dest"
  }
}

if ($CustomDest -eq '' -and -not $NoCopilot) {
  Write-Output ''
  if ($WrappersInstalled.Count -gt 0) {
    Write-Output 'Copilot wrapper skills generated (manual invoke only — disable-model-invocation: true):'
    foreach ($wname in $WrappersInstalled) {
      Write-Output "  $([System.IO.Path]::Combine($CopilotDest, $wname))  (/$wname)"
    }
  } else {
    Write-Output "No Copilot wrapper skills were generated from $PromptsSource."
  }
  Write-Output '  /repo-health is served by the audit skill itself; /repo-health-fix by its'
  Write-Output '  wrapper. In this workspace, .github/prompts/*.prompt.md still register the'
  Write-Output '  commands for the Chat view (Local).'
}

if ($CustomDest -eq '' -and -not $NoCopilot) {
  Write-Output ''
  Write-Output 'OpenCode reads skills from:'
  Write-Output "  1. $DefaultDest (user-installed, highest priority)"
  Write-Output '  2. $PWD/skills/ (project-local)'
}
Write-Output ''

Write-Output 'To verify:'
foreach ($dest in $Dests) {
  if ($OnWindows) {
    Write-Output "  Get-ChildItem -Force `"$dest`""
  } else {
    Write-Output "  ls -la `"$dest`""
  }
}

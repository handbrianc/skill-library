#!/usr/bin/env pwsh
# ============================================================================
# test-install-scripts.ps1 — Windows installer integration test: script
# accessibility (PowerShell port of tests/test-install-scripts.sh)
# ============================================================================
#
# Verifies that a copy install with install-skills.ps1 produces
# self-contained skills:
#   1. no repo-relative script references remain in installed SKILL.md files
#      (agents run in the user's project, where ./skills/... cannot resolve),
#   2. full-path and bare ./<script>.sh references point at the destination,
#   3. every bundled script is executable (POSIX hosts; n/a on Windows),
#   4. the support scripts actually run from a foreign working directory
#      (POSIX hosts, or Windows with bash installed),
#   5. re-running the installer does not re-rewrite already-rewritten files.
#
# Runs the real installer into a throwaway destination; never touches
# ~/.copilot or ~/.config/opencode.
#
# Usage:
#   pwsh -NoProfile -File tests/test-install-scripts.ps1
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$Installer = Join-Path $RepoRoot 'install-skills.ps1'
$PsExe = (Get-Process -Id $PID).Path

$TmpBase = $env:TMPDIR
if (-not $TmpBase) { $TmpBase = [System.IO.Path]::GetTempPath() }
$Tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$Dest = (New-Item -ItemType Directory -Path (Join-Path $TmpBase "install-skills-test-$Tag")).FullName
$ForeignCwd = (New-Item -ItemType Directory -Path (Join-Path $TmpBase "install-skills-test-cwd-$Tag")).FullName
$script:Failures = 0

function Pass([string]$Message) { Write-Host "    ✓ $Message" }
function Fail([string]$Message) {
  Write-Host "    ✖ $Message" -ForegroundColor Red
  $script:Failures++
}
function JoinRepo([string]$Base, [string]$RepoRelative) {
  # '/'-separated repo-relative fragment -> native path under $Base
  # (accumulate: PowerShell does not splat arrays into .NET params methods)
  $result = $Base
  foreach ($part in ($RepoRelative -split '/')) {
    if ($part -ne '') { $result = [System.IO.Path]::Combine($result, $part) }
  }
  return $result
}

Write-Host "  Destination: $Dest"
Write-Host "  Foreign CWD: $ForeignCwd"
Write-Host ''

try {
  # ── 1. Install (copy mode, single throwaway destination, no Copilot flow) ──

  & $PsExe -NoProfile -File $Installer --dest $Dest *> $null
  if ($LASTEXITCODE -eq 0) {
    Pass 'installer completed (copy mode, --dest)'
  } else {
    Fail "installer exited with code $LASTEXITCODE"
  }

  # ── 2. No repo-relative script references remain in installed SKILL.md ────

  $Leftover = @()
  Get-ChildItem -LiteralPath $Dest -Recurse -File -Filter '*.md' | ForEach-Object {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($_.FullName)) {
      $lineNo++
      if ($line -cmatch '(^|[^/])(\./)?skills/[a-z0-9-]+/(scripts|SKILL\.md)') {
        $Leftover += "$($_.FullName):${lineNo}: $line"
      }
    }
  }
  if ($Leftover.Count -eq 0) {
    Pass 'no repo-relative skill/script references remain in installed SKILL.md files'
  } else {
    Fail 'relative references remain in installed SKILL.md files:'
    $Leftover | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
  }

  # ── 3. The reported failure's commands are now absolute and self-consistent

  $P0 = JoinRepo $Dest 'repo-health--phase-0-environment/SKILL.md'
  $p0Text = [System.IO.File]::ReadAllText($P0)
  if ($p0Text.Contains("$Dest/repo-health/scripts/install-missing-tools.sh gnu-grep coreutils gnu-date")) {
    Pass 'phase-0 GNU toolchain command points at the installed scripts'
  } else {
    Fail 'phase-0 GNU toolchain command was not rewritten to the install destination'
  }
  if ($p0Text.Contains("$Dest/repo-health/scripts/install-missing-tools.sh --filter=test")) {
    Pass 'phase-0 bare table commands (./install-missing-tools.sh) made absolute'
  } else {
    Fail 'phase-0 bare table command was not rewritten'
  }
  if ($p0Text.Contains("$Dest/repo-health/scripts/scan-environment.sh --check-tools")) {
    Pass 'phase-0 scan-environment.sh command made absolute'
  } else {
    Fail 'phase-0 scan-environment.sh command was not rewritten'
  }

  # ── 4. Every bundled script is executable ─────────────────────────────────

  if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    Pass 'exec-bit check not applicable on Windows (scripts run via bash/WSL)'
  } else {
    $NonExec = @()
    Get-ChildItem -LiteralPath $Dest -Recurse -File -Filter '*.sh' | ForEach-Object {
      $mode = $_.UnixFileMode
      if (([int]$mode -band [int][System.IO.UnixFileMode]::UserExecute) -eq 0) {
        $NonExec += $_.FullName
      }
    }
    if ($NonExec.Count -eq 0) {
      Pass 'every installed script is executable'
    } else {
      Fail 'installed scripts missing the executable bit:'
      $NonExec | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
    }
  }

  # ── 5. The support scripts run from a foreign working directory ───────────

  if (Get-Command bash -ErrorAction SilentlyContinue) {
    Push-Location $ForeignCwd
    try {
      & bash (JoinRepo $Dest 'repo-health/scripts/install-missing-tools.sh') --check-only *> $null
      if ($LASTEXITCODE -eq 0) {
        Pass 'install-missing-tools.sh --check-only runs from a foreign working directory'
      } else {
        Fail 'install-missing-tools.sh --check-only failed from a foreign working directory'
      }
      & bash (JoinRepo $Dest 'repo-health/scripts/scan-environment.sh') --check-tools *> $null
      if ($LASTEXITCODE -eq 0) {
        Pass 'scan-environment.sh --check-tools runs from a foreign working directory'
      } else {
        Fail 'scan-environment.sh --check-tools failed from a foreign working directory'
      }
    } finally {
      Pop-Location
    }
  } else {
    Write-Host '    ⚠ skipped script run check (no bash — install Git Bash or WSL on Windows)'
  }

  # ── 6. Rewrite is idempotent (a --skip re-run changes nothing) ────────────

  $Files = @(
    'repo-health/SKILL.md',
    'repo-health--phase-0-environment/SKILL.md',
    'spec-compliance/SKILL.md'
  )
  $Hash1 = ($Files | ForEach-Object { (Get-FileHash -LiteralPath (JoinRepo $Dest $_) -Algorithm SHA256).Hash }) -join '|'
  & $PsExe -NoProfile -File $Installer --dest $Dest --skip *> $null
  if ($LASTEXITCODE -ne 0) { Fail "installer --skip re-run exited with code $LASTEXITCODE" }
  $Hash2 = ($Files | ForEach-Object { (Get-FileHash -LiteralPath (JoinRepo $Dest $_) -Algorithm SHA256).Hash }) -join '|'
  if ($Hash1 -ceq $Hash2) {
    Pass 'rewrite is idempotent — --skip re-run left installed SKILL.md files unchanged'
  } else {
    Fail 'second installer run modified already-rewritten SKILL.md files'
  }
} finally {
  Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $ForeignCwd -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures -eq 0) {
  Write-Host '  ✅ Installer script-accessibility test passed'
  exit 0
} else {
  Write-Host "  ❌ $script:Failures installer script-accessibility test failure(s)"
  exit 1
}

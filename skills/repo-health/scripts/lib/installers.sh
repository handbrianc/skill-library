#!/usr/bin/env bash
# lib/installers.sh — Individual tool installer functions
#
# Sourced by install-missing-tools.sh. Each function is named install_<tool>
# and is mapped via the INSTALLERS dispatch table in the main script.
#
# These functions reference global variables set by the main script:
#   OS, PKG_MANAGER, PKG_INSTALL, REPO_ROOT
# And helper functions:
#   tool_missing, ok, warn, err, info, sub, as_root

# shellcheck disable=SC2317 # called dynamically via dispatch table

install_go() {
  if ! tool_missing go; then ok "go already installed $(go version 2>/dev/null | grep -oP 'go[\d.]+' || true)"; return 0; fi
  case "$OS" in
    linux)
      info "Downloading latest Go from golang.org..."
      local ver go_tarball
      ver=$(curl -sL https://go.dev/VERSION?m=text 2>/dev/null | head -1 || echo "go1.22.5")
      go_tarball="${ver}.linux-amd64.tar.gz"
      curl -sLO "https://go.dev/dl/${go_tarball}" &&
      as_root rm -rf /usr/local/go &&
      as_root tar -C /usr/local -xzf "${go_tarball}" &&
      rm -f "${go_tarball}" &&
      info "Add to PATH: export PATH=\$PATH:/usr/local/go/bin" ||
      err "Go download failed — install manually: https://go.dev/dl/"
      ;;
    macos)
      as_root brew install go
      ;;
  esac
}

install_cargo() {
  if ! tool_missing cargo; then ok "cargo already installed $(cargo --version 2>/dev/null || true)"; return 0; fi
  info "Installing Rust/cargo via rustup..."
  if command -v rustup &>/dev/null; then
    rustup install stable 2>&1 | tail -1
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tail -3
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env" 2>/dev/null || true
  fi
}

install_semgrep() {
  if ! tool_missing semgrep; then ok "semgrep already installed"; return 0; fi
  if command -v pip3 &>/dev/null; then
    pip3 install semgrep 2>&1 | tail -2 || as_root pip3 install semgrep 2>&1 | tail -2
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    as_root brew install semgrep
  fi
}

install_syft() {
  if ! tool_missing syft; then ok "syft already installed"; return 0; fi
  case "$OS" in
    linux) as_root bash -c "curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin" 2>&1 | tail -1 ;;
    macos) as_root brew install syft ;;
  esac
}

install_grype() {
  if ! tool_missing grype; then ok "grype already installed"; return 0; fi
  case "$OS" in
    linux) curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin 2>&1 | tail -1 ;;
    macos) as_root brew install grype ;;
  esac
}

install_flake8() {
  if ! tool_missing flake8; then ok "flake8 already installed"; return 0; fi
  pip3 install flake8 2>&1 | tail -1 || as_root pip3 install flake8 2>&1 | tail -1
}

install_black() {
  if ! tool_missing black; then ok "black already installed"; return 0; fi
  pip3 install black 2>&1 | tail -1 || as_root pip3 install black 2>&1 | tail -1
}

install_prettier() {
  if ! tool_missing prettier; then
    ok "prettier already installed"
  elif command -v npm &>/dev/null; then
    npm install -g prettier 2>&1 | tail -1
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    as_root brew install prettier
  fi
  # Also ensure local project install
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    (cd "$REPO_ROOT" && npm install --save-dev prettier 2>/dev/null) && ok "prettier added to project devDependencies"
  fi
}

install_typescript() {
  if ! tool_missing tsc; then ok "tsc already installed"; return 0; fi
  if command -v npm &>/dev/null; then
    npm install -g typescript 2>&1 | tail -1
  fi
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    (cd "$REPO_ROOT" && npm install --save-dev typescript 2>/dev/null) && ok "typescript added to project devDependencies"
  fi
}

install_vitest() {
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    (cd "$REPO_ROOT" && npm install --save-dev vitest 2>/dev/null) && ok "vitest added to project devDependencies"
  else
    npm install -g vitest 2>&1 | tail -1
  fi
}

install_jest() {
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    (cd "$REPO_ROOT" && npm install --save-dev jest 2>/dev/null) && ok "jest added to project devDependencies"
  else
    npm install -g jest 2>&1 | tail -1
  fi
}

install_npm_check_updates() {
  if ! tool_missing npm-check-updates; then ok "npm-check-updates already installed"; return 0; fi
  npm install -g npm-check-updates 2>&1 | tail -1
}

install_ts_prune() {
  if command -v npx &>/dev/null; then
    if [[ -f "$REPO_ROOT/package.json" ]]; then
      (cd "$REPO_ROOT" && npm install --save-dev ts-prune 2>/dev/null) && ok "ts-prune added to project devDependencies"
    fi
  fi
}

# System packages
install_bc() {
  if ! tool_missing bc; then ok "bc already installed"; return 0; fi
  case "$PKG_MANAGER" in
    apt) as_root apt-get install -y -qq bc 2>&1 | tail -1 ;;
    dnf|yum) as_root "$PKG_INSTALL" bc 2>&1 | tail -1 ;;
    apk) as_root apk add -q bc 2>&1 | tail -1 ;;
    brew) as_root brew install bc 2>&1 | tail -1 ;;
    zypper) as_root zypper install -y bc 2>&1 | tail -1 ;;
  esac
}

install_zip() {
  if ! tool_missing zip; then ok "zip already installed"; return 0; fi
  case "$PKG_MANAGER" in
    apt) as_root apt-get install -y -qq zip 2>&1 | tail -1 ;;
    dnf|yum) as_root "$PKG_INSTALL" zip 2>&1 | tail -1 ;;
    apk) as_root apk add -q zip 2>&1 | tail -1 ;;
    brew) as_root brew install zip 2>&1 | tail -1 ;;
    zypper) as_root zypper install -y zip 2>&1 | tail -1 ;;
  esac
}

install_xmlstarlet() {
  if ! tool_missing xmlstarlet; then ok "xmlstarlet already installed"; return 0; fi
  # Check both xpath and xmlstarlet
  if command -v xpath &>/dev/null && command -v xmlstarlet &>/dev/null; then ok "xpath/xmlstarlet already installed"; return 0; fi
  case "$PKG_MANAGER" in
    apt) as_root apt-get install -y -qq libxml-xpath-perl xmlstarlet 2>&1 | tail -1 ;;
    dnf|yum) as_root "$PKG_INSTALL" perl-XML-XPath xmlstarlet 2>&1 | tail -1 ;;
    apk) as_root apk add -q xmlstarlet 2>&1 | tail -1 ;;
    brew) as_root brew install xmlstarlet 2>&1 | tail -1 ;;
    zypper) as_root zypper install -y xmlstarlet 2>&1 | tail -1 ;;
  esac
}

install_jscpd() {
  if command -v npm &>/dev/null; then
    npm install -g jscpd 2>&1 | tail -1 || true
  fi
}

install_golangci_lint() {
  if ! tool_missing golangci-lint; then ok "golangci-lint already installed"; return 0; fi
  case "$OS" in
    linux) curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /usr/local/bin 2>&1 | tail -1 ;;
    macos) as_root brew install golangci-lint ;;
  esac
}

install_rubocop() {
  if ! tool_missing rubocop; then ok "rubocop already installed"; return 0; fi
  if command -v gem &>/dev/null; then
    gem install rubocop 2>&1 | tail -1
  elif [[ "$PKG_MANAGER" == "brew" ]]; then
    as_root brew install rubocop
  fi
}

install_checkstyle() {
  if ! tool_missing checkstyle; then ok "checkstyle already installed"; return 0; fi
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    as_root brew install checkstyle
  elif command -v apt-get &>/dev/null; then
    as_root apt-get install -y -qq checkstyle 2>&1 | tail -1
  else
    warn "checkstyle: install manually from https://checkstyle.org/download.html"
  fi
}

install_dotnet() {
  if ! tool_missing dotnet; then ok "dotnet already installed"; return 0; fi
  warn "dotnet: install manually from https://dotnet.microsoft.com/download"
  info "  Linux:   curl -sL https://dot.net/v1/dotnet-install.sh | bash"
  info "  macOS:   brew install --cask dotnet-sdk"
}

install_ktlint() {
  if ! tool_missing ktlint; then ok "ktlint already installed"; return 0; fi
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    as_root brew install ktlint
  else
    curl -sSLO https://github.com/pinterest/ktlint/releases/latest/download/ktlint &&
    chmod +x ktlint && as_root mv ktlint /usr/local/bin/ &&
    ok "ktlint installed"
  fi
}

install_swiftlint() {
  if ! tool_missing swiftlint; then ok "swiftlint already installed"; return 0; fi
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    as_root brew install swiftlint
  else
    warn "swiftlint: install via mint: mint install realm/SwiftLint"
  fi
}

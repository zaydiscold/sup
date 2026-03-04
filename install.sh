#!/usr/bin/env bash
set -euo pipefail

REPO="zaydiscold/sup"
RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
INSTALL_DIR="${HOME}/.local/bin"
INSTALL_PATH="${INSTALL_DIR}/sup"

info()  { printf '\033[0;36m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

check_bash_version() {
    if (( ${BASH_VERSINFO[0]:-0} < 4 )); then
        warn "Bash 4+ is required (you have ${BASH_VERSION:-unknown})."
        if [[ "$(uname -s)" == "Darwin" ]]; then
            cat >&2 <<'HINT'
macOS ships Bash 3.2 by default. Install a newer Bash first:
  brew install bash
Then re-run this installer:
  /opt/homebrew/bin/bash install.sh   # Apple Silicon
  /usr/local/bin/bash install.sh      # Intel Mac
HINT
        fi
        exit 1
    fi
}

warn_if_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        warn "Running as root is not recommended. sup installs to ~/.local/bin."
    fi
}

compute_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 1
    fi
}

path_contains() {
    case ":${PATH}:" in
        *":$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

detect_shell_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-bash}")"
    case "$shell_name" in
        zsh)  printf '%s' "${HOME}/.zshrc" ;;
        bash) printf '%s' "${HOME}/.bashrc" ;;
        fish) printf '%s' "${HOME}/.config/fish/config.fish" ;;
        *)    printf '%s' "${HOME}/.bashrc" ;;
    esac
}

prompt_yn() {
    local reply=""
    if [[ -t 0 ]]; then
        read -r -p "$1" reply
    elif [[ -r /dev/tty ]]; then
        read -r -p "$1" reply </dev/tty
    else
        return 1
    fi
    case "$reply" in
        ""|[Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

maybe_add_to_path() {
    path_contains "$INSTALL_DIR" && return 0

    local rc_file path_line
    rc_file="$(detect_shell_rc)"
    if [[ "$rc_file" == *.fish ]]; then
        path_line='fish_add_path $HOME/.local/bin'
    else
        path_line='export PATH="$HOME/.local/bin:$PATH"'
    fi

    printf '\n  %s is not in your PATH.\n\n' "$INSTALL_DIR"
    printf '  Add it to your shell config? [Y/n]\n'
    printf '    → Will append to: %s\n\n' "$rc_file"

    if prompt_yn "> "; then
        touch "$rc_file"
        if grep -Fqx "$path_line" "$rc_file" 2>/dev/null; then
            info "PATH line already present in ${rc_file}."
        else
            printf '\n%s\n' "$path_line" >> "$rc_file"
            info "Added PATH to ${rc_file}. Open a new shell or run:"
            printf '  %s\n' "$path_line"
        fi
    else
        warn "Skipped PATH update. You may need to add ~/.local/bin to PATH manually."
    fi
}

main() {
    check_bash_version
    warn_if_root

    command -v curl >/dev/null 2>&1 || die "curl is required but not found."
    command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
        || die "sha256sum or shasum is required for checksum verification."

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    local tmp_script="${tmp_dir}/sup.sh"
    local tmp_checksums="${tmp_dir}/checksums.txt"

    info "Downloading sup.sh..."
    curl -fsSL --retry 3 --connect-timeout 10 \
        "${RELEASE_BASE}/sup.sh" -o "$tmp_script" \
        || die "Failed to download sup.sh"

    info "Downloading checksums.txt..."
    curl -fsSL --retry 3 --connect-timeout 10 \
        "${RELEASE_BASE}/checksums.txt" -o "$tmp_checksums" \
        || die "Failed to download checksums.txt"

    local expected actual
    expected="$(awk '$2 == "sup.sh" || $2 == "./sup.sh" { gsub(/\*/, "", $2); print $1; exit }' "$tmp_checksums")"
    [[ -n "$expected" ]] || die "Could not find sup.sh entry in checksums.txt"

    actual="$(compute_sha256 "$tmp_script")" || die "No SHA-256 tool available."

    if [[ "$actual" != "$expected" ]]; then
        die "Checksum mismatch!\n  Expected: ${expected}\n  Got:      ${actual}"
    fi
    info "Checksum verified."

    mkdir -p "$INSTALL_DIR"
    chmod +x "$tmp_script"
    mv "$tmp_script" "$INSTALL_PATH"

    info "Installed to ${INSTALL_PATH}"
    maybe_add_to_path

    printf '\n  ✓ sup installed successfully. Run: sup\n\n'
}

main "$@"

#!/usr/bin/env bash
# SUP — AI-native universal updater
# https://github.com/zaydiscold/sup  |  MIT License
# Single-file Bash 4+ tool. `cat $(which sup)` to audit.
set -uo pipefail

# ── Bash version gate ─────────────────────────────────────
if (( BASH_VERSINFO[0] < 4 )); then
    printf '\033[0;31m  ✗  sup requires Bash 4.0+. You have %s.\033[0m\n' "$BASH_VERSION" >&2
    printf '     Install with: brew install bash\n' >&2
    printf '     Then run: /opt/homebrew/bin/bash -c "sup"\n' >&2
    exit 3
fi

# ── Constants ─────────────────────────────────────────────
readonly SUP_VERSION="1.0.0"
CURRENT_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
readonly CURRENT_OS
readonly SUP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sup"
readonly SUP_PREF_FILE="$SUP_CONFIG_DIR/preferences"
readonly SUP_LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sup"
readonly SUP_LOG_FILE="$SUP_LOG_DIR/last.log"
readonly SUP_REPO="zaydiscold/sup"
readonly SUP_RELEASE_BASE="https://github.com/${SUP_REPO}/releases/latest/download"

# ── Colors (disabled when not a TTY) ─────────────────────
if [[ -t 1 ]]; then
    readonly RESET='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m' CYAN='\033[0;36m' DIM='\033[2m'
    readonly BOLD='\033[1m'
else
    readonly RESET='' RED='' GREEN='' YELLOW='' CYAN='' DIM='' BOLD=''
fi

# ── Logging ───────────────────────────────────────────────
mkdir -p "$SUP_LOG_DIR"
: > "$SUP_LOG_FILE"

log_file() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SUP_LOG_FILE"; }
log_file "sup v${SUP_VERSION} starting on ${CURRENT_OS} (bash ${BASH_VERSION})"

print_red()    { printf "${RED}%s${RESET}\n" "$*"; }
print_green()  { printf "${GREEN}%s${RESET}\n" "$*"; }
print_yellow() { printf "${YELLOW}%s${RESET}\n" "$*"; }
print_cyan()   { printf "${CYAN}%s${RESET}\n" "$*"; }

usage() {
    cat <<'EOF'
SUP — AI-native universal updater

Usage:
  sup [flags]
  sup config

With no flags, `sup` detects and updates all installed tools.
Use `sup --list` to see valid tool IDs for `--skip` and `--only`.

Flags:
  --help             Print usage information
  --version          Print version
  --self-update      Update sup itself (checksum verified)
  --interactive      Interactive tool picker (TUI)
  --skip <tool>      Skip a specific tool (repeatable)
  --only <tool>      Update only specific tool(s) (repeatable)
  --list             List supported tools and current detection status
  --yes              Skip confirmation prompt
  --no-cleanup       Skip cleanup commands
  --dry-run          Show what would run, make no changes
  --verbose          Print step execution details
EOF
}

# ── Global state ──────────────────────────────────────────
declare -a STEP_ORDER=()
declare -A STEP_OS=() STEP_RISK=() STEP_SUDO=() STEP_LABEL=() STEP_TIMEOUT=()
declare -a FOUND_TOOLS=()
declare -A RESULTS=() ERRORS=() TIMINGS=()
declare -a TEMP_FILES=()

BREW_LIST="" ; BREW_CASK_LIST="" ; BREW_FULL_LIST=""
NPM_GLOBAL_LIST="" ; PIPX_LIST="" ; UV_TOOL_LIST=""
declare -A BREW_PKG_MAP=() NPM_PKG_MAP=() PIPX_PKG_MAP=() UV_TOOL_MAP=()

SUDO_CMD=""
NETWORK_AVAILABLE=true  # exported for future use by tool functions
export NETWORK_AVAILABLE
TOTAL_OK=0 ; TOTAL_FAIL=0 ; TOTAL_SKIP=0
RUN_START=0

# Flags
FLAG_YES=false ; FLAG_DRY_RUN=false ; FLAG_LIST=false
FLAG_VERBOSE=false ; FLAG_SELF_UPDATE=false
FLAG_INTERACTIVE=false
SUBCOMMAND=""

# Preferences (defaults)
SUP_CLEANUP=true
SUP_BREW_GREEDY=false
SUP_AUTO_RETRY=true
SUP_ALLOW_REMOTE_INSTALLER_UPDATES=false
SUP_SKIP_TOOLS=""

declare -A CLI_SKIP=() CLI_ONLY=()

# ── Helpers ───────────────────────────────────────────────
_has() { command -v "$1" >/dev/null 2>&1; }
_is_true() { case "${1:-}" in true|1|yes|on) return 0;; *) return 1;; esac; }

_trim() {
    local s="${1:-}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_list_has() {
    local list="$1" needle="$2"
    [[ -n "$needle" ]] || return 1
    printf '%s\n' "$list" | grep -qxF "$needle"
}

version_gt() {
    [[ "$1" == "$2" ]] && return 1
    local IFS=. i
    local -a a b
    read -r -a a <<< "$1"
    read -r -a b <<< "$2"
    for (( i=0; i < ${#a[@]} || i < ${#b[@]}; i++ )); do
        local x_raw=${a[i]:-0} y_raw=${b[i]:-0}
        local x="${x_raw%%[^0-9]*}" y="${y_raw%%[^0-9]*}"
        [[ -z "$x" ]] && x=0
        [[ -z "$y" ]] && y=0
        (( x > y )) && return 0
        (( x < y )) && return 1
    done
    return 1
}

compute_sha256() {
    if _has sha256sum; then
        sha256sum "$1" | awk '{print $1}'
    elif _has shasum; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        print_red "  ✗  No SHA-256 tool found."
        return 1
    fi
}

# ── Cleanup / signal handling ─────────────────────────────
cleanup_temp() {
    (( ${#TEMP_FILES[@]} == 0 )) && return 0
    local f
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f" "${f}.reason" 2>/dev/null || true
    done
}

cleanup_and_exit() {
    trap - EXIT
    printf '\n'
    print_yellow "  Interrupted. Cleaning up..."
    local pids pid
    pids="$(jobs -p 2>/dev/null)"
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            kill -TERM -- "-$pid" 2>/dev/null || true
            kill "$pid" 2>/dev/null || true
        done
    fi
    cleanup_temp
    if (( ${#RESULTS[@]} > 0 )); then print_summary; fi
    exit 130
}

trap cleanup_temp EXIT
trap cleanup_and_exit INT TERM

# ── Sudo ──────────────────────────────────────────────────
detect_sudo() {
    local cmd
    for cmd in doas sudo pkexec; do
        if _has "$cmd"; then SUDO_CMD="$cmd"; return 0; fi
    done
    SUDO_CMD=""
    return 1
}

pre_elevate() {
    [[ -z "$SUDO_CMD" ]] && return 0
    case "$SUDO_CMD" in
        sudo) $SUDO_CMD -v ;;
        *)    $SUDO_CMD echo >/dev/null 2>&1 ;;
    esac
}

maybe_sudo() {
    if [[ -n "$SUDO_CMD" ]]; then
        $SUDO_CMD "$@"
    else
        "$@"
    fi
}

ensure_sudo() {
    local label="$1"
    if [[ -z "$SUDO_CMD" ]]; then
        print_yellow "  ⚠  $label requires elevated permissions but no sudo found. Skipping."
        return 1
    fi
    pre_elevate
}

warn_and_confirm() {
    local label="$1"
    _is_true "$FLAG_YES" && return 0
    if [[ ! -t 0 ]]; then
        print_yellow "  Non-interactive input detected; skipping risky update: $label"
        return 1
    fi
    printf "  ${YELLOW}⚠${RESET}  %s is marked as risky. Continue? [y/N] " "$label"
    local reply=""
    if ! read -r reply < /dev/tty; then
        return 1
    fi
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Network ───────────────────────────────────────────────
check_network() {
    if ! curl -sI --max-time 5 "https://github.com" >/dev/null 2>&1; then
        print_yellow "  ⚠  No internet detected. Most updates need network access."
        print_yellow "     Some tools may fail. Continuing anyway..."
        printf '\n'
        NETWORK_AVAILABLE=false
    else
        NETWORK_AVAILABLE=true
    fi
}

# ── Timeout / retry ───────────────────────────────────────
run_with_timeout() {
    local secs="$1"; shift
    local func="$1"
    local grace=5

    declare -F "$func" >/dev/null 2>&1 || return 127
    "$func" &
    local pid=$!
    local start_ts now_ts

    start_ts=$(date +%s)
    while kill -0 "$pid" 2>/dev/null; do
        now_ts=$(date +%s)
        if (( now_ts - start_ts >= secs )); then
            # Avoid timeout misclassification when the child exits
            # between the loop check and timeout branch.
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid" 2>/dev/null
                return "$?"
            fi
            if ! kill -TERM "$pid" 2>/dev/null; then
                wait "$pid" 2>/dev/null
                return "$?"
            fi

            # Grace period before force-kill in case the command ignores SIGTERM.
            local grace_start
            grace_start=$(date +%s)
            while kill -0 "$pid" 2>/dev/null; do
                now_ts=$(date +%s)
                if (( now_ts - grace_start >= grace )); then
                    kill -KILL "$pid" 2>/dev/null || true
                    break
                fi
                sleep 0.2
            done

            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 0.2
    done

    wait "$pid" 2>/dev/null
    return "$?"
}

run_with_retry() {
    local step="$1" timeout="$2" stderr_file="$3"
    local max_attempts=2
    _is_true "$SUP_AUTO_RETRY" || max_attempts=1

    local attempt rc=0
    for (( attempt=1; attempt <= max_attempts; attempt++ )); do
        run_with_timeout "$timeout" "update_${step}" 2>>"$stderr_file"
        rc=$?
        (( rc == 0 )) && return 0

        if (( attempt < max_attempts )); then
            log_file "Retrying $step (attempt $((attempt+1)), rc=$rc)"
            : > "$stderr_file"
        fi
    done

    classify_error "$step" "$rc" "$stderr_file"
    return "$rc"
}

# ── Error classification ──────────────────────────────────
classify_error() {
    local step="$1" exit_code="$2" stderr_file="$3"
    local reason

    if (( exit_code == 124 )); then
        reason="Timed out after ${STEP_TIMEOUT[$step]:-?}s."
    elif grep -qiE 'EACCES|permission denied' "$stderr_file" 2>/dev/null; then
        reason="Permission denied. Try running the update with sudo."
    elif grep -qiE 'could not resolve|connection refused|network' "$stderr_file" 2>/dev/null; then
        reason="Network error. Check your connection."
    elif grep -qiE '404|not found|no such package' "$stderr_file" 2>/dev/null; then
        reason="Package/registry not found. May be deprecated."
    elif grep -qiE 'conflict|dependency' "$stderr_file" 2>/dev/null; then
        reason="Dependency conflict. Run the update manually."
    else
        reason=$(head -2 "$stderr_file" 2>/dev/null | tr '\n' ' ')
        [[ -z "$reason" ]] && reason="Unknown error (exit code $exit_code)."
    fi

    printf '%s\n' "$reason" > "${stderr_file}.reason"
}

# ── Spinner ───────────────────────────────────────────────
spin_while() {
    local pid="$1" label="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    [[ -t 1 ]] || return 0

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s %s' "${frames[i++ % ${#frames[@]}]}" "$label"
        sleep 0.1
    done
    printf '\r\033[2K'
}

show_spinner_ok() {
    local label="$1" elapsed="$2"
    printf "  ${GREEN}✓${RESET}  %-24s ${DIM}%ds${RESET}\n" "$label" "$elapsed"
}

show_spinner_fail() {
    local label="$1" elapsed="$2"
    printf "  ${RED}✗${RESET}  %-24s ${DIM}%ds${RESET}\n" "$label" "$elapsed"
}

show_spinner_skip() {
    local label="$1"
    printf "  ${DIM}·${RESET}  %-24s ${DIM}skipped${RESET}\n" "$label"
}

# ── Interactive selector (v1.1 TUI mode) ─────────────────
choose_with_gum() {
    local -a options=("$@")
    _has gum || return 1
    gum choose \
        --no-limit \
        --header "Select tools to update (space to toggle, enter to confirm)" \
        "${options[@]}"
}

choose_with_fzf() {
    local -a options=("$@")
    _has fzf || return 1
    printf '%s\n' "${options[@]}" \
        | fzf --multi --height=60% --reverse \
              --prompt='sup> ' \
              --header='Tab select • Enter confirm • Esc cancel'
}

choose_with_builtin() {
    local -a options=("$@")
    local count=${#options[@]}
    (( count > 0 )) || return 1

    local cursor=0 i key
    local -a selected=()
    for (( i=0; i<count; i++ )); do
        selected[i]=0
    done

    while true; do
        printf '\033[H\033[2J' > /dev/tty
        printf "  SUP --interactive (fallback selector)\n" > /dev/tty
        printf "  Use ↑/↓ or j/k to move, space to toggle, enter to confirm, q to cancel.\n\n" > /dev/tty

        for (( i=0; i<count; i++ )); do
            local pointer=" "
            local box="[ ]"
            [[ $i -eq $cursor ]] && pointer=">"
            [[ ${selected[i]} -eq 1 ]] && box="[x]"
            printf "  %s %s %s\n" "$pointer" "$box" "${options[i]}" > /dev/tty
        done

        IFS= read -rsn1 key < /dev/tty || return 1
        case "$key" in
            $'\x1b')
                IFS= read -rsn2 key < /dev/tty || true
                case "$key" in
                    "[A") (( cursor=(cursor-1+count)%count )) ;;
                    "[B") (( cursor=(cursor+1)%count )) ;;
                esac
                ;;
            k) (( cursor=(cursor-1+count)%count )) ;;
            j) (( cursor=(cursor+1)%count )) ;;
            " ") selected[cursor]=$((1-selected[cursor])) ;;
            $'\n'|$'\r') break ;;
            q|Q) return 1 ;;
        esac
    done

    printf '\033[H\033[2J' > /dev/tty
    for (( i=0; i<count; i++ )); do
        (( selected[i] == 1 )) && printf '%s\n' "${options[i]}"
    done
}

interactive_select_tools() {
    _is_true "$FLAG_INTERACTIVE" || return 0
    (( ${#FOUND_TOOLS[@]} > 0 )) || return 0

    if [[ ! -t 0 || ! -t 1 ]]; then
        print_red "  --interactive requires an interactive terminal."
        return 1
    fi

    local -a options=()
    local -A selected_map=()
    local step line
    for step in "${FOUND_TOOLS[@]}"; do
        line="${STEP_LABEL[$step]} [$step]"
        options+=("$line")
    done

    local selected_output=""
    if _has gum; then
        selected_output="$(choose_with_gum "${options[@]}")" || return 1
    elif _has fzf; then
        selected_output="$(choose_with_fzf "${options[@]}")" || return 1
    else
        selected_output="$(choose_with_builtin "${options[@]}")" || return 1
    fi

    if [[ -z "$selected_output" ]]; then
        print_yellow "  No tools selected. Cancelling."
        return 1
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] && selected_map["$line"]=1
    done <<< "$selected_output"

    local -a new_found=()
    for step in "${FOUND_TOOLS[@]}"; do
        line="${STEP_LABEL[$step]} [$step]"
        [[ -n "${selected_map[$line]:-}" ]] && new_found+=("$step")
    done

    if (( ${#new_found[@]} == 0 )); then
        print_yellow "  No tools selected. Cancelling."
        return 1
    fi

    FOUND_TOOLS=("${new_found[@]}")
    print_cyan "  Interactive mode selected ${#FOUND_TOOLS[@]} tool(s)."
    printf '\n'
}

# ── Preferences ───────────────────────────────────────────
load_preferences() {
    [[ -f "$SUP_PREF_FILE" ]] || return 0
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(_trim "$line")"
        [[ -z "$line" || "$line" != *"="* ]] && continue
        key="$(_trim "${line%%=*}")"
        value="$(_trim "${line#*=}")"
        value="${value%\"}" ; value="${value#\"}"
        value="${value%\'}" ; value="${value#\'}"
        case "$key" in
            SUP_CLEANUP)          _is_true "$value" && SUP_CLEANUP=true || SUP_CLEANUP=false ;;
            SUP_BREW_GREEDY)      _is_true "$value" && SUP_BREW_GREEDY=true || SUP_BREW_GREEDY=false ;;
            SUP_AUTO_RETRY)       _is_true "$value" && SUP_AUTO_RETRY=true || SUP_AUTO_RETRY=false ;;
            SUP_ALLOW_REMOTE_INSTALLER_UPDATES) _is_true "$value" && SUP_ALLOW_REMOTE_INSTALLER_UPDATES=true || SUP_ALLOW_REMOTE_INSTALLER_UPDATES=false ;;
            SUP_SKIP)             SUP_SKIP_TOOLS="$value" ;; # backwards-compat preference key
            SUP_SKIP_TOOLS)       SUP_SKIP_TOOLS="$value" ;;
            *)
                print_yellow "  ⚠  Ignoring unknown preference key: $key"
                log_file "Ignored unknown preference key: $key"
                ;;
        esac
    done < "$SUP_PREF_FILE"
}

save_preferences() {
    if ! mkdir -p "$SUP_CONFIG_DIR"; then
        print_red "  ✗ Failed to create config directory: $SUP_CONFIG_DIR"
        return 1
    fi
    if ! cat > "$SUP_PREF_FILE" <<EOF
# sup preferences — generated by \`sup config\`
# Edit manually or re-run \`sup config\`
SUP_CLEANUP=$SUP_CLEANUP
SUP_BREW_GREEDY=$SUP_BREW_GREEDY
SUP_AUTO_RETRY=$SUP_AUTO_RETRY
SUP_ALLOW_REMOTE_INSTALLER_UPDATES=$SUP_ALLOW_REMOTE_INSTALLER_UPDATES
SUP_SKIP_TOOLS=$SUP_SKIP_TOOLS
EOF
    then
        print_red "  ✗ Failed to write preferences file: $SUP_PREF_FILE"
        return 1
    fi
    print_green "  ✓ Saved preferences to $SUP_PREF_FILE"
}

run_config_menu() {
    local choice input
    if [[ ! -t 0 ]]; then
        print_yellow "  Interactive config requires a TTY."
        return 1
    fi
    while true; do
        printf "\n  ${BOLD}SUP — Configuration${RESET}\n"
        printf "  ──────────────────────────────────────\n"
        printf "  1) Cleanup after updates        [%s]\n" "$SUP_CLEANUP"
        printf "  2) Homebrew --greedy casks      [%s]\n" "$SUP_BREW_GREEDY"
        printf "  3) Auto-retry failed updates    [%s]\n" "$SUP_AUTO_RETRY"
        printf "  4) Allow remote curl installers [%s]\n" "$SUP_ALLOW_REMOTE_INSTALLER_UPDATES"
        printf "  5) Skipped tools                [%s]\n" "${SUP_SKIP_TOOLS:-none}"
        printf "  6) Save and exit\n"
        printf "  7) Exit without saving\n"
        printf "  ──────────────────────────────────────\n"
        printf "  Choose [1-7]: "
        if ! read -r choice < /dev/tty; then
            printf "\n"
            return 1
        fi

        case "$choice" in
            1) _is_true "$SUP_CLEANUP" && SUP_CLEANUP=false || SUP_CLEANUP=true ;;
            2) _is_true "$SUP_BREW_GREEDY" && SUP_BREW_GREEDY=false || SUP_BREW_GREEDY=true ;;
            3) _is_true "$SUP_AUTO_RETRY" && SUP_AUTO_RETRY=false || SUP_AUTO_RETRY=true ;;
            4) _is_true "$SUP_ALLOW_REMOTE_INSTALLER_UPDATES" && SUP_ALLOW_REMOTE_INSTALLER_UPDATES=false || SUP_ALLOW_REMOTE_INSTALLER_UPDATES=true ;;
            5)
                local previous_skip="$SUP_SKIP_TOOLS"
                printf "  Enter comma-separated tool IDs (replaces current; empty to clear): "
                if ! read -r input < /dev/tty; then
                    printf "\n"
                    print_yellow "  Input cancelled."
                    continue
                fi

                input="${input// /}"
                if [[ -z "$input" ]]; then
                    SUP_SKIP_TOOLS=""
                    continue
                fi

                local item step_id joined
                local -a requested valid invalid
                local -A seen_valid=() seen_invalid=()
                IFS=',' read -r -a requested <<< "$input"

                for item in "${requested[@]}"; do
                    item="$(_trim "$item")"
                    [[ -z "$item" ]] && continue

                    local found=1
                    for step_id in "${STEP_ORDER[@]}"; do
                        if [[ "$step_id" == "$item" ]]; then
                            found=0
                            break
                        fi
                    done

                    if (( found == 0 )); then
                        if [[ -z "${seen_valid[$item]:-}" ]]; then
                            seen_valid[$item]=1
                            valid+=("$item")
                        fi
                    else
                        if [[ -z "${seen_invalid[$item]:-}" ]]; then
                            seen_invalid[$item]=1
                            invalid+=("$item")
                        fi
                    fi
                done

                if (( ${#invalid[@]} > 0 )); then
                    joined=""
                    for item in "${invalid[@]}"; do
                        [[ -n "$joined" ]] && joined+=", "
                        joined+="$item"
                    done
                    print_yellow "  Ignoring unknown tool IDs: $joined"
                fi

                if (( ${#valid[@]} == 0 )); then
                    SUP_SKIP_TOOLS="$previous_skip"
                    print_yellow "  No valid tool IDs entered. Keeping existing skip list."
                    print_yellow "  Run: sup --list to see valid tool IDs."
                else
                    SUP_SKIP_TOOLS="$(IFS=,; printf '%s' "${valid[*]}")"
                fi
                ;;
            6) save_preferences; return $? ;;
            7) printf "  No changes saved.\n"; return 0 ;;
            *) print_yellow "  Invalid choice." ;;
        esac
    done
}

# ── Step registration ─────────────────────────────────────
add_step() {
    local step="$1" label="$2" os="$3" sudo_req="$4" risk="$5" timeout="$6"
    STEP_ORDER+=("$step")
    STEP_LABEL["$step"]="$label"
    STEP_OS["$step"]="$os"
    STEP_SUDO["$step"]="$sudo_req"
    STEP_RISK["$step"]="$risk"
    STEP_TIMEOUT["$step"]="$timeout"
}

register_all_steps() {
    # Tier 1: System package managers
    add_step homebrew       "Homebrew"            "darwin,linux" "no"  "safe" 300
    add_step homebrew_cask  "Homebrew Casks"      "darwin"       "no"  "safe" 300
    add_step apt            "apt"                 "linux"        "yes" "safe" 300
    add_step snap           "Snap"                "linux"        "yes" "safe" 300
    add_step flatpak        "Flatpak"             "linux"        "no"  "safe" 300
    add_step mas            "Mac App Store"       "darwin"       "no"  "safe" 120
    add_step macos_system   "macOS System"        "darwin"       "no"  "safe" 30

    # Tier 2: Language runtimes & version managers
    add_step rustup         "Rustup"              "all" "no" "safe" 120
    add_step uv             "uv"                  "all" "no" "safe" 60
    add_step pipx           "pipx"                "all" "no" "safe" 120
    add_step conda          "Conda"               "all" "no" "safe" 120
    add_step mamba          "Mamba"               "all" "no" "safe" 120
    add_step pyenv          "pyenv"               "darwin,linux" "no" "safe" 60
    add_step asdf           "asdf"                "darwin,linux" "no" "safe" 120
    add_step mise           "mise"                "darwin,linux" "no" "safe" 120

    # Tier 3: Node.js ecosystem
    add_step npm            "npm Globals"         "all" "no" "safe" 120
    add_step pnpm           "pnpm"                "all" "no" "safe" 120
    add_step bun            "Bun"                 "all" "no" "safe" 60
    add_step deno           "Deno"                "all" "no" "safe" 60

    # Tier 4: AI-native tools
    add_step claude         "Claude Code"         "all" "no" "safe" 120
    add_step gemini         "Gemini CLI"          "all" "no" "safe" 60
    add_step ollama         "Ollama"              "all" "no" "safe" 120
    add_step goose          "Goose"               "all" "no" "safe" 120
    add_step amazon_q       "Amazon Q CLI"        "all" "no" "safe" 60
    add_step aider          "Aider"               "all" "no" "safe" 120
    add_step open_interpreter "Open Interpreter"  "all" "no" "safe" 60
    add_step huggingface    "HuggingFace CLI"     "all" "no" "safe" 60
    add_step copilot        "GitHub Copilot"      "all" "no" "safe" 60
    add_step codex          "Codex CLI"           "all" "no" "safe" 60

    # Tier 5: Developer CLIs
    add_step gh_extensions  "GitHub Extensions"   "all" "no" "safe" 60
    add_step vercel         "Vercel CLI"          "all" "no" "safe" 60
    add_step firebase       "Firebase CLI"        "all" "no" "safe" 60
    add_step supabase       "Supabase CLI"        "all" "no" "safe" 60
    add_step railway        "Railway CLI"         "all" "no" "safe" 60
    add_step flyctl         "Fly.io CLI"          "all" "no" "safe" 60
    add_step wrangler       "Wrangler"            "all" "no" "safe" 60
    add_step gcloud         "gcloud"              "all" "no" "safe" 120
    add_step terraform      "Terraform"           "all" "no" "safe" 60

    # Tier 6: Editors & extensions
    add_step vscode         "VS Code Extensions"  "all" "no" "safe" 60
    add_step vscode_insiders "VS Code Insiders"   "all" "no" "safe" 60
    add_step vscodium       "VSCodium Extensions" "all" "no" "safe" 60

    # Tier 7: Shell frameworks & plugins
    add_step ohmyzsh        "oh-my-zsh"           "darwin,linux" "no" "safe" 30
    add_step ohmybash       "oh-my-bash"          "darwin,linux" "no" "safe" 30
    add_step fisher         "fisher"              "darwin,linux" "no" "safe" 30
    add_step tmux_plugins   "tmux plugins"        "darwin,linux" "no" "safe" 30

    # Tier 8: Other language tools
    add_step gem            "RubyGems (system)"   "all" "no" "warn" 60
    add_step composer       "Composer"            "all" "no" "safe" 60
    add_step cargo_crates   "Cargo crates"        "all" "no" "safe" 120
    add_step go_binaries    "Go binaries (gup)"   "all" "no" "safe" 120

    # Package-name maps for install-method detection
    BREW_PKG_MAP=(
        [claude]="claude-code"  [gemini]="gemini-cli"  [goose]="block-goose-cli"
        [codex]="codex"         [vercel]="vercel-cli"  [firebase]="firebase-cli"
        [wrangler]="wrangler"   [terraform]="terraform"
    )
    NPM_PKG_MAP=(
        [gemini]="@google/gemini-cli"  [codex]="@openai/codex"
        [vercel]="vercel"              [firebase]="firebase-tools"
        [supabase]="supabase"          [wrangler]="wrangler"
    )
    PIPX_PKG_MAP=(
        [aider]="aider-chat"  [open_interpreter]="open-interpreter"
        [huggingface]="huggingface-hub"
    )
    UV_TOOL_MAP=(
        [aider]="aider-chat"  [open_interpreter]="open-interpreter"
        [huggingface]="huggingface-hub"
    )
}

# ── Install-source caching ────────────────────────────────
cache_install_sources() {
    BREW_LIST="" ; BREW_CASK_LIST="" ; BREW_FULL_LIST=""
    NPM_GLOBAL_LIST="" ; PIPX_LIST="" ; UV_TOOL_LIST=""

    if _has brew; then
        BREW_LIST="$(brew list --formula 2>/dev/null || true)"
        BREW_CASK_LIST="$(brew list --cask 2>/dev/null || true)"
        BREW_FULL_LIST="$(brew list --formula --full-name 2>/dev/null || true)"
    fi
    _has npm  && NPM_GLOBAL_LIST="$(npm list -g --depth=0 2>/dev/null || true)"
    _has pipx && PIPX_LIST="$(pipx list --short 2>/dev/null || true)"
    _has uv   && UV_TOOL_LIST="$(uv tool list 2>/dev/null || true)"
}

detect_install_method() {
    local tool="$1"
    local brew_name="${BREW_PKG_MAP[$tool]:-$tool}"
    local npm_name="${NPM_PKG_MAP[$tool]:-$tool}"
    local pipx_name="${PIPX_PKG_MAP[$tool]:-$tool}"
    local uv_name="${UV_TOOL_MAP[$tool]:-$tool}"

    if [[ "$tool" == "terraform" ]]; then
        if _list_has "$BREW_FULL_LIST" "hashicorp/tap/terraform" || _list_has "$BREW_LIST" "terraform"; then
            printf 'brew'; return
        fi
        printf 'native'; return
    fi

    if _list_has "$BREW_LIST" "$brew_name" || _list_has "$BREW_FULL_LIST" "$brew_name"; then
        printf 'brew'
    elif printf '%s\n' "$NPM_GLOBAL_LIST" | grep -qF "$npm_name" 2>/dev/null; then
        printf 'npm'
    elif printf '%s\n' "$PIPX_LIST" | grep -qF "$pipx_name" 2>/dev/null; then
        printf 'pipx'
    elif printf '%s\n' "$UV_TOOL_LIST" | grep -qF "$uv_name" 2>/dev/null; then
        printf 'uv'
    else
        printf 'native'
    fi
}

# ── uv auto-install ──────────────────────────────────────
ensure_uv() {
    _has uv && return 0
    _is_true "$FLAG_DRY_RUN" && return 0
    _is_true "$FLAG_LIST" && return 0

    log_file "uv not found — attempting auto-install from https://astral.sh/uv/install.sh"
    print_cyan "  Installing uv (fast Python package manager)..."
    if curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh 2>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        print_green "  ✓ uv installed"
        log_file "uv auto-install succeeded"
    else
        print_yellow "  ⚠ uv install failed — Python tools will use pipx/native fallbacks."
        log_file "uv auto-install failed"
    fi
}

# ══════════════════════════════════════════════════════════
# TOOL CHECK / UPDATE FUNCTIONS
# ══════════════════════════════════════════════════════════

# ── Tier 1: System package managers ──────────────────────
check_homebrew() { _has brew; }
update_homebrew() {
    brew update && brew upgrade || return 1
    if _is_true "$SUP_CLEANUP"; then
        brew cleanup --prune=7 2>/dev/null || true
        brew autoremove 2>/dev/null || true
    fi
}

check_homebrew_cask() { [[ "$CURRENT_OS" == "darwin" ]] && _has brew; }
update_homebrew_cask() {
    if _is_true "$SUP_BREW_GREEDY"; then
        brew upgrade --cask --greedy
    else
        brew upgrade --cask
    fi
}

check_apt() { [[ "$CURRENT_OS" == "linux" ]] && _has apt-get; }
update_apt() {
    DEBIAN_FRONTEND=noninteractive maybe_sudo apt-get update -qq \
        && DEBIAN_FRONTEND=noninteractive maybe_sudo apt-get upgrade -y -o Dpkg::Options::="--force-confold" \
        || return 1
    if _is_true "$SUP_CLEANUP"; then
        DEBIAN_FRONTEND=noninteractive maybe_sudo apt-get autoremove -y 2>/dev/null || true
    fi
}

check_snap() { [[ "$CURRENT_OS" == "linux" ]] && _has snap; }
update_snap() { maybe_sudo snap refresh; }

check_flatpak() { [[ "$CURRENT_OS" == "linux" ]] && _has flatpak; }
update_flatpak() { flatpak update -y --noninteractive 2>/dev/null || flatpak update -y; }

check_mas() { [[ "$CURRENT_OS" == "darwin" ]] && _has mas; }
update_mas() { mas upgrade; }

check_macos_system() {
    [[ "$CURRENT_OS" == "darwin" ]] || return 1
    _has softwareupdate || return 1
    local output
    output="$(LANG=C softwareupdate -l 2>&1)" || return 1

    # "No new software..." means there is nothing to do.
    printf '%s\n' "$output" | grep -q "No new software" && return 1

    # Real updates are listed as starred entries.
    printf '%s\n' "$output" | grep -qE '^[[:space:]]*\*'
}
update_macos_system() {
    print_cyan "  Available macOS updates:"
    LANG=C softwareupdate -l 2>/dev/null || true
    printf "  Run: sudo softwareupdate -i -a\n"
}

# ── Tier 2: Language runtimes & version managers ─────────
check_rustup()  { _has rustup; }
update_rustup() { rustup update; }

check_uv()  { _has uv; }
update_uv() { uv self update; }

check_pipx()  { _has pipx; }
update_pipx() { pipx upgrade-all; }

check_conda()  { _has conda; }
update_conda() { conda update conda -y; }

check_mamba()  { _has mamba; }
update_mamba() { mamba update mamba -y; }

check_pyenv() {
    _has pyenv || return 1
    pyenv commands 2>/dev/null | grep -q '^update$'
}
update_pyenv() { pyenv update; }

check_asdf()  { _has asdf; }
update_asdf() { asdf plugin update --all; }

check_mise()  { _has mise; }
update_mise() {
    mise self-update -y 2>/dev/null || mise self-update 2>/dev/null || true
    mise upgrade
}

# ── Tier 3: Node.js ecosystem ────────────────────────────
check_npm()  { _has npm; }
update_npm() { npm update -g --no-fund --no-audit; }

check_pnpm()  { _has pnpm; }
update_pnpm() {
    pnpm self-update 2>/dev/null || true
    pnpm update -g
}

check_bun()  { _has bun; }
update_bun() { bun upgrade --stable 2>/dev/null || bun upgrade; }

check_deno()  { _has deno; }
update_deno() { deno upgrade --quiet; }

# ── Tier 4: AI-native tools ──────────────────────────────
check_claude()  { _has claude; }
update_claude() {
    case "$(detect_install_method claude)" in
        brew) brew upgrade claude-code ;;
        *)    claude update ;;
    esac
}

check_gemini()  { _has gemini; }
update_gemini() {
    case "$(detect_install_method gemini)" in
        brew) brew upgrade gemini-cli ;;
        npm)  npm install -g @google/gemini-cli@latest --no-fund --no-audit ;;
        *)    return 0 ;;
    esac
}

check_ollama()  { _has ollama; }
update_ollama() {
    case "$(detect_install_method ollama)" in
        brew) brew upgrade ollama ;;
        native)
            [[ "$CURRENT_OS" == "darwin" ]] && return 0
            _is_true "$SUP_ALLOW_REMOTE_INSTALLER_UPDATES" || return 0
            curl -fsSL https://ollama.com/install.sh | sh
            ;;
        *) return 0 ;;
    esac
}

check_goose()  { _has goose; }
update_goose() {
    if _list_has "$BREW_LIST" "block-goose-cli"; then
        brew upgrade block-goose-cli
    elif _list_has "$BREW_CASK_LIST" "block-goose"; then
        brew upgrade --cask block-goose
    else
        _is_true "$SUP_ALLOW_REMOTE_INSTALLER_UPDATES" || return 0
        curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh \
            | CONFIGURE=false bash
    fi
}

check_amazon_q() { _has q && q --version 2>&1 | grep -q "Amazon Q"; }
update_amazon_q() { q update --non-interactive; }

check_aider()  { _has aider; }
update_aider() {
    case "$(detect_install_method aider)" in
        uv)   uv tool install --force "aider-chat@latest" ;;
        pipx) pipx upgrade aider-chat ;;
        brew) brew upgrade aider ;;
        *)    return 0 ;;
    esac
}

check_open_interpreter() { _has interpreter; }
update_open_interpreter() {
    case "$(detect_install_method open_interpreter)" in
        uv)   uv tool install --force "open-interpreter@latest" ;;
        pipx) pipx upgrade open-interpreter ;;
        *)    return 0 ;;
    esac
}

check_huggingface() { _has huggingface-cli; }
update_huggingface() {
    case "$(detect_install_method huggingface)" in
        uv)   uv tool install --force "huggingface_hub[cli]@latest" ;;
        pipx) pipx upgrade huggingface-hub ;;
        *)    return 0 ;;
    esac
}

check_copilot() { _has gh && gh extension list 2>/dev/null | grep -q copilot; }
update_copilot() { gh extension upgrade gh-copilot; }

check_codex()  { _has codex; }
update_codex() {
    case "$(detect_install_method codex)" in
        brew) brew upgrade codex ;;
        npm)  npm install -g @openai/codex@latest --no-fund --no-audit ;;
        *)    return 0 ;;
    esac
}

# ── Tier 5: Developer CLIs ───────────────────────────────
check_gh_extensions() { _has gh && gh extension list 2>/dev/null | grep -q .; }
update_gh_extensions() { gh extension upgrade --all; }

check_vercel()  { _has vercel; }
update_vercel() {
    case "$(detect_install_method vercel)" in
        brew) brew upgrade vercel-cli ;;
        npm)  npm install -g vercel@latest --no-fund --no-audit ;;
        *)    return 0 ;;
    esac
}

check_firebase()  { _has firebase; }
update_firebase() {
    case "$(detect_install_method firebase)" in
        brew) brew upgrade firebase-cli ;;
        npm)  npm install -g firebase-tools@latest --no-fund --no-audit ;;
        *)    return 0 ;;
    esac
}

check_supabase()  { _has supabase; }
update_supabase() {
    case "$(detect_install_method supabase)" in
        brew) brew upgrade supabase ;;
        npm)  npm install -g supabase@latest --no-fund --no-audit ;;
        *)    return 0 ;;
    esac
}

check_railway()  { _has railway; }
update_railway() {
    case "$(detect_install_method railway)" in
        brew) brew upgrade railway ;;
        *)    railway upgrade ;;
    esac
}

check_flyctl()  { _has flyctl; }
update_flyctl() { flyctl version upgrade; }

check_wrangler()  { _has wrangler; }
update_wrangler() {
    case "$(detect_install_method wrangler)" in
        npm)  npm install -g wrangler@latest --no-fund --no-audit ;;
        *)    return 0 ;;
    esac
}

check_gcloud()  { _has gcloud; }
update_gcloud() { gcloud components update --quiet; }

check_terraform() {
    _has terraform || return 1
    _has tfenv && return 1
    local method; method="$(detect_install_method terraform)"
    [[ "$method" == "brew" ]]
}
update_terraform() {
    if _list_has "$BREW_FULL_LIST" "hashicorp/tap/terraform"; then
        brew upgrade hashicorp/tap/terraform
    elif _list_has "$BREW_LIST" "terraform"; then
        brew upgrade terraform
    fi
}

# ── Tier 6: Editors & extensions ─────────────────────────
check_vscode()          { _has code; }
update_vscode()         { code --update-extensions; }

check_vscode_insiders() { _has code-insiders; }
update_vscode_insiders(){ code-insiders --update-extensions; }

check_vscodium()        { _has codium; }
update_vscodium()       { codium --update-extensions; }

# ── Tier 7: Shell frameworks & plugins ───────────────────
check_ohmyzsh()  { [[ -x "$HOME/.oh-my-zsh/tools/upgrade.sh" ]]; }
update_ohmyzsh() {
    local d="$HOME/.oh-my-zsh"
    DISABLE_UPDATE_PROMPT=true ZSH="$d" "$d/tools/upgrade.sh"
}

check_ohmybash()  { [[ -d "$HOME/.oh-my-bash" ]]; }
update_ohmybash() {
    local d="$HOME/.oh-my-bash"
    if [[ -x "$d/tools/upgrade.sh" ]]; then
        bash "$d/tools/upgrade.sh"
    else
        git -C "$d" pull --rebase --stat origin master
    fi
}

check_fisher() { _has fish && fish -c 'functions -q fisher' 2>/dev/null; }
update_fisher() { fish -c 'fisher update'; }

check_tmux_plugins() { [[ -x "$HOME/.tmux/plugins/tpm/bin/update_plugins" ]]; }
update_tmux_plugins() { "$HOME/.tmux/plugins/tpm/bin/update_plugins" all; }

# ── Tier 8: Other language tools ─────────────────────────
check_gem()          { _has gem; }
update_gem()         { gem update --system --no-document; }

check_composer()     { _has composer; }
update_composer()    { composer self-update --no-interaction; }

check_cargo_crates() { _has cargo-install-update; }
update_cargo_crates() { cargo install-update -a; }

check_go_binaries()  { _has gup; }
update_go_binaries() { gup update; }

# ══════════════════════════════════════════════════════════
# RUNNER ENGINE
# ══════════════════════════════════════════════════════════

os_matches() {
    local spec="${1:-all}"
    [[ "$spec" == "all" ]] && return 0
    local token
    local -a tokens
    IFS=',' read -r -a tokens <<< "$spec"
    for token in "${tokens[@]}"; do
        [[ "$CURRENT_OS" == "$(_trim "$token")" ]] && return 0
    done
    return 1
}

is_skipped() {
    local step="$1"
    if (( ${#CLI_ONLY[@]} > 0 )) && [[ -z "${CLI_ONLY[$step]:-}" ]]; then
        return 0
    fi
    [[ -n "${CLI_SKIP[$step]:-}" ]] && return 0
    local item
    local -a items
    IFS=',' read -r -a items <<< "${SUP_SKIP_TOOLS:-}"
    for item in "${items[@]}"; do
        [[ "$step" == "$(_trim "$item")" ]] && return 0
    done
    return 1
}

detect_tools() {
    cache_install_sources

    local step
    for step in "${STEP_ORDER[@]}"; do
        os_matches "${STEP_OS[$step]}" || continue
        is_skipped "$step" && continue
        if "check_${step}" 2>/dev/null; then
            FOUND_TOOLS+=("$step")
        fi
    done
}

show_found_tools() {
    local count=${#FOUND_TOOLS[@]}
    if (( count == 0 )); then
        if (( ${#CLI_ONLY[@]} > 0 )); then
            print_yellow "  No tools matched your --only filter."
            print_yellow "  Run: sup --list  (to see valid tool IDs)"
        else
            print_green "  Everything is already up-to-date (or nothing detected)."
        fi
        return 1
    fi

    local needs_sudo=0 step
    local -a sudo_labels=()
    for step in "${FOUND_TOOLS[@]}"; do
        if [[ "${STEP_SUDO[$step]}" == "yes" ]]; then
            (( needs_sudo++ ))
            sudo_labels+=("${STEP_LABEL[$step]}")
        fi
    done

    printf "  Found ${BOLD}%d${RESET} updatable tools:\n" "$count"
    printf "  ─────────────────────────────────────────\n"
    local i=1
    for step in "${FOUND_TOOLS[@]}"; do
        printf "   %2d. %-24s ${DIM}[%s]${RESET}\n" "$i" "${STEP_LABEL[$step]}" "$step"
        (( i++ ))
    done
    printf "  ─────────────────────────────────────────\n"
    if (( needs_sudo > 0 )); then
        local sudo_list="" label
        for label in "${sudo_labels[@]}"; do
            [[ -n "$sudo_list" ]] && sudo_list+=", "
            sudo_list+="$label"
        done
        printf "  ${YELLOW}⚠${RESET}  %d tool(s) need elevated permissions: %s\n" "$needs_sudo" "$sudo_list"
    fi
    printf '\n'
    return 0
}

confirm_or_exit() {
    if _is_true "$FLAG_YES"; then return 0; fi
    if [[ ! -t 0 ]]; then
        print_yellow "  No interactive input detected. Re-run with --yes for non-interactive mode."
        return 1
    fi
    printf "  Press ${BOLD}ENTER${RESET} to update all, or ${BOLD}Ctrl+C${RESET} to cancel."
    if ! read -r < /dev/tty; then
        printf "\n"
        print_yellow "  No interactive input detected. Re-run with --yes for non-interactive mode."
        return 1
    fi
    return 0
}

_step_cmd_hint() {
    case "$1" in
        homebrew)         printf 'brew update && brew upgrade' ;;
        homebrew_cask)    printf 'brew upgrade --cask' ;;
        apt)              printf 'sudo apt-get update && apt-get upgrade -y' ;;
        snap)             printf 'sudo snap refresh' ;;
        flatpak)          printf 'flatpak update -y' ;;
        mas)              printf 'mas upgrade' ;;
        macos_system)     printf 'softwareupdate -l (check-only)' ;;
        rustup)           printf 'rustup update' ;;
        uv)               printf 'uv self update' ;;
        pipx)             printf 'pipx upgrade-all' ;;
        conda)            printf 'conda update conda -y' ;;
        mamba)            printf 'mamba update mamba -y' ;;
        pyenv)            printf 'pyenv update' ;;
        asdf)             printf 'asdf plugin update --all' ;;
        mise)             printf 'mise self-update && mise upgrade' ;;
        npm)              printf 'npm update -g' ;;
        pnpm)             printf 'pnpm self-update && pnpm update -g' ;;
        bun)              printf 'bun upgrade' ;;
        deno)             printf 'deno upgrade' ;;
        claude)           printf 'brew upgrade claude-code / claude update' ;;
        gemini)           printf 'brew/npm upgrade gemini-cli' ;;
        ollama)           printf 'brew upgrade ollama' ;;
        goose)            printf 'brew upgrade block-goose-cli' ;;
        amazon_q)         printf 'q update --non-interactive' ;;
        aider)            printf 'uv tool install aider-chat@latest' ;;
        open_interpreter) printf 'uv/pipx upgrade open-interpreter' ;;
        huggingface)      printf 'uv/pipx upgrade huggingface-hub' ;;
        copilot)          printf 'gh extension upgrade gh-copilot' ;;
        codex)            printf 'brew/npm upgrade codex' ;;
        gh_extensions)    printf 'gh extension upgrade --all' ;;
        vercel)           printf 'brew/npm upgrade vercel' ;;
        firebase)         printf 'brew/npm upgrade firebase-tools' ;;
        supabase)         printf 'brew/npm upgrade supabase' ;;
        railway)          printf 'brew upgrade railway / railway upgrade' ;;
        flyctl)           printf 'flyctl version upgrade' ;;
        wrangler)         printf 'npm install -g wrangler@latest' ;;
        gcloud)           printf 'gcloud components update --quiet' ;;
        terraform)        printf 'brew upgrade terraform' ;;
        vscode)           printf 'code --update-extensions' ;;
        vscode_insiders)  printf 'code-insiders --update-extensions' ;;
        vscodium)         printf 'codium --update-extensions' ;;
        ohmyzsh)          printf 'omz update' ;;
        ohmybash)         printf 'upgrade_oh_my_bash' ;;
        fisher)           printf 'fisher update' ;;
        tmux_plugins)     printf '$HOME/.tmux/plugins/tpm/bin/update_plugins all' ;;
        gem)              printf 'gem update --system' ;;
        composer)         printf 'composer self-update' ;;
        cargo_crates)     printf 'cargo install-update -a' ;;
        go_binaries)      printf 'gup update' ;;
        *)                printf 'update_%s' "$1" ;;
    esac
}

_step_version() {
    local v=""
    case "$1" in
        homebrew|homebrew_cask)
            v="$(brew --version 2>/dev/null | head -1)" ; v="${v#Homebrew }" ;;
        rustup)
            v="$(rustup --version 2>/dev/null)" ; v="${v#rustup }" ; v="${v%% *}" ;;
        uv)
            v="$(uv --version 2>/dev/null)" ; v="${v#uv }" ;;
        pipx)
            v="$(pipx --version 2>/dev/null)" ;;
        npm)
            v="$(npm --version 2>/dev/null)" ;;
        pnpm)
            v="$(pnpm --version 2>/dev/null)" ;;
        bun)
            v="$(bun --version 2>/dev/null)" ;;
        deno)
            v="$(deno --version 2>/dev/null | head -1)" ; v="${v#deno }" ;;
        gemini)
            v="$(gemini --version 2>/dev/null | head -1)" ; v="${v##* }" ;;
        codex)
            v="$(codex --version 2>/dev/null | head -1)" ; v="${v##* }" ;;
        mise)
            v="$(mise --version 2>/dev/null | head -1)" ; v="${v#mise }" ;;
        vercel)
            v="$(vercel --version 2>/dev/null | head -1)"
            v="${v#Vercel CLI }" ; v="${v#vercel }" ;;
        firebase)
            v="$(firebase --version 2>/dev/null | head -1)" ;;
        supabase)
            v="$(supabase --version 2>/dev/null | head -1)" ; v="${v##* }" ;;
        railway)
            v="$(railway --version 2>/dev/null | head -1)" ; v="${v#railway }" ;;
        flyctl)
            v="$(flyctl version 2>/dev/null | head -1)"
            v="${v#flyctl v}" ; v="${v#v}" ;;
        wrangler)
            v="$(wrangler --version 2>/dev/null | head -1)" ; v="${v#wrangler }" ;;
        terraform)
            v="$(terraform version 2>/dev/null | head -1)"
            v="${v#Terraform v}" ; v="${v#v}" ;;
        composer)
            v="$(composer --version 2>/dev/null | head -1)" ; v="${v##* }" ;;
        claude)
            v="$(claude --version 2>/dev/null | head -1)" ; v="${v##* }" ;;
        ollama)
            v="$(ollama --version 2>/dev/null)" ; v="${v##* }" ;;
        gcloud)
            v="$(gcloud --version 2>/dev/null | head -1)" ; v="${v#Google Cloud SDK }" ;;
        *)
            return 1 ;;
    esac
    [[ -n "$v" ]] && printf '%s' "$v" || return 1
}

run_dry_run() {
    printf "\n  ${BOLD}SUP — Dry Run${RESET}\n"
    printf "  ─────────────────────────────────────────\n\n"
    printf "  Would update:\n"
    local i=1 step cmd_hint
    for step in "${FOUND_TOOLS[@]}"; do
        cmd_hint="$(_step_cmd_hint "$step")"
        printf "    %2d. %-22s ${DIM}%s${RESET}\n" "$i" "${STEP_LABEL[$step]}" "$cmd_hint"
        (( i++ ))
    done

    local needs_sudo=0
    for step in "${FOUND_TOOLS[@]}"; do
        [[ "${STEP_SUDO[$step]}" == "yes" ]] && (( needs_sudo++ ))
    done

    printf "\n  %d tools would be updated. %d require sudo.\n" "${#FOUND_TOOLS[@]}" "$needs_sudo"
    printf "  No changes were made.\n\n"
}

run_list() {
    printf "\n  ${BOLD}SUP — Supported Tools${RESET}\n"
    printf "  ─────────────────────────────────────────\n\n"

    local installed=() not_found=() step ver
    local supported_count=0
    for step in "${STEP_ORDER[@]}"; do
        if ! os_matches "${STEP_OS[$step]}"; then
            not_found+=("$step|${STEP_LABEL[$step]}|(${STEP_OS[$step]} only)")
            continue
        fi
        (( supported_count++ ))
        if "check_${step}" 2>/dev/null; then
            ver=""
            ver="$(_step_version "$step" 2>/dev/null)" || ver=""
            if [[ -n "$ver" ]]; then
                installed+=("$step|${STEP_LABEL[$step]}|$ver")
            else
                installed+=("$step|${STEP_LABEL[$step]}|")
            fi
        else
            not_found+=("$step|${STEP_LABEL[$step]}|")
        fi
    done

    local entry label ver_str id os_hint
    if (( ${#installed[@]} > 0 )); then
        printf "  INSTALLED:\n"
        for entry in "${installed[@]}"; do
            id="${entry%%|*}"
            label="${entry#*|}" ; label="${label%%|*}"
            ver_str="${entry##*|}"
            if [[ -n "$ver_str" ]]; then
                printf "    ${GREEN}✓${RESET}  %-22s ${DIM}[%s] %s${RESET}\n" "$label" "$id" "$ver_str"
            else
                printf "    ${GREEN}✓${RESET}  %-22s ${DIM}[%s]${RESET}\n" "$label" "$id"
            fi
        done
        printf '\n'
    fi

    if (( ${#not_found[@]} > 0 )); then
        printf "  NOT FOUND:\n"
        for entry in "${not_found[@]}"; do
            id="${entry%%|*}"
            label="${entry#*|}" ; label="${label%%|*}"
            os_hint="${entry##*|}"
            if [[ -n "$os_hint" ]]; then
                printf "    ${DIM}·${RESET}  %-22s ${DIM}[%s] %s${RESET}\n" "$label" "$id" "$os_hint"
            else
                printf "    ${DIM}·${RESET}  %-22s ${DIM}[%s]${RESET}\n" "$label" "$id"
            fi
        done
        printf '\n'
    fi

    printf "  Total: %d installed, %d supported on %s\n\n" "${#installed[@]}" "$supported_count" "$CURRENT_OS"
}

run_all_updates() {
    local step label timeout risk needs_sudo
    local start_time stderr_file update_pid rc elapsed reason_file
    for step in "${FOUND_TOOLS[@]}"; do
        label="${STEP_LABEL[$step]}"
        timeout="${STEP_TIMEOUT[$step]:-120}"
        risk="${STEP_RISK[$step]:-safe}"
        needs_sudo="${STEP_SUDO[$step]:-no}"

        if [[ "$risk" == "warn" ]]; then
            if ! warn_and_confirm "$label"; then
                RESULTS[$step]="SKIP"
                (( TOTAL_SKIP++ ))
                show_spinner_skip "$label"
                continue
            fi
        fi

        if [[ "$needs_sudo" == "yes" ]]; then
            if ! ensure_sudo "$label"; then
                RESULTS[$step]="SKIP"
                (( TOTAL_SKIP++ ))
                show_spinner_skip "$label"
                continue
            fi
        fi

        start_time=$(date +%s)
        stderr_file="$(mktemp "${TMPDIR:-/tmp}/sup_${step}_XXXXXX")"
        TEMP_FILES+=("$stderr_file")

        if _is_true "$FLAG_VERBOSE"; then
            printf "  ${DIM}→ update_%s${RESET}\n" "$step"
        fi

        log_file "START $step"

        run_with_retry "$step" "$timeout" "$stderr_file" &
        update_pid=$!

        spin_while "$update_pid" "$label"
        wait "$update_pid"
        rc=$?

        elapsed=$(( $(date +%s) - start_time ))
        # shellcheck disable=SC2034
        TIMINGS[$step]="$elapsed"

        if (( rc == 0 )); then
            RESULTS[$step]="OK"
            (( TOTAL_OK++ ))
            show_spinner_ok "$label" "$elapsed"
            log_file "OK $step (${elapsed}s)"
        else
            RESULTS[$step]="FAIL"
            (( TOTAL_FAIL++ ))
            reason_file="${stderr_file}.reason"
            if [[ -f "$reason_file" ]]; then
                ERRORS[$step]="$(<"$reason_file")"
                rm -f "$reason_file"
            else
                ERRORS[$step]="Unknown error (exit code $rc)."
            fi
            show_spinner_fail "$label" "$elapsed"
            log_file "FAIL $step rc=$rc: ${ERRORS[$step]} (${elapsed}s)"
        fi

        rm -f "$stderr_file"
    done
}

print_summary() {
    local total_time=0 mins=0 secs=0
    if (( RUN_START > 0 )); then
        total_time=$(( $(date +%s) - RUN_START ))
        mins=$(( total_time / 60 ))
        secs=$(( total_time % 60 ))
    fi

    printf '\n  ═══════════════════════════════════════════\n'
    printf "  ${BOLD}SUP SUMMARY${RESET}\n"
    printf '  ═══════════════════════════════════════════\n\n'
    printf "  ${GREEN}✓${RESET}  %d updated successfully\n" "$TOTAL_OK"
    (( TOTAL_FAIL > 0 )) && printf "  ${RED}✗${RESET}  %d failed\n" "$TOTAL_FAIL"
    (( TOTAL_SKIP > 0 )) && printf "  ${DIM}·${RESET}  %d skipped\n" "$TOTAL_SKIP"

    if (( TOTAL_FAIL > 0 )); then
        printf '\n  FAILURES:\n'
        printf '  ──────────────────────────────────────────\n'
        local step hint
        for step in "${FOUND_TOOLS[@]}"; do
            [[ "${RESULTS[$step]:-}" == "FAIL" ]] || continue
            printf "  %-20s %s\n" "${STEP_LABEL[$step]}" "${ERRORS[$step]:-Unknown error.}"
            hint="$(_step_cmd_hint "$step")"
            printf "  %-20s ${DIM}Try: %s${RESET}\n" "" "$hint"
        done
        printf '  ──────────────────────────────────────────\n'
    fi

    if (( RUN_START <= 0 )); then
        printf "\n  Done. Stay fresh. 🤙\n\n"
    elif (( mins > 0 )); then
        printf "\n  Done in %dm %ds. Stay fresh. 🤙\n\n" "$mins" "$secs"
    else
        printf "\n  Done in %ds. Stay fresh. 🤙\n\n" "$secs"
    fi
}

# ── Self-update ───────────────────────────────────────────
check_self_update() {
    [[ -n "${SUP_NO_SELF_UPDATE:-}" ]] && return 0
    local remote
    remote="$(curl -fsSL --max-time 3 \
        "https://raw.githubusercontent.com/${SUP_REPO}/main/VERSION" 2>/dev/null | tr -d '[:space:]')"

    if [[ -n "$remote" ]] && version_gt "$remote" "$SUP_VERSION"; then
        print_yellow "  ℹ  New version available: $remote → run \`sup --self-update\`"
    fi
}

self_update() {
    local install_path
    install_path="$(command -v sup 2>/dev/null || printf '%s' "$0")"

    if _has brew && brew list sup &>/dev/null; then
        print_yellow "  ℹ  sup is managed by Homebrew. Run: brew upgrade sup"
        return 0
    fi

    if [[ ! -w "$install_path" ]]; then
        print_red "  ✗  Cannot write to $install_path. Try: sudo sup --self-update"
        return 1
    fi

    local tmp_script tmp_checksums expected actual
    tmp_script="$(mktemp)"
    tmp_checksums="$(mktemp)"

    print_cyan "  Downloading latest sup..."
    curl -fsSL "${SUP_RELEASE_BASE}/sup.sh" -o "$tmp_script" \
        || { print_red "  ✗  Download failed."; rm -f "$tmp_script" "$tmp_checksums"; return 1; }
    curl -fsSL "${SUP_RELEASE_BASE}/checksums.txt" -o "$tmp_checksums" \
        || { print_red "  ✗  Checksum download failed."; rm -f "$tmp_script" "$tmp_checksums"; return 1; }

    expected="$(awk '$2 == "sup.sh" || $2 == "./sup.sh" { gsub(/\*/, "", $2); print $1; exit }' "$tmp_checksums")"
    actual="$(compute_sha256 "$tmp_script")" || { rm -f "$tmp_script" "$tmp_checksums"; return 1; }

    if [[ -z "$expected" || "$expected" != "$actual" ]]; then
        print_red "  ✗  Checksum verification failed. Aborting."
        rm -f "$tmp_script" "$tmp_checksums"
        return 1
    fi

    chmod +x "$tmp_script" || {
        print_red "  ✗  Failed to mark downloaded script as executable."
        rm -f "$tmp_script" "$tmp_checksums"
        return 1
    }
    mv "$tmp_script" "$install_path" || {
        print_red "  ✗  Failed to replace $install_path."
        rm -f "$tmp_script" "$tmp_checksums"
        return 1
    }
    rm -f "$tmp_checksums"
    print_green "  ✓  sup updated successfully."
}

# ── CLI parsing ───────────────────────────────────────────
parse_args() {
    if [[ "${1:-}" == "config" ]]; then
        SUBCOMMAND="config"
        return
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)        usage; exit 0 ;;
            --version)     printf 'sup v%s\n' "$SUP_VERSION"; exit 0 ;;
            --self-update) FLAG_SELF_UPDATE=true ;;
            --interactive) FLAG_INTERACTIVE=true ;;
            --list)        FLAG_LIST=true ;;
            --yes)         FLAG_YES=true ;;
            --no-cleanup)  SUP_CLEANUP=false ;;
            --dry-run)     FLAG_DRY_RUN=true ;;
            --verbose)     FLAG_VERBOSE=true ;;
            --skip)
                shift
                [[ -n "${1:-}" ]] || { print_red "  --skip requires a tool ID"; exit 1; }
                [[ "${1:-}" != -* ]] || { print_red "  --skip requires a tool ID, got flag: $1"; exit 1; }
                CLI_SKIP["$1"]=1
                ;;
            --only)
                shift
                [[ -n "${1:-}" ]] || { print_red "  --only requires a tool ID"; exit 1; }
                [[ "${1:-}" != -* ]] || { print_red "  --only requires a tool ID, got flag: $1"; exit 1; }
                CLI_ONLY["$1"]=1
                ;;
            *)
                print_red "  Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done

    if _is_true "$FLAG_DRY_RUN" && _is_true "$FLAG_YES"; then
        print_yellow "  ⚠  --dry-run and --yes were both provided; --dry-run takes priority."
        FLAG_YES=false
    fi
}

# ── Banner ────────────────────────────────────────────────
print_banner() {
    printf '\n'
    printf "  ${CYAN}███████╗██╗   ██╗██████╗${RESET}\n"
    printf "  ${CYAN}██╔════╝██║   ██║██╔══██╗${RESET}\n"
    printf "  ${CYAN}███████╗██║   ██║██████╔╝${RESET}\n"
    printf "  ${CYAN}╚════██║██║   ██║██╔═══╝${RESET}\n"
    printf "  ${CYAN}███████║╚██████╔╝██║${RESET}\n"
    printf "  ${CYAN}╚══════╝ ╚═════╝ ╚═╝${RESET}\n"
    printf '\n'
    printf "  One Command. Everything Updated.    ${DIM}v%s${RESET}\n" "$SUP_VERSION"
    printf "  ${DIM}by zayd${RESET}\n"
    printf "  ─────────────────────────────────────────\n\n"
}

# ══════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════
main() {
    register_all_steps
    load_preferences
    parse_args "$@"

    # Subcommand: config
    if [[ "$SUBCOMMAND" == "config" ]]; then
        run_config_menu
        exit $?
    fi

    # Self-update
    if _is_true "$FLAG_SELF_UPDATE"; then
        if _is_true "$FLAG_DRY_RUN"; then
            printf "  ${DIM}dry-run:${RESET} would run self-update (download + checksum verify + replace binary)\n"
            exit 0
        fi
        self_update
        exit $?
    fi

    print_banner

    # List mode
    if _is_true "$FLAG_LIST"; then
        cache_install_sources
        run_list
        exit 0
    fi

    # Self-update notification (background-safe, quick)
    check_self_update

    # Network check
    check_network

    # Detect sudo capability
    detect_sudo

    # Detection phase
    printf "  ${DIM}Scanning for installed tools...${RESET}\n\n"
    detect_tools

    if _is_true "$FLAG_INTERACTIVE"; then
        interactive_select_tools || exit 130
    fi

    if ! show_found_tools; then
        exit 0
    fi

    # Dry-run mode
    if _is_true "$FLAG_DRY_RUN"; then
        run_dry_run
        exit 0
    fi

    # Confirmation
    confirm_or_exit || exit 1

    # Optional post-consent bootstrap to improve Python-tool update reliability.
    ensure_uv
    cache_install_sources

    # Pre-elevate sudo if needed
    local step
    for step in "${FOUND_TOOLS[@]}"; do
        if [[ "${STEP_SUDO[$step]}" == "yes" ]]; then
            pre_elevate
            break
        fi
    done

    printf '\n'
    RUN_START=$(date +%s)

    # Execution phase
    run_all_updates

    # Summary
    print_summary

    # Log
    log_file "Completed: OK=$TOTAL_OK FAIL=$TOTAL_FAIL SKIP=$TOTAL_SKIP"

    # Exit code
    if (( TOTAL_FAIL > 0 )); then
        exit 1
    fi
    exit 0
}

main "$@"

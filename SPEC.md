# SUP — The AI-Native Universal Updater

```
  ███████╗██╗   ██╗██████╗
  ██╔════╝██║   ██║██╔══██╗
  ███████╗██║   ██║██████╔╝
  ╚════██║██║   ██║██╔═══╝
  ███████║╚██████╔╝██║
  ╚══════╝ ╚═════╝ ╚═╝

  One Command. Everything Updated.
  ─────────────────────────────────
  by zayd                v1.0.0
```

**Version**: 1.0.0
**Architect**: zayd
**License**: MIT
**Language**: Bash (4.0+ required)
**Platforms**: macOS, Linux
**Repository**: `github.com/zaydiscold/sup`

---

## Table of Contents

1. [Product Philosophy](#1-product-philosophy)
2. [Platform Requirements](#2-platform-requirements)
3. [Architecture](#3-architecture)
4. [Customization Model](#4-customization-model)
5. [UX Flow](#5-ux-flow)
6. [The Runner Pattern](#6-the-runner-pattern)
7. [Tool Registry](#7-tool-registry)
8. [uv Auto-Install](#8-uv-auto-install)
9. [Error Handling & Retry Logic](#9-error-handling--retry-logic)
10. [Sudo Handling](#10-sudo-handling)
11. [Self-Update Mechanism](#11-self-update-mechanism)
12. [Network Connectivity](#12-network-connectivity)
13. [Terminal Output & Branding](#13-terminal-output--branding)
14. [CLI Interface](#14-cli-interface)
15. [Distribution & Installation](#15-distribution--installation)
16. [Repository Structure](#16-repository-structure)
17. [Future Roadmap](#17-future-roadmap)
18. [Appendices](#18-appendices)

---

## 1. Product Philosophy

### Core Principles

**Zero-Config by Default**: `sup` requires no configuration file, no TOML, no YAML, no setup. Run it and it works. Power users who want persistent preferences can run `sup config` to set them interactively. The tool never installs something the user doesn't already have (one exception: uv auto-install if missing, which is non-invasive and user-space only).

**Mass Appeal**: This is not a power-user tool. It is for everyone who has ever thought "I should update my stuff" and didn't because it meant running 12 different commands. The target audience is any developer, designer, or technical user on macOS or Linux.

**The Waterfall**: `sup` follows a strict linear sequence. Detect what's installed, show the user, get one confirmation, run everything, show a summary. No branching, no menus, no interactive selection during the update run itself.

**Transparency**: Because `sup` is a Bash script and not a compiled binary, any user can open it and read exactly what it does. `cat $(which sup)` shows every command. This builds trust and is a selling point over compiled alternatives.

**Curated, Not Exhaustive**: `sup` supports ~49 carefully chosen tools, not 180+. Every entry has been verified for command correctness, risk level, and real-world usefulness. System package managers (Homebrew, apt) act as a catch-all net — anything installed through them (subfinder, ffmpeg, nmap, etc.) gets updated automatically without needing its own entry.

**AI-Native Awareness**: `sup` is the first universal updater that comprehensively covers AI-native developer tools — Claude Code, Gemini CLI, Ollama, Goose, Amazon Q, Aider, Open Interpreter, HuggingFace CLI, Codex CLI, GitHub Copilot. Ten AI tools vs topgrade's one. This is the differentiator.

---

## 2. Platform Requirements

### Bash 4.0+ (Hard Requirement)

`sup` requires Bash 4.0 or later. This is a hard requirement, not a soft preference.

**Why**: The runner pattern uses associative arrays (`declare -A`), which are a Bash 4+ feature. Writing POSIX-compatible fallbacks would double the code complexity, create two untestable code paths, and make contributing harder — all for a shrinking edge case.

**macOS caveat**: macOS ships Bash 3.2 due to GPL licensing. However, sup's target audience (developers with Homebrew) can install Bash 4+ trivially. The installer handles this.

**Startup check**:

```bash
if ((BASH_VERSINFO[0] < 4)); then
    printf '\033[0;31m  ✗  sup requires Bash 4.0+. You have %s.\033[0m\n' "$BASH_VERSION"
    printf '     Install with: brew install bash\n'
    printf '     Then run: /opt/homebrew/bin/bash -c "sup"\n'
    exit 3
fi
```

### Other Dependencies

`sup` uses only tools that ship with macOS and every Linux distro:

- `curl` — network check, self-update check, Ollama update
- `shasum` or `sha256sum` — self-update integrity verification (`shasum` ships with macOS; `sha256sum` ships with most Linux distros; sup tries both)
- `tput` / ANSI escape codes — colors and cursor control
- `mktemp` — temporary error capture files
- Standard POSIX utils: `grep`, `awk`, `sed`, `uname`, `command`, `printf`

Nothing is installed. Nothing is downloaded except tool updates the user already has.

---

## 3. Architecture

### Design Principles (Adapted from topgrade)

**The Runner Pattern**: A central loop iterates through a registry of steps. Each step is a pair of Bash functions (`check_<name>` and `update_<name>`) plus metadata variables. The runner calls the check function, and if the tool is present, queues it for update. No `eval` is used anywhere — all dispatch is through direct function calls.

**Collect, Don't Stop**: Errors are accumulated into arrays during execution. The tool never halts on a single failure. Everything is presented in the final summary. This means `set -e` is explicitly NOT used. The script uses `set -uo pipefail` only, with all error handling done explicitly via return code checks.

**OS Gating**: Each step declares which OS it supports via a metadata variable. The runner detects the current platform once at startup (`CURRENT_OS=$(uname -s | tr '[:upper:]' '[:lower:]')` → `darwin` or `linux`) and only executes steps with matching OS metadata. All OS values in metadata must be lowercase.

**Sequential Execution**: Updates run one at a time, never in parallel. This is intentional (borrowed from topgrade): package managers can conflict (apt lock files, brew locks), output would be interleaved, sudo credential caching works linearly, and error recovery is simpler.

### File Structure

```
sup.sh              # The entire tool (~1200-1500 lines, single file)
```

Single-file design is deliberate. Users can `cat $(which sup)` and audit every command. Each tool is ~15 lines (check + update + metadata), and infrastructure (runner, CLI, output) is ~500 lines.

---

## 4. Customization Model

### The Tension Resolved

sup's philosophy is "zero-config by default" but users need persistent preferences without memorizing CLI flags. The solution is three tiers:

### Tier 1: Zero-Config Default

```bash
sup
```

Works perfectly out of the box. No config file created or required. Sensible defaults: cleanup enabled, all detected tools updated, confirmation prompt shown.

### Tier 2: Interactive Preferences (`sup config`)

Running `sup config` opens an interactive menu for setting persistent preferences:

```
  SUP — Configuration
  ─────────────────────────────────────────

  Which tools should sup always skip? (space to toggle)

    [ ] Homebrew
    [ ] apt
    [x] macOS System Update Check
    [ ] Rustup
    [ ] npm globals
    ...

  Enable cleanup after updates? [Y/n] y
  Enable brew greedy mode (update auto-updating casks)? [y/N] n

  ✓  Preferences saved to ~/.config/sup/preferences
```

The interactive menu uses a two-tier approach:

1. **If `gum` is available** (charmbracelet, `brew install gum`): Uses `gum choose --no-limit` for a best-in-class checkbox experience with arrow keys, space-to-toggle, and `gum confirm` for boolean prompts.
2. **Otherwise**: Uses an embedded pure-Bash multiselect widget (~100 lines, adapted from battle-tested open-source implementations). Arrow keys or j/k to navigate, space to toggle `[ ]` / `[✔]`, enter to confirm. No external dependencies — works on any system with Bash 4+.

`fzf` is not used because it's optimized for fuzzy-searching large lists, not toggling a known set of options. `dialog`/`whiptail` is not used because its ncurses aesthetic clashes with sup's branded terminal output and it isn't pre-installed on macOS.

Most popular CLI tools (topgrade, starship, nvm) don't have interactive config at all — they rely on hand-edited config files. `sup config` is a deliberate UX differentiator: configuration should be as easy as running a command, not editing TOML.

**Preferences file** (`~/.config/sup/preferences`):

```bash
# sup preferences — generated by `sup config`
# Edit manually or re-run `sup config`
SUP_SKIP="macos_system"
SUP_CLEANUP=true
SUP_BREW_GREEDY=false
SUP_AUTO_RETRY=1
```

Format is simple `KEY=value`, loaded via a safe parser (NOT `source` or `eval`). This file is never required — if it doesn't exist, defaults apply.

**Security**: The loader does NOT use `eval` or `source` — both are vulnerable to code injection (a value like `SUP_SKIP=$(rm -rf /)` would execute the command substitution). Instead, it extracts the key and value separately and uses a safe explicit case statement:

```bash
load_preferences() {
    local prefs="${XDG_CONFIG_HOME:-$HOME/.config}/sup/preferences"
    [[ -f "$prefs" ]] || return 0
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        if [[ "$line" =~ ^(SUP_[A-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip surrounding quotes if present
            val="${val#\"}" ; val="${val%\"}"
            val="${val#\'}" ; val="${val%\'}"
            case "$key" in
                SUP_SKIP)         SUP_SKIP="$val" ;;
                SUP_CLEANUP)      SUP_CLEANUP="$val" ;;
                SUP_BREW_GREEDY)  SUP_BREW_GREEDY="$val" ;;
                SUP_AUTO_RETRY)   SUP_AUTO_RETRY="$val" ;;
                *)  print_yellow "  ⚠  Unknown preference: $key" ;;
            esac
        else
            print_yellow "  ⚠  Ignoring invalid preferences line: $line"
        fi
    done < "$prefs"
}
```

The case statement explicitly lists every supported preference key. Unknown keys are warned about but not assigned. Values are never evaluated — they're treated as literal strings via `"$val"` assignment.

### Tier 3: CLI Overrides

Flags override preferences for a single run:

```bash
sup --skip homebrew          # Skip Homebrew for this run only
sup --only claude            # Update only Claude Code
sup --yes                    # Skip confirmation prompt
sup --no-cleanup             # Skip cleanup for this run
```

### Precedence

```
CLI flags  >  preferences file  >  built-in defaults
```

---

## 5. UX Flow

### The Waterfall (Step by Step)

```
┌──────────────────────────────────────────────────┐
│  1. Check Bash version (exit if < 4.0)           │
│  2. Print ASCII banner + version                 │
│  3. Load preferences (if file exists)            │
│  4. Apply CLI flag overrides                     │
│  5. Self-update notification check (3s timeout)  │
│  6. Network connectivity check (warn, continue)  │
│  7. Detect installed tools (silent scan)         │
│  8. Display found tools (colored list)           │
│  9. Show sudo-requiring tools (if any)           │
│ 10. Single confirmation (Enter / Ctrl+C)         │
│ 11. Pre-cache sudo if any step needs it          │
│ 12. Execute updates sequentially                 │
│     ├─ Per tool: spinner → ✓ or ✗ (+ time)      │
│     ├─ Per tool: cleanup if update succeeded     │
│     ├─ On failure: auto-retry once, then report  │
│     ├─ Risky tools: extra Y/n prompt             │
│     └─ Per failure: classify + persist reason       │
│ 13. Summary report (colored, with timings)       │
│ 14. Write run log to ~/.local/share/sup/last.log │
│ 15. Exit with appropriate code                   │
└──────────────────────────────────────────────────┘
```

### Key Changes from Initial Design

- **Network check warns but does not abort.** Some tools (oh-my-zsh, local git repos) can update without internet. Individual tools will fail if they need network, and the collect-and-report pattern handles this gracefully.
- **macOS System Update is check-only.** Shows available updates but prints a manual command instead of installing. OS-level updates are too disruptive for a quick daily runner.
- **Auto-retry on failure.** Each failed update is automatically retried once before being recorded as a failure. This handles transient network issues without user intervention.
- **uv auto-install is proactive.** During detection (before updates run), sup installs `uv` if missing. This improves Python-tool update reliability while staying non-invasive (`~/.local/bin`).
- **Per-tool cleanup.** Cleanup runs inside each tool's update function (only if the update succeeded), not as a separate phase. This keeps cleanup errors associated with the correct tool.
- **Run log.** Every run writes a detailed log to `~/.local/share/sup/last.log` for debugging. This is always written, independent of `--verbose`.

### Example Terminal Session

```
  ███████╗██╗   ██╗██████╗
  ██╔════╝██║   ██║██╔══██╗
  ███████╗██║   ██║██████╔╝
  ╚════██║██║   ██║██╔═══╝
  ███████║╚██████╔╝██║
  ╚══════╝ ╚═════╝ ╚═╝
  One Command. Everything Updated.    v1.0.0
  ─────────────────────────────────────────

  ℹ  New version available: 1.1.0 → run `sup --self-update`

  Scanning for installed tools...

  Found 14 updatable tools:
  ─────────────────────────────────────────
   1. Homebrew            (formulae + casks)
   2. Rustup              (toolchains)
   3. uv                  (self-update)
   4. npm                 (global packages)
   5. Bun                 (runtime)
   6. Deno                (runtime)
   7. Claude Code         (AI assistant)
   8. Gemini CLI          (AI assistant)
   9. Ollama              (local LLMs)
  10. GitHub CLI          (extensions)
  11. Vercel CLI          (deployment)
  12. VS Code             (extensions)
  13. Cursor              (extensions)
  14. oh-my-zsh           (shell framework)
  ─────────────────────────────────────────

  Press ENTER to update all, or Ctrl+C to cancel.

  Updating Homebrew...              ✓  47 formulae, 3 casks    (34s)
  Updating Rustup...                ✓  stable 1.84.0           (4s)
  Updating uv...                    ✓  0.6.2 → 0.6.3          (2s)
  Updating npm globals...           ✓  12 packages             (8s)
  Updating Bun...                   ✓  1.2.1                   (3s)
  Updating Deno...                  ✓  2.2.0                   (2s)
  Updating Claude Code...           ✓  1.0.21                  (5s)
  Updating Gemini CLI...            ✓  0.1.12                  (3s)
  Updating Ollama...                ✓  0.6.1                   (6s)
  Updating GitHub CLI extensions... ✓  2 extensions            (4s)
  Updating Vercel CLI...            ✓  39.3.0                  (5s)
  Updating VS Code extensions...    ✓  updated                 (8s)
  Updating oh-my-zsh...             ✓  latest                  (2s)
  Updating Composer...              ✗  FAIL (retried)          (62s)

  ═══════════════════════════════════════════
  SUP SUMMARY
  ═══════════════════════════════════════════

  ✓  12 updated successfully
  ✗   1 failed

  FAILURES:
  ──────────────────────────────────────────
  Composer             Network error. Check your connection.
                       Try: composer self-update
  ──────────────────────────────────────────

  Done in 2m 14s. Stay fresh. 🤙
```

---

## 6. The Runner Pattern

This is the core engine of `sup`, adapted from topgrade's Rust runner into Bash.

### Step Registration

Each tool is registered via a naming convention. No `eval`, no string parsing, no complex wiring.

```bash
# ── Step ordering ──
STEP_ORDER=(
    homebrew
    homebrew_cask
    apt
    snap
    flatpak
    mas
    macos_system
    rustup
    uv
    pipx
    conda
    mamba
    pyenv
    asdf
    mise
    npm
    pnpm
    bun
    deno
    claude
    gemini
    ollama
    goose
    amazon_q
    aider
    open_interpreter
    huggingface
    copilot
    codex
    gh_extensions
    vercel
    firebase
    supabase
    railway
    flyctl
    wrangler
    gcloud
    terraform
    vscode
    vscode_insiders
    vscodium
    ohmyzsh
    ohmybash
    fisher
    tmux_plugins
    gem
    composer
    cargo_crates
    go_binaries
)

# ── Per-tool metadata ──
declare -A STEP_OS STEP_RISK STEP_SUDO STEP_LABEL STEP_TIMEOUT

STEP_OS[homebrew]="darwin,linux"
STEP_RISK[homebrew]="safe"
STEP_SUDO[homebrew]="no"
STEP_LABEL[homebrew]="Homebrew"
STEP_TIMEOUT[homebrew]=300

# ── Startup: detect platform once ──
CURRENT_OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# ── Per-tool functions ──
check_homebrew() { command -v brew &>/dev/null; }
update_homebrew() {
    brew update
    brew upgrade
    if [[ "${SUP_CLEANUP:-true}" == "true" ]]; then
        brew cleanup --prune=7 2>/dev/null
        brew autoremove 2>/dev/null
    fi
}
```

Adding a new tool requires: one entry in `STEP_ORDER`, four metadata assignments, and two functions. That's it.

### The Runner Loop

All phases run inside functions (required for `local` variables).

```bash
declare -a FOUND_TOOLS=()
declare -A RESULTS=()
declare -A ERRORS=()
declare -A TIMINGS=()
TOTAL_OK=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# ── Phase 1: Detection ──
detect_tools() {
    # Cache install sources once for install-method detection
    cache_install_sources
    # Proactively ensure uv exists (non-blocking fallback)
    ensure_uv
    # Refresh caches in case uv was just installed
    cache_install_sources

    for step in "${STEP_ORDER[@]}"; do
        # OS gate
        if ! os_matches "${STEP_OS[$step]}"; then continue; fi

        # Preference gate (skip if user configured to skip)
        if is_skipped "$step"; then continue; fi

        # Detection (direct function call, no eval)
        if "check_${step}" 2>/dev/null; then
            FOUND_TOOLS+=("$step")
        fi
    done
}

# ── Phase 2: Confirmation (show found tools, wait for Enter) ──

# ── Phase 3: Execution ──
run_all_updates() {
    for step in "${FOUND_TOOLS[@]}"; do
        local label="${STEP_LABEL[$step]}"
        local timeout="${STEP_TIMEOUT[$step]:-120}"
        local risk="${STEP_RISK[$step]:-safe}"
        local needs_sudo="${STEP_SUDO[$step]:-no}"

        # Risky tool: extra confirmation
        if [[ "$risk" == "warn" ]]; then
            warn_and_confirm "$label" || { RESULTS[$step]="SKIP"; ((TOTAL_SKIP++)); continue; }
        fi

        # Sudo prompt if needed
        if [[ "$needs_sudo" == "yes" ]]; then
            ensure_sudo "$label" || { RESULTS[$step]="SKIP"; ((TOTAL_SKIP++)); continue; }
        fi

        # Execute: background the update, animate spinner in foreground
        local start_time stderr_file
        start_time=$(date +%s)
        stderr_file=$(mktemp "${TMPDIR:-/tmp}/sup_${step}_XXXXXX")
        TEMP_FILES+=("$stderr_file")

        run_with_retry "$step" "$timeout" "$stderr_file" &
        local update_pid=$!

        spin_while "$update_pid" "$label"
        wait "$update_pid"
        local rc=$?

        local elapsed=$(( $(date +%s) - start_time ))
        TIMINGS[$step]="$elapsed"

        if (( rc == 0 )); then
            RESULTS[$step]="OK"
            ((TOTAL_OK++))
            show_spinner_done "$label" "$elapsed"
        else
            RESULTS[$step]="FAIL"
            ((TOTAL_FAIL++))
            local reason_file="${stderr_file}.reason"
            if [[ -f "$reason_file" ]]; then
                ERRORS[$step]="$(<"$reason_file")"
                rm -f "$reason_file"
            else
                ERRORS[$step]="Unknown error (exit code $rc)."
            fi
            show_spinner_fail "$label" "$elapsed"
        fi
        rm -f "$stderr_file"
    done
}
```

The key pattern: the update runs in the **background**, the spinner runs in the **foreground** polling the PID, and `wait` collects the exit code. This is the only way to animate the spinner while the update executes.

### Helper Functions

```bash
os_matches() {
    local filter="$1"
    [[ "$filter" == "all" ]] && return 0
    [[ "$filter" == *"$CURRENT_OS"* ]]
}

is_skipped() {
    local step="$1"
    [[ " ${SUP_SKIP:-} " == *" $step "* ]]
}

run_with_retry() {
    local step="$1"
    local timeout="$2"
    local stderr_file="$3"
    local max_attempts=$(( 1 + ${SUP_AUTO_RETRY:-1} ))
    local attempt=1

    while (( attempt <= max_attempts )); do
        run_with_timeout "$timeout" "update_${step}" 2>>"$stderr_file"
        local rc=$?
        if (( rc == 0 )); then
            return 0
        fi
        if (( attempt < max_attempts )); then
            ((attempt++))
            : > "$stderr_file"
            continue
        fi
        classify_error "$step" "$rc" "$stderr_file"
        return 1
    done
}
```

**Note on stderr capture**: The `2>>` redirect is applied to the `run_with_timeout` call. Since `run_with_timeout` invokes the function directly (not via a subshell), the function inherits this file descriptor, and stderr flows into the capture file correctly.

### Portable Timeout (No GNU `timeout` Required)

macOS does not ship GNU `timeout`. This is a Bash-native replacement.

Since `run_with_retry` is already backgrounded by the runner loop (to allow the spinner), `run_with_timeout` backgrounds the update function and uses a watchdog subshell to enforce the deadline. Only the child PID is killed — never `$$` (which would kill the entire script):

```bash
run_with_timeout() {
    local secs="$1"; shift
    local func="$1"

    "$func" &
    local pid=$!

    ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null ) &
    local watchdog=$!

    wait "$pid" 2>/dev/null
    local rc=$?

    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null 2>&1

    # 128+15 = 143 (SIGTERM). Map to 124 (GNU timeout convention).
    (( rc == 143 )) && return 124
    return $rc
}
```

When the watchdog fires, it kills only the backgrounded update function. The runner detects a timeout via exit code 124. stderr capture still works because the `2>>` redirect on `run_with_timeout` is inherited by the backgrounded function.

---

## 7. Tool Registry

Every command below has been researched and verified. System package managers (Homebrew, apt, etc.) are catch-all nets: anything installed through them — subfinder, ffmpeg, nmap, go, python, or any of their thousands of packages — gets updated automatically. Individual entries are only needed for tools with their own update mechanisms.

### Tier 1: System Package Managers

These run first because they may update runtimes and tools that later steps depend on.

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 1 | **Homebrew** (formulae) | `command -v brew` | `brew update && brew upgrade` | macOS, Linux | No | Safe | 300s |
| 2 | **Homebrew** (casks) | `command -v brew` | `brew upgrade --cask` (add `--greedy` if configured) | macOS | No | Safe | 300s |
| 3 | **apt** | `command -v apt-get` | `sudo apt-get update -qq && sudo apt-get upgrade -y` | Linux | Yes | Safe | 300s |
| 4 | **Snap** | `command -v snap` | `sudo snap refresh` | Linux | Yes | Safe | 300s |
| 5 | **Flatpak** | `command -v flatpak` | `flatpak update -y` | Linux | No | Safe | 300s |
| 6 | **Mac App Store** (mas) | `command -v mas` | `mas upgrade` | macOS | No | Safe | 120s |
| 7 | **macOS System** | `LANG=C softwareupdate -l 2>&1 \| grep -qv "No new software"` | **Check-only.** Print available updates, then: `printf "Run: sudo softwareupdate -i -a\n"` | macOS | No | Info | 30s |

**Why Homebrew casks are separate**: `brew upgrade` only upgrades formulae (CLI packages). `brew upgrade --cask` is a separate command required to upgrade GUI applications (Slack, Chrome, VS Code, etc.). Topgrade keeps them separate for the same reason. Additionally, the `--greedy` flag (opt-in via `sup config`) forces updates even on casks that auto-update themselves (Chrome, Firefox) — without it, those casks are skipped.

```bash
check_homebrew_cask() {
    [[ "$CURRENT_OS" == "darwin" ]] && command -v brew &>/dev/null
}
update_homebrew_cask() {
    if [[ "${SUP_BREW_GREEDY:-false}" == "true" ]]; then
        brew upgrade --cask --greedy
    else
        brew upgrade --cask
    fi
}
```

**Why macOS System Update is check-only**: `sudo softwareupdate -i -a` can trigger multi-GB OS upgrades and mandatory restarts. This is too disruptive for a tool that aims to finish in under 5 minutes. sup shows what's available and tells the user to run it manually. The check uses `LANG=C` and negative matching (`grep -qv "No new software"`) to avoid locale-dependent string issues on non-English systems.

**Cleanup** (runs inside update functions, gated by `SUP_CLEANUP`):
- Homebrew: `brew cleanup --prune=7 && brew autoremove`
- apt: `sudo apt-get autoremove -y`

### Tier 2: Language Runtimes & Version Managers

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 8 | **Rustup** | `command -v rustup` | `rustup update` | all | No | Safe | 120s |
| 9 | **uv** | `command -v uv` | `uv self update` | all | No | Safe | 60s |
| 10 | **pipx** | `command -v pipx` | `pipx upgrade-all` | all | No | Safe | 120s |
| 11 | **Conda** (self only) | `command -v conda` | `conda update conda -y` | all | No | Safe | 120s |
| 12 | **Mamba** (self only) | `command -v mamba` | `mamba update mamba -y` | all | No | Safe | 120s |
| 13 | **pyenv** | See note below | `pyenv update` | darwin,linux | No | Safe | 60s |
| 14 | **asdf** (plugins only) | `command -v asdf` | `asdf plugin update --all` | darwin,linux | No | Safe | 120s |
| 15 | **mise** | `command -v mise` | `mise self-update && mise upgrade` | darwin,linux | No | Safe | 120s |

**pyenv note**: `pyenv update` requires the `pyenv-update` plugin, which is not installed by default. The check function verifies the plugin exists:

```bash
check_pyenv() {
    command -v pyenv &>/dev/null || return 1
    pyenv commands 2>/dev/null | grep -q '^update$'
}
```

**fnm note**: fnm has no self-update command. If installed via Homebrew, `brew upgrade` already covers it. If installed via the curl installer, users must re-run the installer manually. sup does not include fnm as a separate step — it is covered implicitly by the Homebrew tier.

**asdf note**: Since asdf v0.16 (rewritten in Go), the `asdf update` self-update command has been removed. Upgrading asdf core is now done via the OS package manager (e.g., `brew upgrade asdf`) or manual binary download. sup only runs `asdf plugin update --all` to update plugin definitions. If asdf was installed via Homebrew, the Homebrew tier already handles the core binary upgrade.

**pip note (deferred to v1.1)**: `pip install --upgrade pip` on system Python can break package management on many Linux distros. The detection logic (EXTERNALLY-MANAGED markers, path checks) is fragile and the consequences of getting it wrong are severe. uv and pipx already cover Python tooling safely in v1. pip self-update will be re-added in v1.1 with hardened safety gates.

### Tier 3: Node.js Ecosystem

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 16 | **npm** (global) | `command -v npm` | `npm update -g` | all | No | Safe | 120s |
| 17 | **pnpm** (self + global) | `command -v pnpm` | `pnpm self-update && pnpm update -g` | all | No | Safe | 120s |
| 18 | **Bun** | `command -v bun` | `bun upgrade` | all | No | Safe | 60s |
| 19 | **Deno** | `command -v deno` | `deno upgrade` | all | No | Safe | 60s |

**Yarn note (removed from v1)**: Yarn Classic (1.x) is frozen at 1.22.22 — there's nothing to update. Yarn Berry (2+) is per-project with no meaningful global update path. Corepack (the Berry manager) is being removed from Node.js in v25+. If Yarn was installed via Homebrew, `brew upgrade` in Tier 1 already handles it. Keeping a dedicated Yarn step adds version-detection complexity for zero practical value.

### Tier 4: AI-Native Tools (The Differentiator)

This is where `sup` stands alone. Topgrade only covers Claude Code and Cursor extensions. sup covers the full AI developer toolkit.

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 20 | **Claude Code** | `command -v claude` | Detect: `brew upgrade claude-code` or `claude update` | all | No | Safe | 120s |
| 21 | **Gemini CLI** | `command -v gemini` | Detect: `brew upgrade gemini-cli` or `npm update -g @google/gemini-cli` | all | No | Safe | 60s |
| 22 | **Ollama** | `command -v ollama` | Detect: `brew upgrade ollama` or (Linux) `curl -fsSL https://ollama.com/install.sh \| sh` | all | No | Safe | 120s |
| 23 | **Goose** (Block) | `command -v goose` | Detect: `brew upgrade block-goose-cli` or `brew upgrade --cask block-goose` or `curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh \| CONFIGURE=false bash` | all | No | Safe | 120s |
| 24 | **Amazon Q CLI** | `command -v q` | `q update --non-interactive` | all | No | Safe | 60s |
| 25 | **Aider** | `command -v aider` | Detect: `uv tool install --force aider-chat@latest` or `pipx upgrade aider-chat` | all | No | Safe | 120s |
| 26 | **Open Interpreter** | `command -v interpreter` | Detect: `pipx upgrade open-interpreter` or `uv tool install --force open-interpreter@latest` | all | No | Safe | 60s |
| 27 | **HuggingFace CLI** | `command -v huggingface-cli` | Detect: `uv tool install --force "huggingface_hub[cli]@latest"` or `pipx upgrade huggingface-hub` | all | No | Safe | 60s |
| 28 | **GitHub Copilot** (gh ext) | `gh extension list 2>/dev/null \| grep -q copilot` | `gh extension upgrade gh-copilot` | all | No | Safe | 60s |
| 29 | **Codex CLI** | `command -v codex` | Detect: `brew upgrade codex` or `npm install -g @openai/codex` | all | No | Safe | 60s |

**Claude Code install-method detection**: If installed via Homebrew (`brew list claude-code` succeeds), use `brew upgrade claude-code`. Otherwise, use `claude update` (the native installer auto-updates in the background, but the explicit command forces an immediate check).

**Ollama on macOS desktop**: If Ollama is installed as the macOS desktop app (not via Homebrew), it auto-updates itself — no action needed. sup detects this by checking if `brew list ollama` succeeds. If yes, it uses `brew upgrade ollama`. If no, it skips on macOS (desktop app handles it) or runs the curl installer on Linux.

**Goose update strategy**: Do NOT use `goose update` — it has documented reliability issues and is being rewritten. Instead: check `brew list --formula block-goose-cli` (CLI formula, preferred), then `brew list --cask block-goose` (desktop app), then fall back to the curl installer with `CONFIGURE=false` to suppress interactive prompts:

```bash
update_goose() {
    if printf '%s\n' "$BREW_LIST" | grep -qxF "block-goose-cli"; then
        brew upgrade block-goose-cli
    elif printf '%s\n' "$BREW_CASK_LIST" | grep -qxF "block-goose"; then
        brew upgrade --cask block-goose
    else
        curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh \
            | CONFIGURE=false bash
    fi
}
```

**Amazon Q CLI**: The `q` binary name is short and could conflict. The check verifies it's the real Amazon Q: `command -v q &>/dev/null && q --version 2>&1 | grep -q "Amazon Q"`.

**MCP servers**: Model Context Protocol servers installed globally via npm (e.g., `npm install -g @modelcontextprotocol/server-filesystem`) are already updated by the npm globals step (`npm update -g`). MCP servers run via `npx` don't need updating — npx fetches the latest version on demand. No separate MCP step is needed.

**Install-method detection**: AI tools can be installed via brew, npm, pipx, uv, or run via npx. sup always checks brew first (to avoid conflicts with brew-managed installations), then falls back to native methods.

**npx-only tools are skipped**: Tools run exclusively via `npx` (e.g., `npx wrangler`, `npx firebase-tools`) are not globally installed and do not need updating — npx fetches the latest version on demand. The detection only considers globally installed packages.

**Cached detection** (avoids calling `brew list` / `npm list -g` per tool):

```bash
# Run once during detection phase, cache results
cache_install_sources() {
    BREW_LIST=""
    BREW_CASK_LIST=""
    BREW_FULL_LIST=""
    NPM_GLOBAL_LIST=""
    PIPX_LIST=""
    UV_TOOL_LIST=""

    if command -v brew &>/dev/null; then
        BREW_LIST=$(brew list --formula 2>/dev/null)
        BREW_CASK_LIST=$(brew list --cask 2>/dev/null)
        BREW_FULL_LIST=$(brew list --formula --full-name 2>/dev/null)
    fi
    command -v npm &>/dev/null && NPM_GLOBAL_LIST=$(npm list -g --depth=0 2>/dev/null)
    command -v pipx &>/dev/null && PIPX_LIST=$(pipx list --short 2>/dev/null)
    command -v uv &>/dev/null && UV_TOOL_LIST=$(uv tool list 2>/dev/null)
}

declare -A BREW_PKG_MAP=(
    [claude]="claude-code"
    [gemini]="gemini-cli"
    [codex]="codex"
    [goose]="block-goose-cli"
    [vercel]="vercel-cli"
    [firebase]="firebase-cli"
)

detect_install_method() {
    local tool="$1"
    local brew_name="${BREW_PKG_MAP[$tool]:-$tool}"

    # Word-boundary match via newline-delimited list to avoid substring collisions
    if printf '%s\n' "$BREW_LIST" | grep -qxF "$brew_name"; then
        echo "brew"
    elif printf '%s\n' "$NPM_GLOBAL_LIST" | grep -qF "$tool"; then
        echo "npm"
    elif printf '%s\n' "$PIPX_LIST" | grep -qF "$tool"; then
        echo "pipx"
    elif printf '%s\n' "$UV_TOOL_LIST" | grep -qF "$tool"; then
        echo "uv"
    else
        echo "native"
    fi
}
```

Caching runs once at startup (~2-3s total) instead of per-tool (~0.5-2s per call x 15+ tools = 10-30s). This keeps the detection phase fast.

### Tier 5: Developer CLIs

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 30 | **GitHub CLI** (extensions) | `command -v gh` | `gh extension upgrade --all` | all | No | Safe | 60s |
| 31 | **Vercel CLI** | `command -v vercel` | Detect: `brew upgrade vercel-cli` or `npm i -g vercel@latest` | all | No | Safe | 60s |
| 32 | **Firebase CLI** | `command -v firebase` | Detect: `brew upgrade firebase-cli` or `npm i -g firebase-tools@latest` | all | No | Safe | 60s |
| 33 | **Supabase CLI** | `command -v supabase` | Detect: `brew upgrade supabase` or `npm i -g supabase@latest` | all | No | Safe | 60s |
| 34 | **Railway CLI** | `command -v railway` | Detect: `brew upgrade railway` or `railway upgrade` | all | No | Safe | 60s |
| 35 | **Fly.io CLI** | `command -v flyctl` | `flyctl version upgrade` | all | No | Safe | 60s |
| 36 | **Wrangler** (Cloudflare) | `command -v wrangler` | Detect: `npm i -g wrangler@latest` (only if globally installed via npm, not npx) | all | No | Safe | 60s |
| 37 | **gcloud** | `command -v gcloud` | `gcloud components update --quiet` | all | No | Safe | 120s |
| 38 | **Terraform** | `command -v terraform` | Brew-only: auto-detect `hashicorp/tap/terraform` vs `terraform`; skip if tfenv or binary | all | No | Safe | 60s |

**Terraform note**: Terraform users often pin versions deliberately (via `required_version` blocks and `.terraform-version` files). sup only updates brew-managed Terraform. If tfenv is detected (`command -v tfenv`) or the install method is "native" (binary download), the step is silently skipped — these users are managing versions intentionally. The HashiCorp tap (`hashicorp/tap/terraform`) and the homebrew-core formula produce different binaries; `BREW_FULL_LIST` (which uses `--full-name`) distinguishes them:

```bash
update_terraform() {
    if printf '%s\n' "$BREW_FULL_LIST" | grep -qxF "hashicorp/tap/terraform"; then
        brew upgrade hashicorp/tap/terraform
    elif printf '%s\n' "$BREW_LIST" | grep -qxF "terraform"; then
        brew upgrade terraform
    else
        return 0
    fi
}
```

### Tier 6: Editors & Extensions

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 39 | **VS Code** (extensions) | `command -v code` | `code --update-extensions` | all | No | Safe | 60s |
| 40 | **VS Code Insiders** | `command -v code-insiders` | `code-insiders --update-extensions` | all | No | Safe | 60s |
| 41 | **VSCodium** | `command -v codium` | `codium --update-extensions` | all | No | Safe | 60s |

**VS Code extensions note**: `--update-extensions` is a valid CLI flag since VS Code 1.86. VS Code Insiders and VSCodium share the same CLI interface and support it.

**Cursor note (deferred to v1.1)**: Cursor's CLI (`cursor`) does not support `--update-extensions`. Cursor's new CLI is an AI agent interface, not a VS Code-compatible extension manager. There is no reliable non-interactive method to update Cursor extensions from a script. This step is deferred until Cursor exposes a stable extension update command.

### Tier 7: Shell Frameworks & Plugins

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 42 | **oh-my-zsh** | `[ -d "$HOME/.oh-my-zsh" ]` | See note below | darwin,linux | No | Safe | 30s |
| 43 | **oh-my-bash** | `[ -d "$HOME/.oh-my-bash" ]` | See note below | darwin,linux | No | Safe | 30s |
| 44 | **fisher** (fish) | `command -v fisher` | `fish -c "fisher update"` | darwin,linux | No | Safe | 30s |
| 45 | **tmux plugins** (TPM) | `[ -d "$HOME/.tmux/plugins/tpm" ]` | `"$HOME/.tmux/plugins/tpm/bin/update_plugins" all` | darwin,linux | No | Safe | 30s |

**zinit (deferred to v1.1)**: `zinit` is a Zsh function — it cannot be called from a Bash script directly. Running `zsh -ic "zinit self-update && zinit update --all"` is fragile (depends on user's `.zshrc` loading correctly in non-interactive mode). Deferred until a reliable cross-shell invocation is validated.

**oh-my-zsh note**: The `$ZSH` variable is set by oh-my-zsh's init script and is not available in Bash. sup sets the path explicitly:

```bash
update_ohmyzsh() {
    local omz_dir="$HOME/.oh-my-zsh"
    ZSH="$omz_dir" "$omz_dir/tools/upgrade.sh"
}
```

**oh-my-bash note**: Unlike oh-my-zsh (which has a standalone `tools/upgrade.sh`), oh-my-bash's upgrade function is defined inside its init script. sup invokes it via:

```bash
update_ohmybash() {
    local omb_dir="$HOME/.oh-my-bash"
    if [[ -f "$omb_dir/tools/upgrade.sh" ]]; then
        bash "$omb_dir/tools/upgrade.sh"
    else
        # Fallback: pull latest from git
        git -C "$omb_dir" pull --rebase --stat origin master
    fi
}
```

### Tier 8: Other Language Tools

| # | Tool | Check | Update Command | OS | Sudo | Risk | Timeout |
|---|------|-------|----------------|-----|------|------|---------|
| 46 | **Ruby gems** (system only) | `command -v gem` | `gem update --system` | all | No | **Warn** | 60s |
| 47 | **Composer** (self) | `command -v composer` | `composer self-update` | all | No | Safe | 60s |
| 48 | **Cargo crates** | `command -v cargo-install-update` | `cargo install-update -a` | all | No | Safe | 120s |
| 49 | **Go binaries** (gup) | `command -v gup` | `gup update` | all | No | Safe | 120s |

**Ruby gems safety note**: sup only runs `gem update --system` (updates RubyGems itself), NOT `gem update` (which updates all installed gems). Updating all gems can break system Ruby on macOS. Users who want that can run it manually.

**Cargo crates note**: Requires the third-party `cargo-install-update` crate. If it's installed, the user wants this functionality. If not, the check function returns false and the step is silently skipped.

---

## 8. uv Auto-Install

`uv` is the modern Python package manager (100x faster than pip, made by Astral). It's used by several tools in the registry (Aider, HuggingFace CLI, Open Interpreter) and is the preferred path for Python-related updates.

**If uv is not detected during the scan phase, sup installs it automatically.** This is the one exception to the "never install anything new" rule, and it's justified: uv is a standalone binary with no system-level side effects, it doesn't modify the user's Python installation, and it makes every downstream Python update faster and safer.

### How It Works

During the detection phase (before any updates run), after `cache_install_sources()`:

```bash
ensure_uv() {
    command -v uv &>/dev/null && return 0
    print_cyan "  Installing uv (fast Python package manager)..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        print_green "  ✓  uv installed"
    else
        print_yellow "  ⚠  uv install failed. Python tools will use pipx/native fallbacks."
    fi
}
```

This runs once, silently succeeds or falls back, and the rest of the run benefits from it. No prompt, no opt-in/opt-out preference needed.

**Why this is safe**: uv installs to `~/.local/bin/uv` (user-space). It does not replace pip, modify system Python, or require sudo. If the install fails (e.g., no internet), everything continues normally — tool update functions fall back to pipx or their native update paths.

---

## 9. Error Handling & Retry Logic

### Philosophy

`sup` **never stops** on a failed update. It collects all failures and presents them in the summary. One broken npm package should never prevent Homebrew from updating.

### Retry Logic (Adapted from topgrade)

Topgrade's three-tier retry system is one of its best patterns. sup adapts it:

**Tier 1 — Auto-retry** (silent): Each failed update is automatically retried once (configurable via `SUP_AUTO_RETRY`). This handles transient network issues.

**Tier 2 — Record and continue**: After auto-retries are exhausted, the failure is recorded and the runner moves to the next tool. No interactive retry prompt in v1 (keeps the "waterfall" philosophy clean).

**Tier 3 — Summary with fix suggestions**: The final report shows every failure with a classified reason and a suggested manual command.

### Error Capture

The runner loop (section 6) backgrounds `run_with_retry` and passes it a stderr capture file. `run_with_retry` calls `run_with_timeout`, which calls the update function directly. Stderr from the update function flows into the capture file via the `2>>` redirect on `run_with_timeout`. On final failure, `classify_error` reads the capture file to produce a human-readable message.

### Error Classification

Errors are classified by grepping stderr for known patterns:

| Pattern | Classification | User-Facing Message |
|---------|---------------|-------------------|
| `EACCES` or `permission denied` | Permission | "Permission denied. Try running the update with sudo." |
| `Could not resolve host` or `connection refused` | Network | "Network error. Check your connection and try again." |
| `404` or `not found` or `no such package` | Not Found | "Package or registry not found. May be deprecated or renamed." |
| `conflict` or `dependency` | Conflict | "Dependency conflict. Run the update manually to resolve." |
| Exit code 124 (timeout) | Timeout | "Timed out after {N}s. Try running it manually." |
| Everything else | Unknown | First 2 lines of stderr displayed directly. |

Each failure in the summary includes:
1. The tool name
2. A one-line human-readable reason
3. A suggested fix or the manual command to run

### Helper Functions (Referenced by Runner)

These are called by the runner loop (section 6) and must be defined in the script:

```bash
classify_error() {
    local step="$1" exit_code="$2" stderr_file="$3"
    local stderr_content reason
    stderr_content=$(head -5 "$stderr_file" 2>/dev/null)

    if (( exit_code == 124 )); then
        reason="Timed out after ${STEP_TIMEOUT[$step]:-?}s."
    elif grep -qiE 'EACCES|permission denied' "$stderr_file" 2>/dev/null; then
        reason="Permission denied. Try running the update with sudo."
    elif grep -qiE 'could not resolve|connection refused' "$stderr_file" 2>/dev/null; then
        reason="Network error. Check your connection and try again."
    elif grep -qiE '404|not found|no such package' "$stderr_file" 2>/dev/null; then
        reason="Package or registry not found. May be deprecated or renamed."
    elif grep -qiE 'conflict|dependency' "$stderr_file" 2>/dev/null; then
        reason="Dependency conflict. Run the update manually to resolve."
    else
        reason=$(head -2 "$stderr_file" 2>/dev/null | tr '\n' ' ')
        [[ -z "$reason" ]] && reason="Unknown error (exit code $exit_code)."
    fi

    # Write classification to a file the PARENT reads after wait
    printf '%s\n' "$reason" > "${stderr_file}.reason"
}

warn_and_confirm() {
    local label="$1"
    printf "  ${YELLOW}⚠${RESET}  %s is marked as risky. Continue? [y/N] " "$label"
    local reply
    read -r reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_sudo() {
    local label="$1"
    if [[ -z "${SUDO_CMD:-}" ]]; then
        print_yellow "  ⚠  $label requires elevated permissions but no sudo found. Skipping."
        return 1
    fi
    pre_elevate
}

print_summary() {
    printf "\n  ═══════════════════════════════════════════\n"
    printf "  SUP SUMMARY\n"
    printf "  ═══════════════════════════════════════════\n\n"
    printf "  ${GREEN}✓${RESET}  %d updated successfully\n" "$TOTAL_OK"
    (( TOTAL_FAIL > 0 )) && printf "  ${RED}✗${RESET}  %d failed\n" "$TOTAL_FAIL"
    (( TOTAL_SKIP > 0 )) && printf "  ${DIM}·${RESET}  %d skipped\n" "$TOTAL_SKIP"

    if (( TOTAL_FAIL > 0 )); then
        printf "\n  FAILURES:\n"
        printf "  ──────────────────────────────────────────\n"
        for step in "${FOUND_TOOLS[@]}"; do
            [[ "${RESULTS[$step]}" == "FAIL" ]] || continue
            local label="${STEP_LABEL[$step]}"
            local reason="${ERRORS[$step]:-Unknown error.}"
            printf "  %-20s %s\n" "$label" "$reason"
        done
        printf "  ──────────────────────────────────────────\n"
    fi
}
```

### Data Flow: Backgrounded Error Classification

**Critical constraint**: `run_with_retry` is backgrounded by the runner loop (to allow the spinner). Backgrounded subshells cannot modify parent associative arrays (`ERRORS`). The solution:

1. `classify_error` writes its reason to a file (`${stderr_file}.reason`) inside the backgrounded process.
2. After `wait "$update_pid"`, the parent reads `${stderr_file}.reason` and stores it in `ERRORS[$step]`.
3. `print_summary` reads `ERRORS[$step]` directly.

This avoids the impossible cross-process array mutation while keeping the interface simple.

### Run Log

Every invocation writes a detailed log to `~/.local/share/sup/last.log`. The log includes:
- Full timestamp and sup version
- Every command executed (with exit codes)
- Full stderr/stdout for failed steps
- System info (OS, Bash version, detected tools)

The log directory is created at startup if it does not exist:

```bash
SUP_LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sup"
SUP_LOG_FILE="$SUP_LOG_DIR/last.log"
mkdir -p "$SUP_LOG_DIR"
```

This is always written, independent of `--verbose`, and is invaluable for debugging.

---

## 10. Sudo Handling

Adapted from topgrade's pre-sudo pattern.

### Detection Order

```bash
detect_sudo() {
    for cmd in doas sudo pkexec; do
        if command -v "$cmd" &>/dev/null; then
            SUDO_CMD="$cmd"
            return 0
        fi
    done
    SUDO_CMD=""
    return 1
}
```

### Pre-Elevation

During the scan phase, sup identifies which found tools require sudo. If any do, it warns the user before the confirmation prompt and pre-caches credentials:

```
  Found 14 updatable tools.
  ⚠  2 tools need elevated permissions: apt, macOS System Update

  Press ENTER to update all, or Ctrl+C to cancel.
```

After confirmation, credentials are cached once:

```bash
pre_elevate() {
    [[ -z "${SUDO_CMD:-}" ]] && return
    case "$SUDO_CMD" in
        sudo)   $SUDO_CMD -v ;;
        doas)   $SUDO_CMD echo >/dev/null 2>&1 ;;
        *)      $SUDO_CMD echo >/dev/null 2>&1 ;;
    esac
}
```

The `sudo -v` credential cache is used so the user only types their password once. If a second sudo tool runs within the cache window (~5 min default), no re-prompt is needed.

### Per-Tool Sudo Wrapper

```bash
maybe_sudo() {
    if [[ "${SUDO_CMD:-}" ]]; then
        $SUDO_CMD "$@"
    else
        "$@"
    fi
}
```

---

## 11. Self-Update Mechanism

### How It Works

On every run, `sup` checks if a newer version exists (with a 3-second timeout to avoid slowing down the tool):

```bash
SUP_VERSION="1.0.0"

check_self_update() {
    [[ -n "${SUP_NO_SELF_UPDATE:-}" ]] && return
    local remote_version
    remote_version=$(curl -fsSL --max-time 3 \
        "https://raw.githubusercontent.com/zaydiscold/sup/main/VERSION" 2>/dev/null | tr -d '[:space:]')

    if [[ -n "$remote_version" ]] && version_gt "$remote_version" "$SUP_VERSION"; then
        print_yellow "  ℹ  New version available: $remote_version → run \`sup --self-update\`"
    fi
}
```

### Semver Comparison

Simple string comparison (`!=`) is not sufficient. `sup` uses a pure-Bash version comparator so it works on macOS (BSD `sort` lacks `-V`):

```bash
version_gt() {
    # Returns 0 if $1 > $2 (pure Bash, no GNU sort -V)
    [[ "$1" == "$2" ]] && return 1
    local IFS=.
    local i a=($1) b=($2)
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        local x=${a[i]:-0} y=${b[i]:-0}
        ((x > y)) && return 0
        ((x < y)) && return 1
    done
    return 1
}
```

### SHA-256 Integrity Verification

Self-update downloads are verified against published checksums before replacing the running script. This prevents supply chain attacks.

**Portable hash function** (macOS has `shasum`, most Linux has `sha256sum`):

```bash
compute_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        print_red "  ✗  No SHA-256 tool found. Cannot verify update."
        return 1
    fi
}
```

```bash
self_update() {
    local install_path tmp_script tmp_checksums expected_hash actual_hash
    install_path=$(command -v sup)

    # Guard: if sup is brew-managed, redirect to brew
    if command -v brew &>/dev/null && brew list sup &>/dev/null 2>&1; then
        print_yellow "  ℹ  sup is managed by Homebrew. Run: brew upgrade sup"
        return 0
    fi

    # Guard: check write permission to install path
    if [[ ! -w "$install_path" ]]; then
        print_red "  ✗  Cannot write to $install_path. Try: sudo sup --self-update"
        return 1
    fi

    tmp_script=$(mktemp)
    tmp_checksums=$(mktemp)

    print_cyan "  Downloading latest sup..."
    curl -fsSL "https://github.com/zaydiscold/sup/releases/latest/download/sup.sh" \
        -o "$tmp_script" || { print_red "  ✗  Download failed."; rm -f "$tmp_script" "$tmp_checksums"; return 1; }
    curl -fsSL "https://github.com/zaydiscold/sup/releases/latest/download/checksums.txt" \
        -o "$tmp_checksums" || { print_red "  ✗  Checksum download failed."; rm -f "$tmp_script" "$tmp_checksums"; return 1; }

    expected_hash=$(grep "sup.sh" "$tmp_checksums" | awk '{print $1}')
    actual_hash=$(compute_sha256 "$tmp_script") || { rm -f "$tmp_script" "$tmp_checksums"; return 1; }

    if [[ -z "$expected_hash" || "$expected_hash" != "$actual_hash" ]]; then
        print_red "  ✗  Checksum verification failed. Aborting update."
        rm -f "$tmp_script" "$tmp_checksums"
        return 1
    fi

    chmod +x "$tmp_script"
    mv "$tmp_script" "$install_path"
    rm -f "$tmp_checksums"
    print_green "  ✓  Updated to $(sup --version)"
}
```

### Anti-Loop

If `SUP_NO_SELF_UPDATE=1` is set (env var), skip the check entirely. This prevents infinite loops if a CI system or script calls `sup`.

---

## 12. Network Connectivity

### Pre-Flight Check (Warn, Don't Block)

```bash
check_network() {
    if ! curl -sI --max-time 5 "https://github.com" >/dev/null 2>&1; then
        print_yellow "  ⚠  No internet connection detected. Most updates require network access."
        print_yellow "     Some tools may fail. Continuing anyway..."
        echo ""
        NETWORK_AVAILABLE=false
    else
        NETWORK_AVAILABLE=true
    fi
}
```

**Why warn instead of abort**: Some tools (oh-my-zsh via git pull on a cached repo, shell plugins) might work offline. Let them try. Failed tools will be caught by the collect-and-report pattern.

**Why github.com**: Most tool registries (npm, cargo, brew, pip) depend on GitHub. If GitHub is down, most updates fail anyway. Avoids false positives in environments where `google.com` is blocked.

---

## 13. Terminal Output & Branding

### Color Scheme

```bash
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

print_green()  { printf "${GREEN}%s${RESET}\n" "$1"; }
print_red()    { printf "${RED}%s${RESET}\n" "$1"; }
print_yellow() { printf "${YELLOW}%s${RESET}\n" "$1"; }
print_cyan()   { printf "${CYAN}%s${RESET}\n" "$1"; }
```

### Spinner (Correct Implementation)

The update runs in the background. The spinner runs in the foreground and polls the background process:

```bash
show_spinner_start() {
    local label="$1"
    printf "  ${CYAN}⠋${RESET}  Updating %s..." "$label"
}

spin_while() {
    local pid=$1
    local label="$2"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET}  Updating %s..." "${chars:i%${#chars}:1}" "$label"
        ((i++))
        sleep 0.1
    done
}

show_spinner_done() {
    local label="$1"
    local elapsed="$2"
    printf "\r  ${GREEN}✓${RESET}  %-30s ${DIM}(%ds)${RESET}\n" "$label" "$elapsed"
}

show_spinner_fail() {
    local label="$1"
    local elapsed="$2"
    printf "\r  ${RED}✗${RESET}  %-30s ${RED}FAIL${RESET} ${DIM}(%ds)${RESET}\n" "$label" "$elapsed"
}
```

### Banner

```bash
print_banner() {
    printf "${CYAN}"
    cat << 'BANNER'

  ███████╗██╗   ██╗██████╗
  ██╔════╝██║   ██║██╔══██╗
  ███████╗██║   ██║██████╔╝
  ╚════██║██║   ██║██╔═══╝
  ███████║╚██████╔╝██║
  ╚══════╝ ╚═════╝ ╚═╝
BANNER
    printf "${RESET}"
    printf "  One Command. Everything Updated.    ${DIM}v%s${RESET}\n" "$SUP_VERSION"
    printf "  ${DIM}by zayd${RESET}\n"
    printf "  ─────────────────────────────────────────\n\n"
}
```

---

## 14. CLI Interface

### Zero-Argument Default

```bash
sup                    # Full waterfall: detect → confirm → update → summarize
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `sup config` | Open interactive preferences menu |

### Flags

| Flag | Description |
|------|-------------|
| `--help` | Print usage information |
| `--version` | Print version (`sup v1.0.0`) |
| `--self-update` | Update sup itself (with checksum verification) |
| `--skip <tool>` | Skip a specific tool for this run. Repeatable: `--skip homebrew --skip apt` |
| `--only <tool>` | Update only a specific tool (e.g., `--only claude`). Repeatable. |
| `--list` | List all supported tools and their detection status |
| `--yes` | Skip the confirmation prompt (for scripts/CI) |
| `--no-cleanup` | Skip cleanup commands (brew cleanup, apt autoremove) |
| `--dry-run` | Show what would be updated without running anything |
| `--verbose` | Print each command before execution |

### Flag Conflicts

- `--only` and `--skip` can both be repeated: `sup --only claude --only ollama` or `sup --skip brew --skip apt`.
- If `--only` and `--skip` conflict on the same tool (e.g., `sup --only claude --skip claude`), `--skip` wins (most restrictive).
- `--dry-run` and `--yes` are mutually exclusive. `--dry-run` takes priority (nothing runs).

### --dry-run Output

```
  SUP — Dry Run
  ─────────────────────────────────────────

  Would update:
    1. Homebrew           brew update && brew upgrade
    2. Rustup             rustup update
    3. uv                 uv self update
    4. npm globals        npm update -g
    5. Claude Code        claude update
    ...

  14 tools would be updated. 0 require sudo.
  No changes were made.
```

### --list Output

```
  SUP — Supported Tools
  ─────────────────────────────────────────

  INSTALLED:
    ✓  Homebrew           brew 4.4.17
    ✓  Rustup             rustup 1.28.1
    ✓  uv                 uv 0.6.3
    ✓  npm                npm 10.9.2
    ✓  Claude Code        claude 1.0.21
    ✓  Gemini CLI         gemini 0.1.12
    ✓  Ollama             ollama 0.6.1

  NOT FOUND:
    ·  apt                (Linux only)
    ·  Snap               (Linux only)
    ·  Flatpak            (Linux only)
    ·  Conda
    ·  Deno

  Total: 7 installed, 49 supported
```

---

## 15. Distribution & Installation

### Channel 1: curl | bash (Primary)

```bash
curl -fsSL https://raw.githubusercontent.com/zaydiscold/sup/main/install.sh | bash
```

**What `install.sh` does:**

1. Check if running as root (warn: "Running as root is not recommended")
2. Detect OS (`uname -s` → Darwin or Linux)
3. Detect architecture (`uname -m` → x86_64 or arm64)
4. Check for Bash 4+ (if macOS with 3.2, print install instructions and exit)
5. Download `sup.sh` to a temp file
6. Verify SHA-256 checksum against published checksums
7. Move to `~/.local/bin/sup` and `chmod +x`
8. Check if `~/.local/bin` is in `$PATH`
9. **If not in PATH**: ask the user before modifying any shell config

```
  ~/.local/bin is not in your PATH.

  Add it to your shell config? [Y/n]
    → Will append to: /Users/you/.zshrc
```

10. Print success message with the ASCII banner

**For security-conscious users** (two-step alternative):

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/zaydiscold/sup/main/install.sh
less install.sh       # Review it
bash install.sh       # Run it
```

### Channel 2: Homebrew

```bash
brew install zaydk/tap/sup
```

Requires a `zaydk/homebrew-tap` repository with the formula. Straightforward for discoverability.

### Channel 3: npm (Thin Wrapper)

```bash
npm install -g @zaydiscold/sup
```

Wrapper `package.json` with `"bin": { "sup": "./sup.sh" }`. Gives access to Node developers, but the curl installer is recommended.

### Channel 4: Direct Download

```bash
curl -fsSL -o sup.sh https://github.com/zaydiscold/sup/releases/latest/download/sup.sh
chmod +x sup.sh
mv sup.sh ~/.local/bin/sup
```

For users who don't trust piping curl to bash.

---

## 16. Repository Structure

```
sup/
│
├── sup.sh                      # The tool (single file, ~1200-1500 lines)
├── install.sh                  # curl|bash installer (~100 lines)
├── VERSION                     # Single line: "1.0.0" (for self-update check)
│
├── README.md                   # GitHub README
├── LICENSE                     # MIT
├── CHANGELOG.md                # keep-a-changelog format
├── CONTRIBUTING.md             # How to add new tools (the 4-piece pattern)
├── REGISTRY.md                 # Full supported tools list for humans
│
├── Formula/
│   └── sup.rb                  # Homebrew formula
│
├── package.json                # npm distribution wrapper
│
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── new_tool_request.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── lint.yml            # ShellCheck on every PR
│       └── release.yml         # Auto-publish on tag push (+ checksums.txt)
│
└── assets/
    └── demo.gif                # Terminal recording for README
```

### release.yml Responsibilities

On tag push (e.g., `v1.1.0`):
1. Run ShellCheck on `sup.sh`
2. Generate `checksums.txt` containing SHA-256 of `sup.sh`
3. Create GitHub Release with `sup.sh` and `checksums.txt` as assets
4. Update the `VERSION` file on main branch

---

## 17. Future Roadmap

### v1.1 — Deferred from v1 + Polish

The following were researched for v1 but deferred because they lack a reliable non-interactive update path or require shell-context tricks that are fragile from Bash:

- **Cursor extensions**: Cursor CLI does not support `--update-extensions`. Awaiting a stable extension management command.
- **zinit**: Zsh-only function, cannot be reliably invoked from Bash without loading the user's full `.zshrc`.
- **Yarn**: Classic is frozen at 1.22.22; Berry is per-project with no global update; corepack is being removed from Node.js. Homebrew covers the only valid case.
- **pip self-update**: System Python detection (`EXTERNALLY-MANAGED`, `/usr/bin/pip`) is fragile and the consequences of getting it wrong (broken system Python) are severe. uv and pipx cover Python tooling safely. Scope for v1.1: re-add pip with `check_pip()` safety gates (EXTERNALLY-MANAGED marker, `/usr/lib/python*/` path check, pyenv/venv detection).

Additional v1.1 features:
- `--interactive` flag: TUI mode with arrow keys and toggle selection (using `gum` or `fzf` if installed)
- `--quiet` flag: suppress all output except errors
- `--json` flag: machine-readable output for scripting
- Ollama model updates (`ollama list` → `ollama pull` each)
- Docker image updates (`docker images --format` → `docker pull` each)
- Display elapsed time per step (refinement of v1's basic timing)

### v2.0 — Go Rewrite
- Rewrite in Go for a single compiled binary
- Bubble Tea TUI as the default experience
- Parallel updates (non-conflicting tools update simultaneously)
- Plugin system: users can add custom tool definitions
- Remote SSH updates (like topgrade's `remote_topgrades`)

### v2.x — Platform
- Windows support (PowerShell script)
- Auto-scheduling: `sup --schedule` adds a weekly cron/launchd job
- Community registry: pull new tool definitions from a central repo

---

## 18. Appendices

### Appendix A: Adding a New Tool

To contribute a new tool to `sup`, add the following to `sup.sh`:

```bash
# 1. Add to STEP_ORDER array (in the right tier position)
STEP_ORDER=(
    ...
    "newtool"
    ...
)

# 2. Add metadata
STEP_OS[newtool]="darwin,linux"     # or "darwin" or "linux" or "all"
STEP_RISK[newtool]="safe"           # or "warn"
STEP_SUDO[newtool]="no"             # or "yes"
STEP_LABEL[newtool]="New Tool"      # Display name
STEP_TIMEOUT[newtool]=60             # Seconds

# 3. Add check function
check_newtool() {
    command -v newtool &>/dev/null
}

# 4. Add update function
update_newtool() {
    newtool update
}
```

Five pieces. Submit a PR.

### Appendix B: Timeout Strategy

Every update command has a tier-based timeout:

| Tier | Timeout | Rationale |
|------|---------|-----------|
| System package managers (brew, apt) | 300s (5 min) | Can download hundreds of packages |
| Language tools (rustup, npm, pipx) | 120s (2 min) | Usually fast, occasionally heavy |
| AI tools (claude, ollama, gemini) | 120s (2 min) | Download-dependent |
| Developer CLIs (vercel, firebase) | 60s (1 min) | Small updates |
| Editor extensions (code, codium) | 60s (1 min) | Usually fast |
| Shell frameworks (oh-my-zsh) | 30s | Just a git pull |

If a command hits its timeout, it is killed (SIGTERM) and classified as a "Timeout" error with exit code 124.

### Appendix C: Signal Handling

`sup` traps SIGINT and SIGTERM for clean exit:

```bash
declare -a TEMP_FILES=()

cleanup_and_exit() {
    printf "\n"
    print_yellow "  Interrupted. Cleaning up..."
    # Remove only tracked temp files
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f" 2>/dev/null
    done
    # Kill any background update process (portable — no GNU xargs -r)
    local pids
    pids=$(jobs -p 2>/dev/null)
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null
    fi
    # Show partial summary if any updates completed
    if [[ ${#RESULTS[@]} -gt 0 ]]; then
        print_summary
    fi
    exit 130
}

trap cleanup_and_exit SIGINT SIGTERM
```

Temp files are tracked in an array and only those files are cleaned up — no unsafe glob patterns on `/tmp`.

### Appendix D: Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All updates succeeded (or nothing to update) |
| 1 | One or more updates failed (see summary) |
| 3 | Bash version too old (< 4.0) |
| 130 | Interrupted by user (Ctrl+C) |

**Note**: There is no exit code for "no internet." Since the network check warns but continues, the exit code reflects update outcomes (0 = all OK, 1 = some failed). If network is down and all tools fail, exit code is 1.

### Appendix E: Testing Strategy

**Linting**: ShellCheck runs on every PR via GitHub Actions. All warnings must be clean.

**Unit tests**: Key functions (version comparison, error classification, OS detection, install-method detection) are testable with BATS (Bash Automated Testing System).

**Integration tests**: Docker containers with various tool combinations installed. Test matrix:
- macOS (via GitHub Actions macOS runner)
- Ubuntu (Docker)
- Fedora (Docker)
- Minimal container (only bash + curl)

**Manual verification**: Each new tool entry must include a screen recording or log of a successful update on at least one platform.

### Appendix F: Positioning vs topgrade

| | **sup** | **topgrade** |
|---|---|---|
| Language | Bash (readable, auditable) | Rust (compiled binary) |
| Config | Zero by default, opt-in preferences | TOML file with 100+ options |
| Install | `curl \| bash` one-liner | cargo/brew/pip/winget |
| AI tools | Claude, Gemini, Ollama, Goose, Amazon Q, Aider, Open Interpreter, HuggingFace, Copilot, Codex (10) | Claude only (1) |
| uv auto-install | Installs uv if missing for faster Python updates | No equivalent |
| Target user | Everyone | Power users |
| Steps | 49 curated | 180+ (many niche) |
| Approach | Curated & safe | Exhaustive & configurable |
| Contributing | 5 pieces of Bash | Learn Rust, add enum variant, wire runner |

### Appendix G: v1 Reliability Checklist

Every tool and code path in v1 has been validated against these gates. Any entry that cannot satisfy all three is deferred to v1.1+.

**Gate 1 — Non-Interactive**: The update command must complete without any stdin prompts. If a tool requires user input mid-update, it must have a `-y`, `--non-interactive`, or equivalent flag, or it is excluded.

**Gate 2 — Platform-Safe Syntax**: No GNU-only flags (`xargs -r`, `sort -V`, `timeout`) without a portable fallback. All commands must work on both macOS (BSD userland) and Linux (GNU userland) without installing additional dependencies.

**Gate 3 — Fallback/Skip Path**: Every tool entry must have a `check_<name>` function that silently returns `1` if the tool is not installed or not in the expected state. No tool should error during detection. If the update path is ambiguous (e.g., multiple install methods), install-method detection must resolve to a single command or skip.

**Deferred in v1 for failing these gates:**

| Tool | Gate Failed | Reason |
|------|------------|--------|
| Cursor extensions | Gate 1, 2 | No `--update-extensions` CLI flag exists |
| zinit | Gate 2 | Zsh function, cannot be invoked reliably from Bash |
| Yarn | Gate 3 | Classic frozen, Berry per-project, corepack being removed — no reliable path |
| pip self-update | Gate 3 | System Python detection is fragile; wrong = broken system. uv/pipx cover this. |

**Hardened in v1 (were previously failing):**

| Item | Fix Applied |
|------|------------|
| `xargs -r` in signal handler | Replaced with portable Bash loop |
| `sort -V` in version comparison | Replaced with pure-Bash `version_gt` |
| `print` (not a Bash builtin) | Replaced with `printf` |
| `run_with_timeout` killing `$$` | Replaced with child-PID-only kill |
| `asdf update` (removed in v0.16) | Changed to `asdf plugin update --all` only |
| `softwareupdate` locale-dependent grep | Added `LANG=C` and negative matching |
| oh-my-zsh `$ZSH` unset in Bash | Explicitly set path before invocation |
| `compute_sha256` silent failure | Now returns non-zero when no hash tool found |
| `self_update` overwrites brew-managed binary | Detects brew ownership, redirects to `brew upgrade` |
| `detect_install_method` substring collisions | Uses package-name mapping and word-boundary matching |
| Missing `classify_error`, `warn_and_confirm`, `ensure_sudo`, `print_summary` | Defined with complete implementations |
| Backgrounded subshell can't write parent arrays | Error reasons written to files, read by parent after `wait` |
| Log directory may not exist | `mkdir -p` at startup |

---

*End of specification. This document is the complete blueprint for building `sup` v1.0.0.*

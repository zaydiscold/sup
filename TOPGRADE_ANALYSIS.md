# Topgrade Deep Dive: Architecture Analysis for "sup"

> Comprehensive reverse-engineering of [topgrade-rs/topgrade](https://github.com/topgrade-rs/topgrade) v16.9.0
> Purpose: Inform the design of `sup`, a Bash-based system updater

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Step System](#2-the-step-system)
3. [The Runner & Execution Engine](#3-the-runner--execution-engine)
4. [Detection Patterns](#4-detection-patterns)
5. [Sudo Handling](#5-sudo-handling)
6. [Error Handling & Retry Logic](#6-error-handling--retry-logic)
7. [Self-Update Mechanism](#7-self-update-mechanism)
8. [Dry Run System](#8-dry-run-system)
9. [Config System](#9-config-system)
10. [Cleanup Patterns](#10-cleanup-patterns)
11. [Distribution Channels](#11-distribution-channels)
12. [Complete Step List (180+ tools)](#12-complete-step-list)
13. [Smart Tricks Worth Stealing](#13-smart-tricks-worth-stealing)
14. [Bash Adaptation Patterns](#14-bash-adaptation-patterns)

---

## 1. Architecture Overview

### High-Level Flow

```
main() → run()
  ├── Parse CLI args (clap)
  ├── Load config (TOML, layered: file + CLI + env)
  ├── Detect sudo binary (doas/sudo/pkexec/run0/please)
  ├── Build ExecutionContext (run_type, sudo, config, distribution)
  ├── Build Runner (holds context + report vector)
  ├── Run SelfUpdate step FIRST (before anything else)
  ├── Optionally pre-elevate sudo (cache credentials)
  ├── Run pre_commands from config
  ├── Loop through default_steps() → step.run(&mut runner, &ctx)
  ├── Print summary report
  ├── Run post_commands from config
  ├── Optional: keep-at-end prompt (Reboot/Shell/Quit)
  └── Desktop notification on completion
```

### Key Design Principle: Sequential, Not Parallel

Topgrade runs steps **sequentially**. There is no parallelism. This is intentional:
- Package managers can conflict (apt lock files, brew locks)
- Output would be interleaved and unreadable
- Error recovery is simpler
- Sudo credential caching works linearly

**Bash adaptation**: This is perfect for us. Sequential is natural in Bash.

### The Four Core Abstractions

| Abstraction | Rust Type | Purpose |
|---|---|---|
| **Step** | `enum Step` (180 variants) | Declares what CAN be updated |
| **Runner** | `struct Runner` | Executes steps, collects results |
| **ExecutionContext** | `struct ExecutionContext` | Carries config, sudo, run_type across all steps |
| **Executor** | `enum Executor` | Wraps Command to support Wet/Dry/Damp modes |

---

## 2. The Step System

### How Steps Are Defined

Every updatable tool is a variant in a single `Step` enum (180+ variants):

```rust
pub enum Step {
    AM, AndroidStudio, AppMan, Aqua, Asdf, Atom, Atuin,
    BrewCask, BrewFormula, Bun, Cargo, Chezmoi, Chocolatey,
    ClaudeCode, Conda, Containers, Cursor, Deno, Flatpak,
    Firmware, Go, Nix, Node, Pip3, Pipx, Rustup, Snap,
    System, Vim, Vscode, Winget, Yarn, ...
}
```

### How Steps Are Ordered

The function `default_steps()` returns a `Vec<Step>` with a carefully curated order:

1. **Remotes** first (SSH into other machines)
2. **System-level** package managers (apt, dnf, pacman, brew, winget)
3. **Secondary** package managers (snap, flatpak, nix)
4. **Shell plugins** (oh-my-zsh, fisher, etc.)
5. **Language-specific** (rustup, cargo, npm, pip, go, etc.)
6. **Editor plugins** (vim, vscode, jetbrains)
7. **Git repos** pull
8. **Custom commands** (user-defined, always last)

Platform-specific steps use `#[cfg(target_os = "linux")]` compile-time gates.

**Bash adaptation**: Use an ordered array of function names. Platform detection via `uname`.

```bash
# Step ordering in bash
STEPS=(
    step_system        # apt/dnf/pacman/brew
    step_snap
    step_flatpak
    step_brew_cask
    step_shell_plugins # oh-my-zsh, fisher
    step_rustup
    step_cargo
    step_node
    step_pip
    step_go
    step_editors       # vim, vscode
    step_git_repos
    step_custom
)
```

### How Steps Dispatch

Each Step variant has a `run()` method that calls `runner.execute()`:

```rust
impl Step {
    pub fn run(&self, runner: &mut Runner, ctx: &ExecutionContext) -> Result<()> {
        match *self {
            Step::Cargo => runner.execute(*self, "cargo", || generic::run_cargo_update(ctx))?,
            Step::BrewFormula => runner.execute(*self, "Brew", || unix::run_brew_formula(ctx, BrewVariant::Path))?,
            // ...
        }
        Ok(())
    }
}
```

The actual update logic lives in module functions like `generic::run_cargo_update()`.

---

## 3. The Runner & Execution Engine

### Runner Structure

```rust
pub struct Runner<'a> {
    ctx: &'a ExecutionContext<'a>,
    report: Vec<(Cow<'a, str>, StepResult)>,
}
```

The runner is the heart of the system. It:
1. Takes a step name and a closure
2. Calls the closure
3. Handles errors, retries, skips
4. Records the result for the summary report

### StepResult Variants

```rust
pub enum StepResult {
    Success,          // Step ran and succeeded
    Failure,          // Step ran and failed
    Ignored,          // Step failed but ignore_failure was set
    SkippedMissingSudo,  // Step needed sudo but none found
    Skipped(String),  // Step skipped (tool not installed, etc.)
}
```

### The Execute Loop (Retry Logic)

```
runner.execute(step, key, func):
  max_attempts = 1 + config.auto_retry()   // default: 1 attempt total

  loop:
    match func():
      Ok(()) → push Success, break
      Err(DryRun) → break (silently)
      Err(MissingSudo) → push SkippedMissingSudo, break
      Err(SkipStep) → push Skipped (if verbose), break
      Err(other):
        if interrupted → always prompt user
        elif has_auto_retries_left → increment attempt, continue (no prompt)
        elif ignore_failure → push Ignored, break (no prompt)
        elif config.ask_retry → prompt user (Retry/Quit/Continue)
        else → push Failure, break
```

**This is brilliant.** The retry system has three layers:
1. **Auto-retry** (silent, configurable count)
2. **Interactive retry** (ask user on failure)
3. **Ignore-failure** (never prompt, just log)

**Bash adaptation**:

```bash
run_step() {
    local name="$1" func="$2"
    local max_attempts=$((1 + AUTO_RETRY))
    local attempt=1

    while true; do
        if output=$("$func" 2>&1); then
            RESULTS+=("$name:success")
            return 0
        fi

        if ((attempt < max_attempts)); then
            ((attempt++))
            continue
        fi

        if [[ "$ASK_RETRY" == "true" ]]; then
            read -rp "[$name] failed. (R)etry, (C)ontinue, (Q)uit? " choice
            case "$choice" in
                r|R) continue ;;
                q|Q) RESULTS+=("$name:failure"); return 1 ;;
                *)   RESULTS+=("$name:failure"); return 0 ;;
            esac
        else
            RESULTS+=("$name:failure")
            return 0
        fi
    done
}
```

---

## 4. Detection Patterns

### The `require()` / `which()` Pattern

Topgrade uses a two-tier detection system:

```rust
// Soft check - returns Option<PathBuf>
pub fn which(binary_name: T) -> Option<PathBuf> {
    match which_crate::which(&binary_name) {
        Ok(path) => Some(path),
        Err(_) => None,
    }
}

// Hard check - returns Result, emits SkipStep on failure
pub fn require(binary_name: T) -> Result<PathBuf> {
    match which_crate::which(&binary_name) {
        Ok(path) => Ok(path),
        Err(_) => Err(SkipStep("Cannot find X in PATH")),
    }
}
```

Every step function starts with `require()`:

```rust
pub fn run_cargo_update(ctx: &ExecutionContext) -> Result<()> {
    let cargo_dir = env::var_os("CARGO_HOME")
        .map_or_else(|| HOME_DIR.join(".cargo"), PathBuf::from)
        .require()?;                    // ← directory must exist
    require("cargo")?;                  // ← binary must be in PATH
    let toml_file = cargo_dir.join(".crates.toml").require()?; // ← file must exist
    // ...
}
```

The `require()` call returns `Err(SkipStep)` which the runner catches and silently skips.

### Path Existence Checks

```rust
pub trait PathExt {
    fn if_exists(self) -> Option<Self>;  // Returns Some if exists, None otherwise
    fn require(self) -> Result<Self>;    // Returns Ok if exists, Err(SkipStep) otherwise
}
```

### require_one() for alternatives

```rust
pub fn require_one(binary_names: impl IntoIterator) -> Result<PathBuf> {
    // Try each binary, return the first one found
    // If none found, emit SkipStep listing all tried binaries
}
```

**Bash adaptation**:

```bash
require() {
    command -v "$1" >/dev/null 2>&1 || { skip "$1 not found"; return 1; }
}

require_one() {
    for bin in "$@"; do
        command -v "$bin" >/dev/null 2>&1 && return 0
    done
    skip "None of [$*] found"
    return 1
}

require_dir() {
    [[ -d "$1" ]] || { skip "Directory $1 not found"; return 1; }
}

require_file() {
    [[ -f "$1" ]] || { skip "File $1 not found"; return 1; }
}
```

---

## 5. Sudo Handling

### Detection Order

```rust
// Unix
const DETECT_ORDER: [SudoKind; 5] = [Doas, Sudo, Pkexec, Run0, Please];

// Windows
const DETECT_ORDER: [SudoKind; 2] = [Gsudo, WinSudo];
```

It tries each in order, uses the first one found. This is configurable in TOML.

### SudoKind Variants

| Kind | Binary | Platform | Notes |
|------|--------|----------|-------|
| `Doas` | `doas` | Unix | OpenBSD-style, no credential caching |
| `Sudo` | `sudo` | Unix | Standard, supports `-v` for caching |
| `Pkexec` | `pkexec` | Unix | PolicyKit, graphical prompt |
| `Run0` | `run0` | Unix | systemd-based, uses polkit |
| `Please` | `please` | Unix | Supports `-w` for credential warming |
| `Gsudo` | `gsudo` | Windows | Third-party sudo for Windows |
| `WinSudo` | `sudo.exe` | Windows | Windows 11 native sudo |
| `Null` | (none) | Any | No-op when already running as root |

### Pre-Elevation Pattern

Topgrade optionally elevates sudo BEFORE running steps. This caches credentials so the user isn't prompted mid-run:

```rust
// In main, before running steps:
if config.pre_sudo() {
    if let Some(sudo) = ctx.sudo() {
        sudo.elevate(&ctx)?;
    }
}
```

The `elevate()` method runs a dummy command to trigger the password prompt:

```rust
pub fn elevate(&self) -> Result<()> {
    match self.kind {
        SudoKind::Sudo   => cmd.arg("-v"),          // validate/extend timeout
        SudoKind::Doas   => cmd.arg("echo"),         // dummy command
        SudoKind::Please => cmd.arg("-w"),           // warm token
        SudoKind::Gsudo  => cmd.args(["-d", "cmd.exe", "/c", "rem"]),
        // ...
    }
}
```

### Sudo Execute with Options

```rust
pub struct SudoExecuteOpts {
    pub login_shell: bool,        // -i for sudo
    pub preserve_env: PreserveEnv, // -E or --preserve-env=LIST
    pub set_home: bool,           // -H for sudo
    pub user: Option<&str>,       // -u USER
}
```

**Bash adaptation**:

```bash
detect_sudo() {
    for cmd in doas sudo pkexec run0 please; do
        if command -v "$cmd" >/dev/null 2>&1; then
            SUDO_CMD="$cmd"
            return 0
        fi
    done
    SUDO_CMD=""
    return 1
}

pre_elevate() {
    [[ -z "$SUDO_CMD" ]] && return
    case "$SUDO_CMD" in
        sudo)   $SUDO_CMD -v ;;
        doas)   $SUDO_CMD echo >/dev/null ;;
        please) $SUDO_CMD -w ;;
        *)      $SUDO_CMD echo >/dev/null ;;
    esac
}

run_sudo() {
    [[ -z "$SUDO_CMD" ]] && { warn "No sudo available, skipping"; return 1; }
    $SUDO_CMD "$@"
}
```

---

## 6. Error Handling & Retry Logic

### Error Type Hierarchy

Topgrade uses typed errors for flow control:

| Error Type | Meaning | Runner Behavior |
|---|---|---|
| `SkipStep(reason)` | Tool not installed / not applicable | Skip silently (or log if verbose) |
| `MissingSudo` | Step needs sudo, none available | Mark `SkippedMissingSudo` |
| `DryRun` | In dry-run mode | Skip silently |
| `StepFailed` | At least one step failed | Set exit code to non-zero |
| `TopgradeError::ProcessFailed` | A command returned non-zero | Trigger retry logic |
| `TopgradeError::ProcessFailedWithOutput` | Non-zero + captured stderr | Trigger retry with error display |

### Command Extension Pattern

Every command execution goes through `CommandExt`:

```rust
pub trait CommandExt {
    fn status_checked(&mut self) -> Result<()>;      // run, check exit code
    fn output_checked(&mut self) -> Result<Output>;   // run, capture output, check exit code
    fn output_checked_utf8(&mut self) -> Result<Utf8Output>; // + decode UTF-8
}
```

On failure, the error message includes:
1. The full command with arguments (shell-escaped)
2. The exit status
3. Captured stdout/stderr (if using `output_checked`)

**Bash adaptation**:

```bash
run_checked() {
    local label="$1"; shift
    log_debug "Executing: $*"
    if output=$("$@" 2>&1); then
        return 0
    else
        local rc=$?
        log_error "[$label] Command failed (exit $rc): $*"
        [[ -n "$output" ]] && log_error "Output: $output"
        return $rc
    fi
}
```

### Auto-Retry Configuration

From the config TOML:
```toml
[misc]
auto_retry = 3        # Silently retry failed steps up to 3 times
ask_retry = true       # Prompt user after auto-retries exhausted
ignore_failures = ["pip3", "gem"]  # Never fail on these steps
```

---

## 7. Self-Update Mechanism

### How It Works

1. Runs as the VERY FIRST step (before all others)
2. Uses the `self_update` crate which queries GitHub Releases API
3. Downloads the correct binary for the current platform/target triple
4. Replaces the running binary
5. **Respawns itself** with the same arguments

```rust
pub fn self_update(ctx: &ExecutionContext) -> Result<()> {
    let result = Update::configure()
        .repo_owner("topgrade-rs")
        .repo_name("topgrade")
        .target(self_update_crate::get_target())
        .bin_name("topgrade")
        .current_version(cargo_crate_version!())
        .no_confirm(assume_yes)
        .build()?
        .update_extended()?;

    if result.updated() {
        print_info("Respawning...");
        let mut command = Command::new(current_exe?);
        command.args(env::args().skip(1))
               .env("TOPGRADE_NO_SELF_UPGRADE", "");
        // On Unix: exec() replaces the process
        // On Windows: spawn + exit with child's code
    }
}
```

Key details:
- Uses `TOPGRADE_NO_SELF_UPGRADE` env var to prevent infinite update loops
- Feature-gated behind `self-update` cargo feature
- Can be disabled via config: `no_self_update = true`

**Bash adaptation**:

```bash
self_update() {
    [[ -n "$SUP_NO_SELF_UPGRADE" ]] && return 0
    [[ "$NO_SELF_UPDATE" == "true" ]] && return 0

    local latest current script_path
    script_path="$(realpath "$0")"
    current="$VERSION"

    latest=$(curl -sL "https://api.github.com/repos/USER/sup/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"v\(.*\)".*/\1/')

    [[ "$latest" == "$current" ]] && { info "sup is up to date"; return 0; }

    info "Updating sup: $current → $latest"
    curl -sL "https://raw.githubusercontent.com/USER/sup/v$latest/sup" \
        -o "$script_path.new"
    chmod +x "$script_path.new"
    mv "$script_path.new" "$script_path"

    info "Respawning..."
    SUP_NO_SELF_UPGRADE=1 exec "$script_path" "$@"
}
```

---

## 8. Dry Run System

### Three Modes

| Mode | Enum | Behavior |
|---|---|---|
| **Wet** | `RunType::Wet` | Actually runs commands |
| **Dry** | `RunType::Dry` | Prints what would run, doesn't execute |
| **Damp** | `RunType::Damp` | Prints AND executes (verbose mode) |

### The `Executor` Enum

```rust
pub enum Executor {
    Wet(Command),     // Real execution
    Damp(Command),    // Print + execute
    Dry(DryCommand),  // Print only
}
```

### The `.always()` Escape Hatch

Detection commands (checking versions, querying config) must run even in dry mode:

```rust
// This runs even in --dry-run mode:
ctx.execute(&haxelib).always().arg("config").output_checked()
```

`.always()` converts a `Dry` executor to `Wet`.

**Bash adaptation**:

```bash
DRY_RUN=false

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

run_always() {
    # Always execute, even in dry-run (for detection)
    "$@"
}
```

---

## 9. Config System

### Config File Locations

- Linux/macOS: `~/.config/topgrade/topgrade.toml`
- macOS alt: `~/Library/Preferences/topgrade/topgrade.toml`
- Windows: `%APPDATA%/topgrade/topgrade.toml`

### Config Structure (from their example)

```toml
[misc]
pre_sudo = false           # Ask for sudo before starting
cleanup = true             # Run cleanup after updates
no_retry = false           # Disable retry prompts
no_self_update = false     # Disable self-update
assume_yes = true          # Auto-approve all prompts
auto_retry = 0             # Number of auto-retries
run_in_tmux = false        # Run inside tmux
set_title = true           # Set terminal title
display_time = true        # Show time for each step
notify_each_step = false   # Desktop notification per step
show_skipped = false       # Show skipped steps in summary

[pre_commands]
"My pre-command" = "echo 'Starting updates'"

[post_commands]
"Cleanup temp" = "rm -rf /tmp/junk"

[commands]
"Custom update" = "my-custom-update-script"

[git]
repos = ["~/projects/myrepo", "~/dotfiles"]
pull_predefined = true

[brew]
greedy_cask = true

[linux]
yay_arguments = "--nodiffmenu"
trizen_arguments = "--noconfirm"

[pip]
pip_review = false

[disable]
# Steps to completely skip:
system = true
snap = true

[ignore_failures]
# Steps where failures are OK:
cargo = true
pip3 = true
```

### Config Layering

1. Default values (compiled in)
2. Config file (`topgrade.toml`)
3. CLI arguments (override everything)
4. Environment variables

### Key Config Features

- **`[disable]`** section: Skip specific steps entirely
- **`[ignore_failures]`** section: Don't count as failures
- **`[commands]`** section: Add custom update commands
- **`[pre_commands]` / `[post_commands]`**: Run before/after all steps
- **`assume_yes`**: Pass `-y` to package managers
- **`cleanup`**: Run cleanup commands after updates

**Bash adaptation** (use a simple key=value file):

```bash
# ~/.config/sup/sup.conf
CLEANUP=true
AUTO_RETRY=2
ASK_RETRY=true
ASSUME_YES=false
PRE_SUDO=true
DISABLED_STEPS="snap flatpak"
IGNORE_FAILURES="pip cargo"
GIT_REPOS="~/dotfiles ~/projects/myrepo"
BREW_GREEDY=true
```

```bash
load_config() {
    local config="${XDG_CONFIG_HOME:-$HOME/.config}/sup/sup.conf"
    [[ -f "$config" ]] && source "$config"
}
```

---

## 10. Cleanup Patterns

Topgrade runs cleanup commands when `cleanup = true` in config:

### Brew Cleanup
```rust
// After updating brew formulas:
if ctx.config().cleanup() {
    ctx.execute(&brew).args(["cleanup"]).status_checked()?;
}
```

### Cargo Cache Cleanup
```rust
if ctx.config().cleanup() {
    let cargo_cache = require("cargo-cache");
    if let Some(e) = cargo_cache {
        ctx.execute(e).args(["-a"]).status_checked()?;
    }
}
```

### APT Autoremove
```rust
// In the Linux distribution update:
if ctx.config().cleanup() {
    sudo.execute(ctx, "apt-get")?
        .args(["autoremove", "-y"])
        .status_checked()?;
}
```

### Pattern

Cleanup is always:
1. **Optional** (gated by config flag)
2. **After** the update step, not separate
3. **Non-fatal** (doesn't fail the step if cleanup fails)

**Bash adaptation**:

```bash
step_brew() {
    require brew || return 0
    separator "Homebrew"
    run brew update && run brew upgrade

    if [[ "$CLEANUP" == "true" ]]; then
        run brew cleanup --prune=7
        run brew autoremove
    fi
}
```

---

## 11. Distribution Channels

### How Topgrade Is Distributed

| Channel | Mechanism | Platform |
|---|---|---|
| **Cargo** | `cargo install topgrade` | All (source build) |
| **Homebrew** | `brew install topgrade` | macOS, Linux |
| **AUR** | `paru -S topgrade` | Arch Linux |
| **Nix** | `nix-env -iA topgrade` | NixOS, Linux, macOS |
| **Winget** | `winget install topgrade` | Windows |
| **Scoop** | `scoop install topgrade` | Windows |
| **Pip** | `pip install topgrade` (wrapper) | All |
| **Conda** | `conda install topgrade` | All |
| **GitHub Releases** | Pre-built binaries | All |
| **RPM** | via `cargo-generate-rpm` | Fedora/RHEL |
| **DEB** | via `cargo-deb` | Debian/Ubuntu |

### Self-Update via GitHub Releases

The `self_update` crate:
1. Queries `https://api.github.com/repos/topgrade-rs/topgrade/releases/latest`
2. Finds the asset matching the current target triple (e.g., `topgrade-v16.9.0-x86_64-unknown-linux-gnu.tar.gz`)
3. Downloads and extracts the binary
4. Replaces the running executable

### Cargo.toml Metadata for Packaging

```toml
[package.metadata.generate-rpm]
assets = [{ source = "target/release/topgrade", dest = "/usr/bin/topgrade" }]

[package.metadata.deb]
section = "utils"
assets = [
    "$auto",
    ["deployment/deb/topgrade.1", "usr/share/man/man1/", "644"],
    ["deployment/deb/topgrade.bash", "usr/share/bash-completion/completions/", "644"],
]
```

**Bash adaptation for sup**:

For a Bash script, distribution is simpler:
1. **curl pipe**: `curl -sL https://raw.githubusercontent.com/.../sup | bash` (installer)
2. **Homebrew tap**: Create a formula that downloads the script
3. **GitHub Releases**: Just the script file
4. **Self-update**: `curl` the latest version and replace self

---

## 12. Complete Step List

### System Package Managers
`System` (apt/dnf/pacman/zypper/apk), `BrewFormula`, `BrewCask`, `Macports`, `Chocolatey`, `Scoop`, `Winget`, `Snap`, `Flatpak`, `Pkg` (FreeBSD), `Pkgin`, `MicrosoftStore`, `Nix`, `Guix`, `HomeManager`

### Language Package Managers
`Cargo`, `Pip3`, `PipReview`, `PipReviewLocal`, `Pipupgrade`, `Pipx`, `Pipxu`, `Node` (npm), `Yarn`, `Pnpm`, `Bun`, `BunPackages`, `Deno`, `Go`, `Gem`, `RubyGems`, `Composer`, `Julia`, `Juliaup`, `Opam`, `Stack`, `Haxelib`, `Raco`, `Dotnet`, `Conda`, `Mamba`, `Pixi`, `Poetry`, `Uv`, `Rye`

### Version Managers
`Rustup`, `Asdf`, `Mise`, `Pyenv`, `Sdkman`, `Ghcup`, `Choosenim`, `Elan`, `Bob` (neovim), `Zigup`, `Zvm`

### Editor Plugins
`Vim`, `Emacs`, `Kakoune`, `Helix`, `HelixDb`, `Vscode`, `VscodeInsiders`, `Vscodium`, `VscodiumInsiders`, `Cursor`, `Atom`, `Micro`, `ClaudeCode`

### JetBrains IDEs (individual)
`JetbrainsToolbox`, `JetbrainsIdea`, `JetbrainsPycharm`, `JetbrainsWebstorm`, `JetbrainsGoland`, `JetbrainsClion`, `JetbrainsRider`, `JetbrainsRubymine`, `JetbrainsRustrover`, `JetbrainsDatagrip`, `JetbrainsDataspell`, `JetbrainsGateway`, `JetbrainsMps`, `JetbrainsPhpstorm`, `JetbrainsAqua`, `AndroidStudio`

### Shell Plugin Managers
`Shell` group: zr, antibody, antidote, antigen, zgenom, zplug, zinit, zi, zim, oh-my-zsh, oh-my-bash, fisher, bash-it, oh-my-fish, fish-plug, fundle

### DevOps/Cloud Tools
`Helm`, `Krew`, `Gcloud`, `Containers`, `Vagrant`, `Vcpkg`, `Aqua`, `Certbot`

### Linux-Specific
`AM`, `AppMan`, `DebGet`, `Distrobox`, `DkpPacman`, `Firmware` (fwupdmgr), `Flatpak`, `Gearlever`, `Lure`, `Mandb`, `Pacdef`, `Pacstall`, `Pkgfile`, `Protonup`, `Waydroid`, `AutoCpufreq`, `CinnamonSpices`, `ConfigUpdate`, `Restarts` (needrestart), `Toolbx`

### macOS-Specific
`Macports`, `Mas` (Mac App Store), `Sparkle`, `Xcodes`

### Windows-Specific
`Chocolatey`, `Scoop`, `Winget`, `MicrosoftStore`, `Wsl`, `WslUpdate`, `Miktex`

### Other
`Chezmoi`, `Yadm`, `Rcm`, `Myrepos`, `GitRepos`, `Sheldon`, `Tmux`, `Atuin`, `Bin`, `Stew`, `Fossil`, `Flutter`, `Falconf`, `Spicetify`, `GithubCliExtensions`, `ClamAvDb`, `PlatformioCore`, `Lensfun`, `Tldr`, `Tlmgr`, `Jetpack`, `Rtcl`, `Hyprpm`, `Maza`, `Pearl`, `Typst`, `Yazi`, `Powershell`, `CustomCommands`, `Remotes`, `VoltaPackages`, `SelfUpdate`

---

## 13. Smart Tricks Worth Stealing

### 1. The SkipStep Error Pattern

Instead of checking if a tool exists and then running it in two separate calls, they combine them. The step function calls `require()` at the top, which returns `Err(SkipStep)` if the tool isn't there. The runner catches `SkipStep` and silently moves on. This means:
- Zero overhead for tools you don't have
- No complex "should I run this?" logic in the main loop
- The step itself knows best what it needs

### 2. Pre-Sudo Credential Caching

Running `sudo -v` before all steps means the user enters their password once at the beginning, not randomly mid-way through. This is a huge UX improvement.

### 3. The Dry/Wet/Damp Executor

Three execution modes with one interface:
- `--dry-run`: See what would happen
- Normal: Just run
- `--damp`: See AND run (for debugging)

The `.always()` escape hatch is critical - detection commands must run even in dry mode.

### 4. Summary Report at End

Every step's result is recorded and printed in a final summary:
```
Summary
-------
✓ Brew
✓ Cargo
✗ pip3  ← failed
⊘ snap  ← skipped (not installed)
```

### 5. Breaking Changes Notification

When a major version bumps, topgrade shows breaking changes on first run and asks for confirmation. The state is tracked with a file.

### 6. Self-Update Then Respawn

Update self first, then `exec()` to replace the process with the new version, passing through all original arguments. The `TOPGRADE_NO_SELF_UPGRADE` env var prevents infinite loops.

### 7. The `require_one()` Pattern

For tools that might have multiple names (e.g., `python3` vs `python`), try each in order and use the first found.

### 8. Interrupt Handling

Ctrl+C during a step triggers the interactive retry prompt instead of killing the whole process. This lets users skip a slow step without aborting everything.

### 9. Custom Commands Integration

Users can add arbitrary commands to the config that run alongside the built-in steps:
```toml
[commands]
"Update my project" = "cd ~/project && git pull && make"
```

### 10. Config-Based Step Disabling

Instead of removing code, users disable steps in config:
```toml
[disable]
snap = true    # Never run snap updates
```

---

## 14. Bash Adaptation Patterns

### Core Architecture for `sup`

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
SCRIPT_PATH="$(realpath "$0")"

# ── Result tracking ──
declare -a RESULTS=()
FAILED=false

# ── Config defaults ──
CLEANUP=true
AUTO_RETRY=0
ASK_RETRY=true
ASSUME_YES=false
PRE_SUDO=true
DRY_RUN=false
SHOW_SKIPPED=false
DISABLED_STEPS=""
IGNORE_FAILURES=""

# ── Load config ──
load_config() {
    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/sup/sup.conf"
    [[ -f "$conf" ]] && source "$conf"
}

# ── Sudo detection ──
detect_sudo() {
    for cmd in doas sudo pkexec; do
        if command -v "$cmd" &>/dev/null; then
            SUDO_CMD="$cmd"; return 0
        fi
    done
    SUDO_CMD=""
}

# ── Detection helpers ──
require()     { command -v "$1" &>/dev/null || return 1; }
require_dir() { [[ -d "$1" ]] || return 1; }

# ── Execution helpers ──
run() {
    if $DRY_RUN; then
        echo "[dry] $*"
    else
        "$@"
    fi
}

run_sudo() {
    [[ -z "${SUDO_CMD:-}" ]] && return 1
    run $SUDO_CMD "$@"
}

# ── Runner ──
run_step() {
    local name="$1"; shift
    local func="$1"

    # Check if disabled
    [[ " $DISABLED_STEPS " == *" $name "* ]] && return 0

    local max=$((1 + AUTO_RETRY))
    local attempt=1
    local ignore=false
    [[ " $IGNORE_FAILURES " == *" $name "* ]] && ignore=true

    while true; do
        if "$func" 2>&1; then
            RESULTS+=("OK:$name")
            return 0
        fi

        if ((attempt < max)); then
            ((attempt++)); continue
        fi

        if $ignore; then
            RESULTS+=("IGNORED:$name"); return 0
        fi

        if $ASK_RETRY; then
            read -rp "[$name] failed. (R)etry/(C)ontinue/(Q)uit? " ch
            case "$ch" in
                r|R) continue ;;
                q|Q) RESULTS+=("FAIL:$name"); FAILED=true; return 1 ;;
            esac
        fi
        RESULTS+=("FAIL:$name"); FAILED=true; return 0
    done
}

# ── Step functions ──
step_brew() {
    require brew || return 1
    echo "═══ Homebrew ═══"
    run brew update && run brew upgrade
    $CLEANUP && run brew cleanup --prune=7 && run brew autoremove
}

step_apt() {
    require apt-get || return 1
    echo "═══ APT ═══"
    run_sudo apt-get update -qq
    run_sudo apt-get upgrade -y
    $CLEANUP && run_sudo apt-get autoremove -y
}

# ... more steps ...

# ── Summary ──
print_summary() {
    echo ""
    echo "═══ Summary ═══"
    for r in "${RESULTS[@]}"; do
        local status="${r%%:*}" name="${r#*:}"
        case "$status" in
            OK)      printf "  ✓ %s\n" "$name" ;;
            FAIL)    printf "  ✗ %s\n" "$name" ;;
            IGNORED) printf "  ~ %s\n" "$name" ;;
            SKIP)    $SHOW_SKIPPED && printf "  ⊘ %s\n" "$name" ;;
        esac
    done
}

# ── Main ──
main() {
    load_config
    detect_sudo

    $PRE_SUDO && [[ -n "${SUDO_CMD:-}" ]] && {
        echo "═══ Sudo ═══"
        $SUDO_CMD -v
    }

    # Ordered step execution
    run_step "brew"     step_brew
    run_step "apt"      step_apt
    run_step "snap"     step_snap
    # ... etc ...

    print_summary
    $FAILED && exit 1
    exit 0
}

main "$@"
```

### Key Differences from Topgrade to Embrace

| Topgrade (Rust) | sup (Bash) | Why |
|---|---|---|
| Compile-time `#[cfg]` platform gates | Runtime `uname` / `$OSTYPE` checks | Bash is interpreted |
| Typed error hierarchy | Return codes + convention | Keep it simple |
| TOML config with serde | `source` a key=value file | Zero dependencies |
| `self_update` crate for GitHub releases | `curl` + `mv` + `exec` | Shell native |
| `which` crate | `command -v` | Shell builtin |
| Executor enum (Wet/Dry/Damp) | `run()` function with `$DRY_RUN` check | Simpler |
| 180+ steps with individual functions | Start with ~30 most common | Grow organically |

---

## Summary of What to Steal

1. **SkipStep pattern** → `require` returns 1, caller returns 0
2. **Pre-sudo caching** → `sudo -v` at the start
3. **Three-tier retry** → auto-retry, then prompt, then ignore
4. **Summary report** → Track all results, print at end
5. **Self-update first** → Update self, then `exec` respawn
6. **Cleanup gating** → `$CLEANUP && brew cleanup`
7. **Config-based disable** → `DISABLED_STEPS="snap flatpak"`
8. **Dry-run mode** → `run()` wrapper function
9. **Custom commands** → Source user-defined commands from config
10. **Step ordering** → System first, language managers, editors, custom last

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `--interactive` TUI tool picker (gum -> fzf -> pure Bash fallback)
- `REGISTRY.md` with all 49 tool IDs and update metadata

### Changed
- Expanded `--list` version extraction coverage for more tools
- Updated docs usage examples for `--interactive`
- Fixed `.gitignore` to keep project markdown docs tracked

## [1.0.0] - 2026-03-03

### Added
- Initial release with 49 supported tools across 8 tiers
- System package managers: Homebrew, apt, Snap, Flatpak, Mac App Store, macOS System
- Language runtimes: Rustup, uv, pipx, Conda, Mamba, pyenv, asdf, mise
- Node.js ecosystem: npm globals, pnpm, Bun, Deno
- AI-native tools: Claude Code, Gemini CLI, Ollama, Goose, Amazon Q, Aider, Open Interpreter, HuggingFace CLI, GitHub Copilot, Codex CLI
- Developer CLIs: GitHub Extensions, Vercel, Firebase, Supabase, Railway, Fly.io, Wrangler, gcloud, Terraform
- Editors: VS Code Extensions, VS Code Insiders, VSCodium Extensions
- Shell frameworks: oh-my-zsh, oh-my-bash, fisher, tmux plugins
- Other: RubyGems, Composer, Cargo crates, Go binaries (gup)
- Install-method detection (Homebrew vs npm vs pipx vs uv vs native)
- Automatic uv installation for Python tool reliability
- Per-tool timeout with SIGTERM/SIGKILL grace period
- Automatic retry on transient failures
- Error classification (timeout, network, permission, conflict)
- Interactive configuration menu (`sup config`)
- Persistent preferences in `~/.config/sup/preferences`
- CLI flags: --help, --version, --self-update, --skip, --only, --list, --yes, --no-cleanup, --dry-run, --verbose
- Self-update with SHA-256 checksum verification
- Homebrew-managed installation detection (redirects to `brew upgrade`)
- curl|bash installer with checksum verification and PATH setup
- Run logging to `~/.local/share/sup/last.log`
- Colored terminal output with non-TTY fallback
- ASCII art banner with branding
- Signal handling (Ctrl+C) with partial summary and cleanup

[1.0.0]: https://github.com/zaydiscold/sup/releases/tag/v1.0.0

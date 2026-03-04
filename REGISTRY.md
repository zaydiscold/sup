# SUP Tool Registry

Human-readable registry of all supported tools in `sup.sh`.

`command` values are the effective update path used by the runner; some entries switch by install method (brew/npm/pipx/uv/native).

| ID | Command | OS | Sudo | Risk | Timeout (s) |
|---|---|---|---|---|---|
| `homebrew` | `brew update && brew upgrade` | darwin,linux | no | safe | 300 |
| `homebrew_cask` | `brew upgrade --cask` (adds `--greedy` when enabled) | darwin | no | safe | 300 |
| `apt` | `sudo apt-get update -qq && sudo apt-get upgrade -y` | linux | yes | safe | 300 |
| `snap` | `sudo snap refresh` | linux | yes | safe | 300 |
| `flatpak` | `flatpak update -y --noninteractive` | linux | no | safe | 300 |
| `mas` | `mas upgrade` | darwin | no | safe | 120 |
| `macos_system` | `softwareupdate -l` (check-only) | darwin | no | safe | 30 |
| `rustup` | `rustup update` | all | no | safe | 120 |
| `uv` | `uv self update` | all | no | safe | 60 |
| `pipx` | `pipx upgrade-all` | all | no | safe | 120 |
| `conda` | `conda update conda -y` | all | no | safe | 120 |
| `mamba` | `mamba update mamba -y` | all | no | safe | 120 |
| `pyenv` | `pyenv update` | darwin,linux | no | safe | 60 |
| `asdf` | `asdf plugin update --all` | darwin,linux | no | safe | 120 |
| `mise` | `mise self-update && mise upgrade` | darwin,linux | no | safe | 120 |
| `npm` | `npm update -g --no-fund --no-audit` | all | no | safe | 120 |
| `pnpm` | `pnpm self-update && pnpm update -g` | all | no | safe | 120 |
| `bun` | `bun upgrade --stable` (fallback `bun upgrade`) | all | no | safe | 60 |
| `deno` | `deno upgrade --quiet` | all | no | safe | 60 |
| `claude` | `brew upgrade claude-code` or `claude update` | all | no | safe | 120 |
| `gemini` | `brew upgrade gemini-cli` or `npm install -g @google/gemini-cli@latest` | all | no | safe | 60 |
| `ollama` | `brew upgrade ollama` or Linux installer (if enabled) | all | no | safe | 120 |
| `goose` | `brew upgrade block-goose-cli` / `brew upgrade --cask block-goose` / installer fallback (if enabled) | all | no | safe | 120 |
| `amazon_q` | `q update --non-interactive` | all | no | safe | 60 |
| `aider` | `uv tool install --force aider-chat@latest` or `pipx upgrade aider-chat` | all | no | safe | 120 |
| `open_interpreter` | `uv tool install --force open-interpreter@latest` or `pipx upgrade open-interpreter` | all | no | safe | 60 |
| `huggingface` | `uv tool install --force "huggingface_hub[cli]@latest"` or `pipx upgrade huggingface-hub` | all | no | safe | 60 |
| `copilot` | `gh extension upgrade gh-copilot` | all | no | safe | 60 |
| `codex` | `brew upgrade codex` or `npm install -g @openai/codex@latest` | all | no | safe | 60 |
| `gh_extensions` | `gh extension upgrade --all` | all | no | safe | 60 |
| `vercel` | `brew upgrade vercel-cli` or `npm install -g vercel@latest` | all | no | safe | 60 |
| `firebase` | `brew upgrade firebase-cli` or `npm install -g firebase-tools@latest` | all | no | safe | 60 |
| `supabase` | `brew upgrade supabase` or `npm install -g supabase@latest` | all | no | safe | 60 |
| `railway` | `brew upgrade railway` or `railway upgrade` | all | no | safe | 60 |
| `flyctl` | `flyctl version upgrade` | all | no | safe | 60 |
| `wrangler` | `npm install -g wrangler@latest` (npm-global install path) | all | no | safe | 60 |
| `gcloud` | `gcloud components update --quiet` | all | no | safe | 120 |
| `terraform` | `brew upgrade hashicorp/tap/terraform` or `brew upgrade terraform` | all | no | safe | 60 |
| `vscode` | `code --update-extensions` | all | no | safe | 60 |
| `vscode_insiders` | `code-insiders --update-extensions` | all | no | safe | 60 |
| `vscodium` | `codium --update-extensions` | all | no | safe | 60 |
| `ohmyzsh` | `DISABLE_UPDATE_PROMPT=true ZSH=... ~/.oh-my-zsh/tools/upgrade.sh` | darwin,linux | no | safe | 30 |
| `ohmybash` | `bash ~/.oh-my-bash/tools/upgrade.sh` (fallback git pull) | darwin,linux | no | safe | 30 |
| `fisher` | `fish -c 'fisher update'` | darwin,linux | no | safe | 30 |
| `tmux_plugins` | `~/.tmux/plugins/tpm/bin/update_plugins all` | darwin,linux | no | safe | 30 |
| `gem` | `gem update --system --no-document` | all | no | warn | 60 |
| `composer` | `composer self-update --no-interaction` | all | no | safe | 60 |
| `cargo_crates` | `cargo install-update -a` | all | no | safe | 120 |
| `go_binaries` | `gup update` | all | no | safe | 120 |

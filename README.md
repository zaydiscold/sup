![banner](./assets/banner.svg)

<!-- add signature.svg to ./assets/ -->

# sup

single command that updates every package manager and dev tool on your system.

![bash](./assets/badge-bash.svg)
![version](./assets/badge-version.svg)
![site](./assets/badge-site.svg)

[what it does](#what-it-does) | [install](#install) | [usage](#usage) | [what's inside](#whats-inside)

<br>

![·](./assets/stars1.svg)

<br>

## what it does

sup detects every package manager and developer tool on your machine and updates them all. one command. no config files. no dependencies beyond bash 4.

built this because running `brew update && brew upgrade && rustup update && npm update -g && pipx upgrade-all && ...` every morning was getting old. 49 tools. one word.

<br>

![·](./assets/stars2.svg)

<br>

## install

```bash
curl -fsSL https://raw.githubusercontent.com/zaydiscold/sup/main/install.sh | bash
```

or

```bash
brew install zaydiscold/tap/sup     # homebrew
```

or

```bash
npm install -g @zaydiscold/sup      # npm
```

or

```bash
curl -fsSL -o sup.sh https://github.com/zaydiscold/sup/releases/latest/download/sup.sh
chmod +x sup.sh
mv sup.sh ~/.local/bin/sup          # direct download
```

or

```bash
git clone https://github.com/zaydiscold/sup
```

note: requires bash 4+. macos ships 3.2 by default. run `brew install bash` first if you're on a mac.

<br>

![·](./assets/stars3.svg)

<br>

## usage

```
sup                              # detect + confirm + update everything
sup --list                       # show all 49 supported tools
sup --dry-run                    # show what would run, change nothing
sup --interactive                # tui picker (gum > fzf > builtin)
sup --only claude --only uv      # just these two
sup --skip homebrew              # everything except homebrew
sup --yes                        # skip confirmation (scripts/ci)
sup --self-update                # update sup itself (checksum verified)
sup --verbose                    # show commands as they run
sup config                       # preferences menu (type 1-7, enter)
```

`--skip` and `--only` are repeatable. `--skip` wins if both target the same tool. `--dry-run` overrides `--yes`.

`--interactive` opens a selector where you pick which tools to update. uses `gum choose --no-limit` if installed, falls back to `fzf --multi`, then to a pure bash arrow-key selector with space-to-toggle.

`sup config` is a numbered menu. lets you toggle cleanup, homebrew greedy casks, auto-retry, and a skip list. preferences save to `~/.config/sup/preferences`.

<br>

![·](./assets/stars4.svg)

<br>

## what's inside

![bash](./assets/badge-bash.svg)
![curl](./assets/badge-curl.svg)
![shellcheck](./assets/badge-shellcheck.svg)

<br>

single file. ~1700 lines. no external dependencies. works on macos and linux.

<br>

**49 tools across 8 tiers:**

<br>

**system** //
- homebrew, homebrew casks, apt, snap, flatpak, mac app store, macos system updates

<br>

**languages** //
- rustup, uv, pipx, conda, mamba, pyenv, asdf, mise

<br>

**node** //
- npm globals, pnpm, bun, deno

<br>

**ai tools** //
- claude code, gemini cli, ollama, goose, amazon q, aider, open interpreter, huggingface cli, github copilot, codex cli

<br>

**dev clis** //
- github extensions, vercel, firebase, supabase, railway, fly.io, wrangler, gcloud, terraform

<br>

**editors** //
- vs code extensions, vs code insiders, vscodium

<br>

**shell** //
- oh-my-zsh, oh-my-bash, fisher, tmux plugins

<br>

**other** //
- rubygems, composer, cargo crates, go binaries

<br>

each tool gets auto-detected, run with a timeout, auto-retried on transient failures, and classified on error. failures don't block other tools. the summary tells you what to fix manually.

self-update downloads from github releases and verifies sha-256 checksums before replacing the binary. if sup was installed via homebrew it redirects you to `brew upgrade sup`.

<br>

**exit codes**

| code | meaning |
|------|---------|
| 0 | everything updated successfully, or nothing needed updating |
| 1 | one or more tools failed to update. check the summary for details |
| 3 | bash version too old. requires 4.0+, macos ships 3.2 by default |
| 130 | interrupted by ctrl+c. cleanup runs automatically |

<br>

![·](./assets/stars5.svg)

<br>

[![star history chart](https://api.star-history.com/svg?repos=zaydiscold/sup&type=Date)](https://star-history.com/#zaydiscold/sup&Date)

mit. [license](./LICENSE)

<br>

![footer](./assets/footer.svg)

<sub>

- [x] 49 tools across 8 tiers
- [x] --interactive tui (gum / fzf / builtin)
- [ ] --json output for scripting
- [ ] ollama model updates
- [ ] docker image updates

</sub>

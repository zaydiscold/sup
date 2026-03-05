<p align="center">
  <img src="./assets/banner.svg" alt="sup" />
</p>

<!-- add signature.svg to ./assets/ -->

<h1 align="center">sup</h1>

<p align="center">single command that updates every package manager and dev tool on your system.</p>

<p align="center">
  <img src="https://img.shields.io/badge/bash-4.0+-B4A7D6?style=flat-square&labelColor=1a1a2e" alt="bash" />
  <img src="https://img.shields.io/badge/version-1.0.0-5F9EA0?style=flat-square&labelColor=1a1a2e" alt="version" />
  <img src="https://img.shields.io/badge/zayd.wtf-D4AF37?style=flat-square&labelColor=1a1a2e" alt="site" />
</p>

<p align="center">
  <a href="#what-it-does">what it does</a> · <a href="#install">install</a> · <a href="#usage">usage</a> · <a href="#whats-inside">what's inside</a>
</p>

<br>
<br>

<p align="center">
  <img src="./assets/stars1.svg" alt="·" />
</p>

<br>
<br>

## what it does

sup detects every package manager and developer tool on your machine and updates them all. one command. no config files. no dependencies beyond bash 4.

built this because running `brew update && brew upgrade && rustup update && npm update -g && pipx upgrade-all && ...` every morning was getting old. 49 tools. one word.

<br>
<br>

<p align="center">
  <img src="./assets/stars2.svg" alt="·" />
</p>

<br>
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
<br>

<p align="center">
  <img src="./assets/stars3.svg" alt="·" />
</p>

<br>
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
<br>

<p align="center">
  <img src="./assets/stars4.svg" alt="·" />
</p>

<br>
<br>

## what's inside

<p align="center">
  <img src="https://img.shields.io/badge/bash-B4A7D6?style=flat-square&labelColor=1a1a2e" alt="bash" />
  <img src="https://img.shields.io/badge/curl-5F9EA0?style=flat-square&labelColor=1a1a2e" alt="curl" />
  <img src="https://img.shields.io/badge/shellcheck-D4AF37?style=flat-square&labelColor=1a1a2e" alt="shellcheck" />
</p>

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
<br>

<p align="center">
  <img src="./assets/stars5.svg" alt="·" />
</p>

<br>
<br>

<p align="center">
  <a href="https://star-history.com/#zaydiscold/sup&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=zaydiscold/sup&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=zaydiscold/sup&type=Date" />
      <img src="https://api.star-history.com/svg?repos=zaydiscold/sup&type=Date&theme=dark" width="320" alt="star history chart" />
    </picture>
  </a>
</p>

<p align="center">mit. <a href="./LICENSE">license</a></p>

<br>
<br>

<p align="left"><strong>zayd / cold</strong></p>

<p align="center">
  <a href="https://zayd.wtf">zayd.wtf</a> · <a href="https://x.com/coldcooks">twitter</a> · <a href="https://github.com/zaydiscold">github</a>
  <br>
  <em>icarus only fell because he flew</em>
</p>

<p align="right">
  <strong>to do</strong><br>
  <sub>
  ☑ 49 tools across 8 tiers<br>
  ☑ --interactive tui (gum / fzf / builtin)<br>
  ☐ --json output for scripting<br>
  ☐ ollama model updates<br>
  ☐ docker image updates
  </sub>
</p>

<br>
<br>
<br>
<br>

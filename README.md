# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io), designed to run on several Macs at once — including
managed work machines where not everything can be installed. Shared configuration travels; machine-specific settings do
not.

## How the split works

At `chezmoi init` you pick a **profile** — `personal` or `work` — and answer a few questions. The answers live in
`~/.config/chezmoi/chezmoi.toml`, outside git, so nothing identifying is ever committed:

| Prompt                                 | Used for                                                                    |
|----------------------------------------|-----------------------------------------------------------------------------|
| Machine profile                        | `personal` / `work` — selects package manifests and profile-specific config |
| Git author name, Git email             | `~/.gitconfig` identity                                                     |
| SSH signing key path                   | commit and tag signing; leave blank to disable it entirely                  |
| Directory with a separate git identity | optional `includeIf` for one directory tree                                 |

Answers are re-used silently on later runs (`prompt*Once`); `chezmoi init
--prompt` forces them to be asked again.

Three layers, from most to least shared:

1. **This repository** — everything that should be identical everywhere.
2. **Profile branches** — `{{ if eq .profile "work" }}` inside templates, plus
   the encrypted `Brewfile.personal`.
3. **Local files, never committed** — `~/.zshrc.local` and `~/.gitconfig.local`.
   Sourced last, so they win over everything above.

The optional second git identity is not one of them: answer the `workdir` prompt
with the directory holding those repositories and chezmoi renders
`~/.gitconfig.extra` from the name, email and signing key it asks for next. git
merges it into `~/.gitconfig` for that tree only, and it carries nothing but
`[user]` — pager, aliases and the rest stay inherited.

## Bootstrap a new machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ospiem
```

This installs chezmoi into `./bin`, clones the repo, prompts for the profile and identity, then:

1. `run_once_before_00-install-homebrew` — installs Homebrew (on `work` it only prints instructions: installing needs
   admin rights that may not exist)
2. dotfiles are written into `$HOME`, and `.chezmoiexternal.toml` fetches the four zsh plugins pinned to exact commits
3. `run_onchange_after_20-go-tools` — `go install`s everything from `go-packages.txt`

Packages are **not** installed automatically. Review the manifest chezmoi just created and install when you are ready:

```bash
brew bundle                                                    # core: HOMEBREW_BUNDLE_FILE points at it
brew bundle --file=~/.config/homebrew/Brewfile.personal        # personal machines only
```

Afterwards, on a machine that needs them: create `~/.zshrc.local` /
`~/.gitconfig.local`, and generate a new signing key (Secure Enclave keys cannot be migrated — see below).

## Working from an existing checkout

The bootstrap one-liner clones into `~/.local/share/chezmoi`. To drive chezmoi from a checkout you already have, symlink
it there:

```bash
brew install chezmoi
ln -s ~/projects/ospiem/dotfiles ~/.local/share/chezmoi
chezmoi init          # writes ~/.config/chezmoi/chezmoi.toml, prompts once
chezmoi diff          # always sanity-check before the first apply
```

The symlink is what makes `chezmoi` commands work without `--source` every time; the package manifest does not depend on
it, since `HOMEBREW_BUNDLE_FILE` points at `~/.config/homebrew/Brewfile`, which chezmoi applies like any other target.

## What's managed

| Target                                             | Source                                                                                    |
|----------------------------------------------------|-------------------------------------------------------------------------------------------|
| `~/.zshrc`, `~/.zshenv`, `~/.zprofile`             | `dot_zshrc`, `dot_zshenv`, `dot_zprofile`                                                 |
| `~/.zsh/git-aliases.zsh`                           | `dot_zsh/git-aliases.zsh` (~30 git aliases)                                               |
| `~/.zsh/plugins/*`                                 | `.chezmoiexternal.toml` — fzf-tab, zsh-autosuggestions, fast-syntax-highlighting, fzf-git |
| `~/.gitconfig`                                     | `dot_gitconfig.tmpl` — identity, delta, rerere, autosquash, optional SSH signing          |
| `~/.config/git/ignore`                             | global gitignore (`core.excludesFile` is deliberately unset so git reads this path)       |
| `~/.config/git/attributes`                         | funcname diff drivers, `-diff` for lock files                                             |
| `~/.config/ripgrep/ripgreprc`                      | persistent rg flags; `.zshrc` points `RIPGREP_CONFIG_PATH` here                           |
| `~/.vimrc`                                         | `dot_vimrc` — fallback editor only; sources `defaults.vim` explicitly                     |
| `~/.config/kitty/`                                 | `kitty.conf`, `Catppuccin-Mocha.conf`, and `current-theme.conf` created once              |
| `~/.config/nvim/`                                  | kickstart-modular.nvim + `nvim-pack-lock.json` (see below)                                |
| `~/.config/zed/settings.json`                      | editor settings                                                                           |
| `~/.config/starship.toml`                          | Gruvbox Dark prompt                                                                       |
| `~/.config/atuin/config.toml`                      | shell history — local-only, secret filtering                                              |
| `~/.config/dotpak/config.toml.tmpl`                | [dotpak](https://github.com/ospiem/dotpak) backup config                                  |
| `~/.config/homebrew/Brewfile`                      | package manifest, created once then owned by the machine (see below)                      |
| `~/.config/homebrew/Brewfile.personal`             | personal extras, encrypted, personal profile only                                        |
| `go-packages.txt`                                  | Go CLI tools (installed with `@latest`)                                                   |

The Neovim config is [kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim) — a starting point
meant to be read and edited, not a distribution, so it lives in the source state as plain files (upstream's `.git`,
`README.md`
and CI furniture are left out; pull upstream changes by hand). Plugins come from Neovim's built-in `vim.pack`, which
needs 0.12+, and `nvim-pack-lock.json` — not `lazy-lock.json` — is what pins their versions across machines. The
`tree-sitter` CLI in the core Brewfile is a hard requirement: without it nvim-treesitter cannot build parsers.

The kitty theme is managed with the `create_` attribute: chezmoi writes
`current-theme.conf` only if it is missing, so `kitten themes` can keep rewriting it locally without a fight at the next
apply.

`dot_zshrc` is intentionally **not** a template — it contains aliases with literal `{{ }}` (docker `--format`) that
chezmoi would try to render. Anything machine-specific goes to `~/.zshrc.local`, not into a profile branch here.

Git is set up for a rebase-first workflow: `rerere` replays conflict resolutions, `rebase.autoSquash` picks up
`git commit --fixup` (aliased `gcf`), `fetch.prune` keeps remote-tracking refs honest, and `push.autoSetupRemote` makes
`git push` work on a fresh branch. Two things need the tools from the Brewfile: `git dft` runs a structural diff through
difftastic, and `Ctrl+G` opens the fzf-git pickers (`Ctrl+G Ctrl+B` branches, `Ctrl+F` files, `Ctrl+H` hashes,
`Ctrl+T` tags, `Ctrl+S` stashes, `Ctrl+R` remotes). Branch cleanup lives in `dot_zsh/git-aliases.zsh`: `gbda` deletes
what is merged into the default branch, `gbdg` deletes branches whose upstream is gone — that is the one that catches
squash merges.

### Deliberately unmanaged

`~/.config/git/allowed_signers` (per-machine keys), `~/.config/gh`,
`~/.config/mole`, `~/.claude`, `~/.config/raycast`, and everything dotpak already covers. Zsh completions and the
`vivid` colour cache under `~/.zsh/` are generated locally — `gen-completions` and `switch-theme` rebuild them.

`core.excludesFile` is unset on purpose, so a leftover `~/.gitignore_global`
from an older setup does nothing; delete it by hand if you still have one.

## Daily usage

```bash
chezmoi edit ~/.zshrc      # edit the source, not the live file
chezmoi diff               # what would change
chezmoi apply              # apply source state to $HOME
chezmoi re-add             # pull local edits back (skips templates by design)
chezmoi cd                 # jump into this repo to commit/push
```

### Packages

`~/.config/homebrew/Brewfile` carries the `create_` attribute: chezmoi writes it on the first apply and never touches it
again. That is deliberate — a work machine can delete the lines its policy forbids and `chezmoi apply` will not put them
back, and `chezmoi diff` stays quiet about it. The flip side is that manifest changes in this repo do not reach a machine
that already has the file; delete the local copy and re-apply, or merge by hand.

Local trimming: edit `~/.config/homebrew/Brewfile`. A change meant for every machine: `chezmoi edit
~/.config/homebrew/Brewfile`, which opens the source in this repo. Note that `chezmoi re-add` does **not** work for
`create_` files — it leaves the source untouched.

To refresh from what is installed (`HOMEBREW_BUNDLE_FILE` already points at the local core manifest):

```bash
brew bundle dump --force
```

`dump` writes *everything installed* into that one file, flattening the split — afterwards move the personal entries back
into `Brewfile.personal` in the source.

To check what the other profile would produce, render it into a scratch directory instead of applying it; the exact
command is in `CLAUDE.md`.

## Secrets

This repo intentionally contains **no secrets and nothing identifying**:

- `~/.ssh`, `~/.gnupg`, `~/.aws`, shell history and friends are backed up by
  [dotpak](https://github.com/ospiem/dotpak) as encrypted archives, not committed here.
- Git identity is prompted for at init and stored outside git.
- Commits are signed with [Secretive](https://github.com/maxgoedjen/secretive); keys live in the Secure Enclave and
  **cannot be migrated** — create a new key on a new machine, point the `signingkey` prompt at it, and add the public
  key to `~/.config/git/allowed_signers` (which is not managed here either).

### Encrypted files

`Brewfile.personal` is the one encrypted entry: age, with the three YubiKey recipients from
`~/.config/age/recipients`. The private keys never leave the token — `~/.config/age/identity` only holds
`AGE-PLUGIN-YUBIKEY` stubs — so the repository is safe to publish even though the ciphertext is in it.

Consequences worth knowing:

- **Decryption needs the token plugged in, and a terminal** for the PIN prompt. `chezmoi apply`, `diff` and `status` all
  decrypt, so all three want the key. Skip those entries with `-x encrypted` when you only care about the rest.
- **A missing key does not abort the apply** — chezmoi reports the entry as failed and keeps going with everything else.
- `encryption = "age"` is set for every profile on purpose: it is what makes chezmoi treat `.age` as a suffix, so the
  target is `Brewfile.personal` everywhere. Gate it per profile and a work machine tries to apply the raw ciphertext.
- To edit: `chezmoi edit ~/.config/homebrew/Brewfile.personal` (decrypts, opens, re-encrypts). Adding another encrypted
  file: `chezmoi add --encrypt <path>`.

## License

[MIT](LICENSE)

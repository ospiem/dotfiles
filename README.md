# dotfiles

[chezmoi](https://www.chezmoi.io) source directory for macOS, with `personal`
and `work` profiles.

## Bootstrap

Order matters: the dotpak archive carries the chezmoi answers, so restoring it
first means `init` asks nothing.

```bash
brew install age age-plugin-yubikey chezmoi go       # YubiKey plugged in
age-plugin-yubikey --identity > ~/.config/age/identity
go install github.com/ospiem/dotpak/cmd/dotpak@latest
dotpak restore ~/Library/Mobile\ Documents/com~apple~CloudDocs/backups/dotfiles/dotfiles-<latest>.tar.gz.age
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ospiem
dotpak cron install                                   # daily dotfiles job
```

`dotpak restore` brings back content only (SSH/GPG/cloud credentials, shell
history, Codex/Claude state, `~/.config/chezmoi/chezmoi.toml`); every dotfile
comes from this repo, so the two never overwrite each other. The archive is
encrypted to the cron key and to every YubiKey — the stub identity above opens
it (two touches: safety scan, then extraction). `~/.config/age/cron-recipient.txt`
and the YubiKey-encrypted `cron-identity.txt.age` are managed here, so a new
machine encrypts to the same keys and can recover the cron key.

`chezmoi init` applies the dotfiles, installs the Go tools from
`go-packages.txt` and loads the `~/.claude` backup job
(`Library/LaunchAgents/dev.ospiem.dotpak.claude-code.plist`).

Homebrew packages are a separate, deliberate step:

```bash
brew bundle                                               # core
brew bundle --file=~/.config/homebrew/Brewfile.personal   # personal only
```

## Daily usage

```bash
chezmoi edit ~/.zshrc      # edit the source, not the live file
chezmoi diff               # what would change
chezmoi apply
chezmoi re-add             # pull local edits back (skips templates)
```

## Worth knowing

- Machine-specific settings go to `~/.zshrc.local` / `~/.gitconfig.local`,
  sourced last. `dot_zshrc` is not a template — it contains literal `{{ }}`.
- `~/.config/homebrew/Brewfile` is a `create_` file: written once, then owned by
  the machine. Changes here don't reach a machine that already has it, and
  `re-add` won't pick up local edits — use `chezmoi edit`.
- `Brewfile.personal` is age-encrypted; `apply`, `diff` and `status` all want
  the key. `-x encrypted` skips it.
- Signing keys are per-machine: create a new one and add it to
  `~/.config/git/allowed_signers`.

## License

[MIT](LICENSE)
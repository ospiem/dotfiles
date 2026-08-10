# dotfiles

[chezmoi](https://www.chezmoi.io) source directory for macOS, with `personal`
and `work` profiles.

## Bootstrap

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ospiem
```

Prompts for the profile and git identity (answers go to
`~/.config/chezmoi/chezmoi.toml`, outside git), applies the dotfiles, installs
the Go tools from `go-packages.txt`.

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
# ~/.zsh/brew.zsh — helpers for the two package manifests.
#
# Two files exist on purpose:
#   ~/.config/homebrew/Brewfile           core, travels to every machine
#   ~/.config/homebrew/Brewfile.personal  encrypted, personal profile only
#
# The only decision when adding a package is "would a work machine need this
# too?" — yes goes to the core manifest, no goes to the personal one.
#
# bic and bip write to the SOURCE files inside the chezmoi repository, not to the
# copies in $HOME: the core copy carries the create_ attribute, so chezmoi never
# syncs it back and editing it would only change this machine.
#
# baudit reads the opposite way — the copies in $HOME. The personal manifest is
# age-encrypted at the source, so reading it there costs a YubiKey PIN on every
# run; `chezmoi apply` already wrote a decrypted copy, so the PIN is paid once,
# at apply time. This also makes the report describe THIS machine: the core copy
# is allowed to drift from the source (a work machine may drop packages its
# policy forbids), and it is the drifted copy that says what should be installed
# here.
#
# The price of that split: a package recorded by bic lands in the source only,
# and baudit calls it untracked until the core copy is refreshed. `apply` will
# not do it — create_ means chezmoi writes that file once and never again — so
# the refresh is `rm ~/.config/homebrew/Brewfile && chezmoi apply`, which also
# discards whatever this machine had trimmed.

function _brew_manifest_src() {
    command chezmoi source-path "$HOME/.config/homebrew/$1" 2>/dev/null
}

# bic [--cask] <name>... — install and record in the CORE manifest.
function bic() {
    local src
    src=$(_brew_manifest_src Brewfile) || { print -u2 "bic: no core manifest in the source state"; return 1 }
    command brew bundle add --install --file="$src" "$@"
}

# bip [--cask] <name>... — install and record in the PERSONAL manifest.
# The source is age-encrypted, so decrypt into a private temp file, append there
# and encrypt back. Needs the YubiKey.
function bip() {
    local src tmp
    src=$(_brew_manifest_src Brewfile.personal) || { print -u2 "bip: no personal manifest in the source state"; return 1 }
    tmp=$(mktemp "${TMPDIR:-/tmp}/brewfile.XXXXXX") || return 1
    chmod 600 "$tmp"
    if ! command chezmoi decrypt "$src" > "$tmp"; then
        print -u2 "bip: could not decrypt — is the YubiKey plugged in?"
        rm -f "$tmp"; return 1
    fi
    if command brew bundle add --install --file="$tmp" "$@"; then
        command chezmoi encrypt "$tmp" > "$src"
    fi
    rm -f "$tmp"
}

# Progress for baudit, on stderr and only when that is a terminal: one line that
# is rewritten in place and erased before any real output, so a redirect or a pipe
# gets exactly the report and nothing else. Without it the two `brew bundle check`
# runs and the mas query look like a hang.
function _baudit_step() {
    [[ -t 2 ]] || return 0
    print -Pnu2 "\r\e[2K%F{242}… $1%f"
}

function _baudit_step_done() {
    [[ -t 2 ]] || return 0
    print -nu2 "\r\e[2K"
}

# baudit — reconcile what is installed against both manifests.
#
# Every check runs first and the report is printed in one go at the end: that is
# what lets the progress line stay on its own line and be erased cleanly.
#
# The two directions need different tools. `brew bundle check` understands
# dependencies and aliases, so it is authoritative for "in the manifest but not
# installed". For the opposite direction it is useless, so that half compares
# against `brew leaves --installed-on-request` — which lists only deliberate
# installs, not packages pulled in as dependencies — plus `brew list --cask` and
# `mas list`.
function baudit() {
    local tmp core="$HOME/.config/homebrew/Brewfile" pers="$HOME/.config/homebrew/Brewfile.personal"
    local -a manifests

    [[ -f $core ]] || { print -u2 "baudit: no $core — run chezmoi apply"; return 1 }
    manifests=("$core")

    # An absent personal manifest is normal on a work machine, where
    # .chezmoiignore drops it — but on a personal one it means the apply has not
    # happened yet, and staying quiet would report its packages as untracked.
    # `chezmoi source-path` tells the two apart without touching the ciphertext.
    if [[ -f $pers ]]; then
        manifests+=("$pers")
    elif command chezmoi source-path "$pers" &>/dev/null; then
        print -u2 "baudit: $pers is managed but missing — run chezmoi apply, or its packages look untracked"
    fi

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/baudit.XXXXXX") || return 1
    chmod 700 "$tmp"

    _baudit_step 'listing installed formulae and casks'
    grep -hE '^brew ' "${manifests[@]}" | sed -E 's/^brew "([^"]+)".*/\1/' | sort -u > "$tmp/want_brew"
    grep -hE '^cask ' "${manifests[@]}" | sed -E 's/^cask "([^"]+)".*/\1/' | sort -u > "$tmp/want_cask"
    command brew leaves --installed-on-request | sort > "$tmp/have_brew"
    command brew list --cask 2>/dev/null | sort > "$tmp/have_cask"

    # App Store apps are keyed by id, never by name: `mas list` prints one id
    # under two names after an app is renamed (Vinegar / Vinegar 2), and two
    # unrelated apps can share a name (Pages). mas itself comes from the personal
    # manifest, so it is absent on a work machine.
    : > "$tmp/extra_mas"
    if (( $+commands[mas] )); then
        _baudit_step 'listing App Store apps'
        grep -hE '^mas ' "${manifests[@]}" | sed -E 's/.*id: *([0-9]+).*/\1/' | sort -u > "$tmp/want_mas"
        # The tracked ids go in as one comma-delimited string, not as a second awk
        # input file: with an empty want list `NR == FNR` holds for every line of
        # `mas list` as well, and the comparison silently prints nothing at all.
        command mas list | awk -v tracked=",$(paste -sd, "$tmp/want_mas")," '
            $1 !~ /^[0-9]+$/           { next }
            index(tracked, "," $1 ",") { next }
            seen[$1]++                 { next }
            { id = $1
              sub(/[[:space:]]*\([^)]*\)[[:space:]]*$/, "")
              sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
              print "  mas " $0 " (" id ")" }
        ' > "$tmp/extra_mas"
    fi

    # --no-upgrade keeps this a presence check instead of a version check. The
    # version check re-resolves every cask and calls `mas outdated`, both
    # network-bound: that is what made this take minutes instead of a second.
    local -x HOMEBREW_NO_AUTO_UPDATE=1
    local m
    : > "$tmp/missing"
    for m in "${manifests[@]}"; do
        _baudit_step "checking ${m:t} against what is installed"
        command brew bundle check --no-upgrade --verbose --file="$m" 2>&1 | grep '^→' >> "$tmp/missing"
    done
    _baudit_step_done

    print -P '%F{yellow}installed but in no manifest%f'
    comm -23 "$tmp/have_brew" "$tmp/want_brew" | sed 's/^/  /'
    comm -23 "$tmp/have_cask" "$tmp/want_cask" | sed 's/^/  cask /'
    cat "$tmp/extra_mas"

    print -P '%F{yellow}in a manifest but not installed%f'
    sed 's/^/  /' "$tmp/missing"

    rm -rf "$tmp"
}

# `brew bundle add` has no --mas flag, so App Store entries are still added by
# hand: `chezmoi edit ~/.config/homebrew/Brewfile.personal`.

# ~/.zsh/brew.zsh — helpers for the two package manifests.
#
# Two files exist on purpose:
#   ~/.config/homebrew/Brewfile           core, travels to every machine
#   ~/.config/homebrew/Brewfile.personal  encrypted, personal profile only
#
# The only decision when adding a package is "would a work machine need this
# too?" — yes goes to the core manifest, no goes to the personal one.
#
# All three functions work on the SOURCE files inside the chezmoi repository, not
# on the copies in $HOME: the core copy carries the create_ attribute, so chezmoi
# never syncs it back and editing it would only change this machine.

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
    local core pers tmp have_personal=1
    core=$(_brew_manifest_src Brewfile) || return 1
    pers=$(_brew_manifest_src Brewfile.personal)
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/baudit.XXXXXX") || return 1
    chmod 700 "$tmp"

    # stderr is deliberately NOT redirected here, and this notice is a permanent
    # line rather than a transient one: age-plugin-yubikey prints "Enter PIN for
    # YubiKey" on stderr and reads the PIN from the terminal, so swallowing stderr
    # turns a PIN prompt into a silent "not decrypted", and erasing the line would
    # eat the prompt with it.
    if [[ -n $pers ]]; then
        [[ -t 2 ]] && print -Pu2 '%F{242}… decrypting the personal manifest — the YubiKey wants its PIN%f'
        command chezmoi decrypt "$pers" > "$tmp/pers" || have_personal=0
    else
        have_personal=0
    fi
    if (( ! have_personal )); then
        : > "$tmp/pers"
        print -u2 "baudit: personal manifest not decrypted — its packages will look untracked"
    fi

    _baudit_step 'listing installed formulae and casks'
    grep -hE '^brew ' "$core" "$tmp/pers" | sed -E 's/^brew "([^"]+)".*/\1/' | sort -u > "$tmp/want_brew"
    grep -hE '^cask ' "$core" "$tmp/pers" | sed -E 's/^cask "([^"]+)".*/\1/' | sort -u > "$tmp/want_cask"
    command brew leaves --installed-on-request | sort > "$tmp/have_brew"
    command brew list --cask 2>/dev/null | sort > "$tmp/have_cask"

    # App Store apps are keyed by id, never by name: `mas list` prints one id
    # under two names after an app is renamed (Vinegar / Vinegar 2), and two
    # unrelated apps can share a name (Pages). mas itself comes from the personal
    # manifest, so it is absent on a work machine.
    : > "$tmp/extra_mas"
    if (( $+commands[mas] )); then
        _baudit_step 'listing App Store apps'
        grep -hE '^mas ' "$core" "$tmp/pers" | sed -E 's/.*id: *([0-9]+).*/\1/' | sort -u > "$tmp/want_mas"
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
    _baudit_step 'checking the core manifest against what is installed'
    command brew bundle check --no-upgrade --verbose --file="$core" 2>&1 | grep '^→' > "$tmp/missing"
    if (( have_personal )); then
        _baudit_step 'checking the personal manifest against what is installed'
        command brew bundle check --no-upgrade --verbose --file="$tmp/pers" 2>&1 | grep '^→' >> "$tmp/missing"
    fi
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

# ~/.zsh/git-aliases.zsh

# ── Helpers ──────────────────────────────────────────────────────────────────
# Detect the default branch (main, master, trunk, etc.) — from oh-my-zsh git plugin
function git_main_branch() {
  command git rev-parse --git-dir &>/dev/null || return
  local ref
  for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
    if command git show-ref -q --verify $ref; then
      echo ${ref:t}
      return 0
    fi
  done
  echo master
  return 1
}

# Status & Info
alias gs='git status'
alias gst='git status'
alias gb='git branch'
alias glo='git log --oneline --decorate'
alias glg='git log --graph --oneline --decorate --all'
alias gsh='git show'
alias gbl='git blame -w -C -C -C'   # ignore whitespace, follow code moved between files
alias gd='git diff'
alias gds='git diff --staged'
alias gdup='git diff @{upstream}'
alias gdst='git diff --stat'

# Staging & Committing
alias gaa='git add --all'
alias gcmsg='git commit -m'
alias gcsm='git commit -s -m'
alias gcm='git checkout main 2>/dev/null || git checkout master'

# Checkout & Branching
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'              # switch is the modern verb for branches only
alias gswc='git switch -c'
alias gcp='git cherry-pick'

# Push & Pull
alias gp='git push'
alias gpsup='git push --set-upstream origin $(git symbolic-ref --short HEAD)'
alias gpf='git push --force-with-lease'
alias gpd='git push --dry-run'
alias gl='git pull'

# Fetch & Remote
alias gf='git fetch'
alias gfa='git fetch --all --prune'
alias gra='git remote add'

# Rebase & Merge
alias grb='git rebase'
alias grbi='git rebase -i'          # rebase.autoSquash picks up fixup! commits
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias grbom='git rebase origin/$(git_main_branch)'
alias gm='git merge'

# Fixup workflow: stage the fix, `gcf <sha>`, then `grbi <sha>~1` — autoSquash
# in ~/.gitconfig folds it into the right commit without editing the todo list.
alias gcf='git commit --fixup'
alias gundo='git reset --soft HEAD~1'   # undo the last commit, keep the changes staged

# Restore & Revert
alias grs='git restore'
alias grst='git restore --staged'
alias grev='git revert'

# Stash
alias gsta='git stash push'
alias gstp='git stash pop'
alias gstd='git stash drop'
alias gsts='git stash show --text'
alias gstl='git stash list'

# Branch delete
alias gbd='git branch -d'
alias gbD='git branch -D'
alias gbv='git branch -vv'          # shows upstream and [gone] markers

# Delete local branches already merged into the default branch.
#   gbda        delete
#   gbda -n     dry run — only print what would go
#   gbda -f     use `git branch -D` instead of `-d`
#
# The default branch and the checked-out one are always kept. `--merged` compares
# against the LOCAL default branch, so pull it first or the list will be stale.
# Squash-merged work is invisible to `--merged` — use gbdg for that.
function gbda() {
  local dry=0 flag=-d main current
  local -a branches
  while [[ $1 == -* ]]; do
    case $1 in
      -n|--dry-run) dry=1 ;;
      -f|--force) flag=-D ;;
      *) print -u2 "usage: gbda [-n|--dry-run] [-f|--force]"; return 2 ;;
    esac
    shift
  done

  command git rev-parse --git-dir &>/dev/null || { print -u2 "gbda: not a git repository"; return 1 }
  # git_main_branch returns non-zero when it falls back to 'master', which is not
  # an error here — only the missing repository is.
  main=$(git_main_branch)
  current=$(command git symbolic-ref --quiet --short HEAD)

  if ! command git show-ref -q --verify "refs/heads/$main"; then
    print -u2 "gbda: no local $main branch to compare against"
    return 1
  fi

  # --format avoids parsing the '*' and '+' markers that `git branch` prints.
  branches=(${(f)"$(command git branch --merged $main --format='%(refname:short)' \
    | grep -vxE "main|master|develop|trunk|$main|${current:-HEAD}")"})

  if (( ${#branches} == 0 )); then
    print "gbda: nothing merged into $main"
    return 0
  fi

  if (( dry )); then
    print -l "gbda: would delete" $branches
    return 0
  fi

  command git branch $flag $branches
}

# Delete local branches whose upstream is gone — the branch was merged and the
# forge deleted it. This is what catches squash and rebase merges, which leave no
# merge commit for `--merged` to find.
#   gbdg        fetch --prune, show the list, ask, delete
#   gbdg -n     dry run
#   gbdg -y     no confirmation
#
# Deletion is forced (`-D`): squash-merged branches are not "merged" as far as git
# is concerned. Recover a mistake with `git reflog` and `git branch <name> <sha>`.
function gbdg() {
  local dry=0 yes=0 main current
  local -a branches
  while [[ $1 == -* ]]; do
    case $1 in
      -n|--dry-run) dry=1 ;;
      -y|--yes) yes=1 ;;
      *) print -u2 "usage: gbdg [-n|--dry-run] [-y|--yes]"; return 2 ;;
    esac
    shift
  done

  command git rev-parse --git-dir &>/dev/null || { print -u2 "gbdg: not a git repository"; return 1 }
  command git remote >/dev/null && [[ -n $(command git remote) ]] || { print -u2 "gbdg: no remote configured"; return 1 }
  command git fetch --prune --quiet || return 1

  main=$(git_main_branch)
  current=$(command git symbolic-ref --quiet --short HEAD)

  branches=(${(f)"$(command git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads \
    | awk '$2 == "[gone]" { print $1 }' \
    | grep -vxE "$main|${current:-HEAD}")"})

  if (( ${#branches} == 0 )); then
    print "gbdg: no branches with a gone upstream"
    return 0
  fi

  print -l "gbdg: upstream gone for" $branches
  (( dry )) && return 0

  if (( ! yes )); then
    read -q "?Delete ${#branches} branch(es)? [y/N] " || { print; return 0 }
    print
  fi

  command git branch -D $branches
}

# Clone
alias gcl='git clone'

function gccd() {
  git clone --recurse-submodules "$@" \
    && cd "$(basename "${1%.git}")"
}

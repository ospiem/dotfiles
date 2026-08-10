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
alias gst='git status'                        # working tree status
alias gb='git branch'                         # list local branches
alias glo='git log --oneline --decorate'      # one line per commit
alias glg='git log --graph --oneline --decorate --all'  # graph, every branch
alias gsh='git show'                          # a commit: metadata and diff
alias gbl='git blame -w -C -C -C'             # ignore whitespace and moved code
alias gd='git diff'                           # unstaged changes
alias gds='git diff --staged'                 # staged changes — the next commit
alias gdup='git diff @{upstream}'             # what is not pushed yet
alias gdst='git diff --stat'                  # changed files and line counts

# Staging & Committing
alias gaa='git add --all'                     # stage everything, deletions too
alias gcmsg='git commit -m'                   # commit with an inline message
alias gcsm='git commit -s -m'                 # same, with a Signed-off-by line

# Checkout & Branching
# `git switch` is the modern verb for branches; gco stays for what it cannot do
# (paths, detached HEAD, `gco <sha>`).
alias gco='git checkout'                      # paths, revisions, detached HEAD
alias gsw='git switch'                        # branches only, never files
alias gswc='git switch -c'                    # create a branch and switch to it
alias gcm='git checkout $(git_main_branch)'   # back to the default branch
alias gcp='git cherry-pick'                   # replay a commit onto HEAD

# Push & Pull
# No gpsup: push.autoSetupRemote in ~/.gitconfig makes plain `gp` set the
# upstream on a fresh branch.
alias gp='git push'                           # upstream is set automatically
alias gpf='git push --force-with-lease'       # abort if the remote moved
alias gpd='git push --dry-run'                # what would be pushed
alias gl='git pull'                           # rebases, per pull.rebase

# Fetch & Remote
alias gf='git fetch'                          # refresh origin's tracking refs
alias gfa='git fetch --all --prune'           # all remotes, drop dead branches
alias gra='git remote add'                    # gra <name> <url>

# Rebase & Merge
alias grb='git rebase'                        # replay HEAD onto <branch>
alias grbi='git rebase -i'                    # autoSquash folds fixup! commits
alias grbc='git rebase --continue'            # resume after fixing conflicts
alias grba='git rebase --abort'               # restore the pre-rebase state
alias grbom='git rebase origin/$(git_main_branch)'  # onto remote default
alias gm='git merge'                          # merge <branch> into HEAD

# Fixup workflow: stage the fix, `gcf <sha>`, then `grbi <sha>~1` — autoSquash
# in ~/.gitconfig folds it into the right commit without editing the todo list.
alias gcf='git commit --fixup'                # mark a fix for <sha>
alias gundo='git reset --soft HEAD~1'         # undo last commit, keep changes

# Restore & Revert
alias grs='git restore'                       # discard unstaged changes
alias grst='git restore --staged'             # unstage, keep the changes
alias grev='git revert'                       # new commit that undoes <sha>

# Stash
alias gsta='git stash push'                   # stash the working tree
alias gstp='git stash pop'                    # apply newest stash and drop it
alias gstd='git stash drop'                   # discard a stash unapplied
alias gsts='git stash show --text'            # full diff of a stash
alias gstl='git stash list'                   # list stashes

# Branch delete
alias gbd='git branch -d'                     # delete a merged branch
alias gbD='git branch -D'                     # delete even if unmerged
alias gbv='git branch -vv'                    # upstream and [gone] markers

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
alias gcl='git clone'                         # clone into ./<repo>

function gccd() {
  git clone --recurse-submodules "$@" \
    && cd "$(basename "${1%.git}")"
}

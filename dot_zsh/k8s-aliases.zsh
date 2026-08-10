# ~/.zsh/k8s-aliases.zsh
#
# Sourced from .zshrc after compinit — that is what fills $_comps, which the
# compdef guards below depend on.
#
# Every group is guarded on its binary. The Kubernetes tools sit in the core
# Brewfile, but a machine is free to trim them, and an alias for a missing
# command only turns into a confusing error much later.

# ── kubectl ──────────────────────────────────────────────────────────────────
if (( $+commands[kubectl] )); then
  alias k='kubectl'                           # completes like kubectl itself
  alias kg='kubectl get'                      # kg pods, kg svc -A
  alias kd='kubectl describe'                 # status and events of one object
  alias kl='kubectl logs'                     # kl -f <pod> to follow
  alias kex='kubectl exec -it'                # not `ke`: too close to `k`
  alias kaf='kubectl apply -f'                # a manifest or a directory
  alias kdf='kubectl diff -f'                 # what apply would change
  alias kgp='kubectl get pods'                # pods in the current namespace
  alias kgn='kubectl get nodes'               # nodes in the cluster

  # The tools ship their own completions via Homebrew (_kubectl, _kubectx and
  # _kubens land in site-functions, already on fpath), so only the aliases need
  # wiring: compdef makes them reuse the real command's completion.
  #
  # This guard tests $_comps rather than the binary — the binary is a given by
  # now, but compdef still errors out loudly when the completion system has
  # never seen the command: a stale ~/.zcompdump, rebuilt only once a day.
  (( $+_comps[kubectl] )) && compdef k=kubectl
fi

# ── Context and namespace ────────────────────────────────────────────────────
# Separate guards rather than one on kubectx: the formula ships both binaries,
# but either can be trimmed while kubectl stays.
if (( $+commands[kubectx] )); then
  alias kctx='kubectx'                        # switch context
  (( $+_comps[kubectx] )) && compdef kctx=kubectx
fi

if (( $+commands[kubens] )); then
  alias kns='kubens'                          # switch namespace
  (( $+_comps[kubens] )) && compdef kns=kubens
fi

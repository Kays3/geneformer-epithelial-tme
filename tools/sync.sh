#!/usr/bin/env bash
# Sync this repository between the laptop, the workstations, and GitHub.
#
# The failure this prevents: committing on two machines without pulling in
# between, which forks history and needs a manual rebase to untangle. Run it
# before you start work on a machine and after you finish.
#
#   ./tools/sync.sh                 # rebase onto origin, push, fast-forward every node
#   ./tools/sync.sh --check         # report divergence and exit, change nothing
#   ./tools/sync.sh --only thinkstation1
#   ./tools/sync.sh --github-only   # skip the workstations entirely
#   ./tools/sync.sh --bootstrap     # clone the repo onto any node that lacks it
#
# Hosts are ~/.ssh/config aliases, which already carry User and IdentityFile, so
# the bare alias is preferred over kaisar@thinkstation2. Override the list with
# SYNC_HOSTS="a b", or the checkout path with SYNC_REMOTE_PATH.
#
# Direct laptop -> node pushes work because each node sets
# `receive.denyCurrentBranch=updateInstead`, which updates its working tree in
# place. That needs a clean tree on the node; this script checks first and tells
# you rather than failing halfway. A node that is unreachable, missing the repo,
# or dirty is reported and skipped -- it never blocks the other nodes or GitHub.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

read -r -a HOSTS <<< "${SYNC_HOSTS:-thinkstation2 thinkstation1}"
REMOTE_PATH="${SYNC_REMOTE_PATH:-workspace/geneformer-lung-tcell}"
BRANCH="${BRANCH:-main}"
CLONE_URL="${SYNC_CLONE_URL:-https://github.com/Kays3/geneformer-lung-tcell.git}"
SSH_OPTS=(-o ConnectTimeout=8 -o BatchMode=yes)

CHECK_ONLY=0
BOOTSTRAP=0
GITHUB_ONLY=0
ONLY_HOST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=1 ;;
        --bootstrap) BOOTSTRAP=1 ;;
        --github-only|--no-nodes) GITHUB_ONLY=1 ;;
        --only) ONLY_HOST="${2:-}"; shift ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

[[ -n "$ONLY_HOST" ]] && HOSTS=("$ONLY_HOST")
[[ "$GITHUB_ONLY" -eq 1 ]] && HOSTS=()

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
ok()   { printf '  %s\n' "$*"; }

# Per-host state, resolved once and reused: offline | norepo | dirty | ready.
# macOS ships bash 3.2, which has no associative arrays, so state is kept in
# variables whose names are derived from a sanitised host string.
_slot() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
set_state() { eval "ST_$(_slot "$1")=\$2"; }
get_state() { eval "printf '%s' \"\${ST_$(_slot "$1"):-}\""; }
set_head()  { eval "HD_$(_slot "$1")=\$2"; }
get_head()  { eval "printf '%s' \"\${HD_$(_slot "$1"):-}\""; }

probe_host() {
    local host="$1"
    if ! ssh "${SSH_OPTS[@]}" "$host" true 2>/dev/null; then
        set_state "$host" offline; return
    fi
    if ! ssh "${SSH_OPTS[@]}" "$host" "test -d '$REMOTE_PATH/.git'" 2>/dev/null; then
        set_state "$host" norepo; return
    fi
    set_head "$host" "$(ssh "${SSH_OPTS[@]}" "$host" "git -C '$REMOTE_PATH' rev-parse HEAD" 2>/dev/null || echo unknown)"
    if [[ -n "$(ssh "${SSH_OPTS[@]}" "$host" "git -C '$REMOTE_PATH' status --porcelain | head -1" 2>/dev/null)" ]]; then
        set_state "$host" dirty
    else
        set_state "$host" ready
    fi
}

bootstrap_host() {
    local host="$1"
    say "Bootstrapping $host"
    ssh "${SSH_OPTS[@]}" "$host" "
        set -e
        mkdir -p \"\$(dirname '$REMOTE_PATH')\"
        git clone --quiet '$CLONE_URL' '$REMOTE_PATH'
        git -C '$REMOTE_PATH' config receive.denyCurrentBranch updateInstead
    " || { warn "clone failed on $host"; return 1; }
    ok "cloned to $host:$REMOTE_PATH"
    set_state "$host" ready
    set_head "$host" "$(ssh "${SSH_OPTS[@]}" "$host" "git -C '$REMOTE_PATH' rev-parse HEAD")"
}

# A git remote per node, so `git push <host>` works. Kept in step with the alias
# list rather than configured by hand, since the alias set has changed before.
ensure_remote() {
    local host="$1" url="$host:$REMOTE_PATH"
    if ! git remote get-url "$host" >/dev/null 2>&1; then
        git remote add "$host" "$url"
        ok "added git remote '$host' -> $url"
    elif [[ "$(git remote get-url "$host")" != "$url" ]]; then
        git remote set-url "$host" "$url"
        ok "updated git remote '$host' -> $url"
    fi
}

say "Local state"
if [[ -n "$(git status --porcelain)" ]]; then
    warn "working tree is dirty; commit or stash before syncing"
    git status --short | sed 's/^/    /'
    exit 1
fi
ok "$BRANCH at $(git rev-parse --short HEAD)"

say "Fetching origin"
git fetch --quiet origin
behind="$(git rev-list --count "HEAD..origin/$BRANCH")"
ahead="$(git rev-list --count "origin/$BRANCH..HEAD")"
ok "behind origin: $behind   ahead of origin: $ahead"

if [[ ${#HOSTS[@]} -gt 0 ]]; then
    say "Probing nodes"
    for host in "${HOSTS[@]}"; do
        probe_host "$host"
        case "$(get_state "$host")" in
            offline) warn "$host: unreachable, skipping" ;;
            norepo)  warn "$host: no checkout at ~/$REMOTE_PATH (re-run with --bootstrap)" ;;
            dirty)   warn "$host: working tree DIRTY at $(get_head "$host" | cut -c1-7), will not push" ;;
            ready)   ok   "$host: clean at $(get_head "$host" | cut -c1-7)" ;;
        esac
    done
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    say "Check only; nothing changed"
    exit 0
fi

if [[ "$BOOTSTRAP" -eq 1 ]]; then
    for host in "${HOSTS[@]}"; do
        [[ "$(get_state "$host")" == "norepo" ]] && bootstrap_host "$host" || true
    done
fi

if [[ "$behind" -gt 0 ]]; then
    say "Rebasing onto origin/$BRANCH"
    git rebase "origin/$BRANCH"
fi

if [[ "$(git rev-list --count "origin/$BRANCH..HEAD")" -gt 0 ]]; then
    say "Pushing to origin"
    git push origin "$BRANCH"
else
    say "origin already up to date"
fi

for host in "${HOSTS[@]}"; do
    case "$(get_state "$host")" in
        ready) ;;
        dirty)
            warn "$host: skipped, working tree dirty (commit or stash there, then re-run)"
            continue ;;
        *) continue ;;
    esac
    ensure_remote "$host"
    # Node may be ahead of the laptop if work was committed there; fetch it into
    # a tracking ref so a real fork is visible instead of a rejected push.
    if ! git push "$host" "$BRANCH" 2>/dev/null; then
        warn "$host: push rejected -- it likely has commits the laptop lacks"
        warn "  inspect with:  git fetch $host && git log --oneline HEAD..$host/$BRANCH"
        continue
    fi
    say "Pushed to $host"
done

say "Final state"
printf '  %-16s %s\n' "local" "$(git rev-parse HEAD)"
printf '  %-16s %s\n' "origin" "$(git rev-parse "origin/$BRANCH")"
for host in "${HOSTS[@]}"; do
    case "$(get_state "$host")" in
        ready) printf '  %-16s %s\n' "$host" "$(ssh "${SSH_OPTS[@]}" "$host" "git -C '$REMOTE_PATH' rev-parse HEAD")" ;;
        *)     printf '  %-16s (%s)\n' "$host" "$(get_state "$host")" ;;
    esac
done

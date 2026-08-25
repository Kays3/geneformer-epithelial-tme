#!/usr/bin/env bash
# Move the lab's Geneformer data out of the retired per-machine home directory
# into /srv/lab, group-owned by labusers.
#
# Why: /home/thinkstation{1,2} is mode 750 owned by an account that is no longer
# used, so no current user can read it. Copying it into a personal home would
# work today and break again the next time accounts change. A group-owned path
# with setgid survives account churn and lets every labusers member read it.
#
# /srv/lab is LOCAL to each node. Run this on each node separately; the two
# machines hold different arms of the perturbation run, so neither copy is
# redundant and there is no merge between them.
#
#   sudo bash tools/migrate_to_srv_lab.sh --inventory   # read-only, shows what would move
#   sudo bash tools/migrate_to_srv_lab.sh --migrate     # copy, then set group + setgid
#   sudo bash tools/migrate_to_srv_lab.sh --verify      # re-check counts and permissions
#
# The source is never deleted. Remove it yourself once you have verified the
# copy and no longer need the old account.
set -euo pipefail

LAB_ROOT="${LAB_ROOT:-/srv/lab}"
LAB_GROUP="${LAB_GROUP:-labusers}"
# Defaults to the retired account matching this machine's short hostname.
SRC_USER="${SRC_USER:-}"
MODE=""

for arg in "$@"; do
    case "$arg" in
        --inventory) MODE=inventory ;;
        --migrate)   MODE=migrate ;;
        --verify)    MODE=verify ;;
        --src-user=*) SRC_USER="${arg#*=}" ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
[[ -z "$MODE" ]] && { printf 'pick one of --inventory | --migrate | --verify\n' >&2; exit 2; }

if [[ -z "$SRC_USER" ]]; then
    for candidate in thinkstation1 thinkstation2; do
        [[ -d "/home/$candidate/workspace" ]] && SRC_USER="$candidate"
    done
fi
[[ -z "$SRC_USER" ]] && { printf 'no retired workspace found; pass --src-user=NAME\n' >&2; exit 1; }

SRC="/home/$SRC_USER/workspace"
say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || { warn "must run as root (sudo)"; exit 1; }
[[ -d "$SRC" ]] || { warn "source not found: $SRC"; exit 1; }

# Everything the analysis actually needs: the experiment workspace and the
# model weights / venv-adjacent assets.
SUBDIRS=(
    "KD"
)
# A virtualenv's compiled packages and shebangs embed absolute paths from the
# machine that built it, so copying one to a new prefix produces an interpreter
# that half-works and fails obscurely. Model weights and the Geneformer checkout
# inside the same tree ARE data and must come across, so exclude only the venv
# and rebuild it with geneformer_uv_setup/scripts/bootstrap_workspace.sh.
RSYNC_EXCLUDES=(--exclude '.venv/' --exclude '__pycache__/' --exclude '*.pyc')
# Assets that are data but do not live under KD. Each entry is SRC:DEST_UNDER_LAB_ROOT.
# The Geneformer checkout carries the model weights and token dictionary; it sits
# inside the venv-bearing tree, so it is pulled out explicitly rather than copying
# that whole directory.
EXTRA_PATHS=(
    "/home/$SRC_USER/workspace/geneformer-uv-starter/geneformer-workspace/Geneformer:geneformer"
)

say "Source: $SRC   (retired account: $SRC_USER)"
say "Target: $LAB_ROOT   group: $LAB_GROUP"

case "$MODE" in
inventory)
    say "Sizes (this is what will be copied)"
    total=0
    for d in "${SUBDIRS[@]}"; do
        if [[ -d "$SRC/$d" ]]; then
            sz="$(du -sb "$SRC/$d" 2>/dev/null | cut -f1)"
            total=$((total + sz))
            printf '  %-28s %8s  %s files\n' "$d" "$(numfmt --to=iec "$sz")" \
                   "$(find "$SRC/$d" -type f 2>/dev/null | wc -l)"
        else
            warn "$d: absent"
        fi
    done
    for entry in "${EXTRA_PATHS[@]}"; do
        src="${entry%%:*}"; dest="${entry##*:}"
        if [[ -d "$src" ]]; then
            sz="$(du -sb "$src" | cut -f1)"; total=$((total + sz))
            printf '  %-28s %8s  -> %s\n' "$dest" "$(numfmt --to=iec "$sz")" "$LAB_ROOT/$dest"
        else
            warn "$dest: absent at $src"
        fi
    done
    printf '\n  TOTAL %s\n' "$(numfmt --to=iec "$total")"
    say "Free space on $(df -h --output=target "$(dirname "$LAB_ROOT")" | tail -1)"
    df -h "$(dirname "$LAB_ROOT")" | tail -1
    avail="$(df -B1 --output=avail "$(dirname "$LAB_ROOT")" | tail -1)"
    if (( avail < total * 11 / 10 )); then
        warn "less than 110% of the payload free -- do not migrate yet"
    else
        ok "sufficient free space"
    fi
    say "Nothing was changed. Re-run with --migrate to copy."
    ;;

migrate)
    say "Creating $LAB_ROOT"
    install -d -m 2775 -g "$LAB_GROUP" "$LAB_ROOT"
    ok "$(stat -c '%n  %U:%G %a' "$LAB_ROOT")"

    for d in "${SUBDIRS[@]}"; do
        [[ -d "$SRC/$d" ]] || { warn "$d: absent, skipped"; continue; }
        say "Copying $d"
        # -H preserves hardlinks, -A/-X keep ACLs and xattrs, no --delete so the
        # run is idempotent and can never remove anything already in the target.
        rsync -aHAX "${RSYNC_EXCLUDES[@]}" --info=progress2 "$SRC/$d/" "$LAB_ROOT/$d/"
        ok "done: $LAB_ROOT/$d"
    done

    for entry in "${EXTRA_PATHS[@]}"; do
        src="${entry%%:*}"; dest="${entry##*:}"
        [[ -d "$src" ]] || { warn "$dest: absent, skipped"; continue; }
        say "Copying $dest"
        install -d -m 2775 -g "$LAB_GROUP" "$LAB_ROOT/$(dirname "$dest")"
        rsync -aHAX "${RSYNC_EXCLUDES[@]}" --info=progress2 "$src/" "$LAB_ROOT/$dest/"
        ok "done: $LAB_ROOT/$dest"
    done

    say "Applying ownership, group and setgid"
    # Own the tree as root rather than leaving it under the retired account. If
    # that account is ever deleted its UID disappears and every file it owns
    # becomes an orphaned numeric owner; root always exists. Access is granted
    # through the group, so nobody loses anything by root holding the files.
    chown -R root:"$LAB_GROUP" "$LAB_ROOT"
    # Group-writable, not just readable: analyses write their outputs back into
    # these trees (stats tables, raw shards), so labusers members must be able to
    # create and modify files here. X rather than x so only directories and
    # already-executable files gain the traverse bit.
    chmod -R g+rwX "$LAB_ROOT"
    # setgid on directories so anything created later inherits labusers; this is
    # what stops the permission problem recurring.
    find "$LAB_ROOT" -type d -exec chmod g+s {} +
    ok "owner=root, group=$LAB_GROUP, group-writable, dirs setgid"
    say "Next: rebuild the Python environment"
    ok "the .venv was deliberately NOT copied; rebuild it with"
    ok "  bash geneformer_uv_setup/scripts/bootstrap_workspace.sh"
    ok "then point PYTHON_BIN at the new interpreter in ~/.config/geneformer-lung-tcell/paths.env"
    say "Source left untouched at $SRC -- delete it yourself after verifying"
    ;;

verify)
    say "Verifying $LAB_ROOT"
    fail=0
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    for d in "${SUBDIRS[@]}"; do
        [[ -d "$SRC/$d" ]] || continue
        # Compare the actual relative paths, not just counts: a count can match
        # while different files are missing on each side, and a count mismatch
        # says nothing about which direction the problem lies in.
        ( cd "$SRC/$d" && find . -type f -not -path './.venv/*' -not -name '*.pyc' 2>/dev/null | sort ) > "$tmp/src"
        ( cd "$LAB_ROOT/$d" && find . -type f 2>/dev/null | sort ) > "$tmp/dst"
        only_src="$(comm -23 "$tmp/src" "$tmp/dst")"
        only_dst="$(comm -13 "$tmp/src" "$tmp/dst")"
        n_src="$(wc -l < "$tmp/src")"; n_dst="$(wc -l < "$tmp/dst")"
        if [[ -z "$only_src" && -z "$only_dst" ]]; then
            ok "$d: $n_dst files, identical file lists"
        elif [[ -z "$only_src" ]]; then
            # Extra files in the target are not data loss. They accumulate when
            # the target was populated earlier and has been written to since.
            ok "$d: all $n_src source files present; target has $(wc -l <<< "$only_dst") extra"
            printf '%s\n' "$only_dst" | head -10 | sed 's|^\./|      + |'
            [[ "$(wc -l <<< "$only_dst")" -gt 10 ]] && printf '      ... and %s more\n' "$(( $(wc -l <<< "$only_dst") - 10 ))"
        else
            warn "$d: $(wc -l <<< "$only_src") file(s) MISSING from the target"
            printf '%s\n' "$only_src" | head -20 | sed 's|^\./|      - |' >&2
            [[ "$(wc -l <<< "$only_src")" -gt 20 ]] && printf '      ... and %s more\n' "$(( $(wc -l <<< "$only_src") - 20 ))" >&2
            fail=1
        fi
    done
    bad_group="$(find "$LAB_ROOT" ! -group "$LAB_GROUP" -print -quit 2>/dev/null || true)"
    [[ -n "$bad_group" ]] && { warn "not group $LAB_GROUP: $bad_group"; fail=1; } || ok "group ownership uniform"
    bad_owner="$(find "$LAB_ROOT" ! -user root -print -quit 2>/dev/null || true)"
    [[ -n "$bad_owner" ]] && { warn "not owned by root (orphans if the account is deleted): $bad_owner"; fail=1; } || ok "owned by root"
    nogw="$(find "$LAB_ROOT" -type d ! -perm -g+w -print -quit 2>/dev/null || true)"
    [[ -n "$nogw" ]] && { warn "directory not group-writable: $nogw"; fail=1; } || ok "directories group-writable"
    nosetgid="$(find "$LAB_ROOT" -type d ! -perm -g+s -print -quit 2>/dev/null || true)"
    [[ -n "$nosetgid" ]] && { warn "directory without setgid: $nosetgid"; fail=1; } || ok "setgid set on all directories"
    say "$([[ $fail -eq 0 ]] && echo 'VERIFIED' || echo 'PROBLEMS FOUND - do not delete the source')"
    exit $fail
    ;;
esac

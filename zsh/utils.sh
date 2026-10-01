#!/bin/bash

########################################################################################
# VPN utils
# VPN_PROFILE is per-machine: set it in ~/.zshrc.local (untracked).
connect_vpn() {
    openvpn3 session-start --config "$VPN_PROFILE"
}

check_vpn() {
    echo "Check VPN sessions list"
    openvpn3 sessions-list
}

disconnect_vpn() {
    ACTIVE_SESSIONS=$(openvpn3 sessions-list | grep -i 'path' | awk '{p=index($0, ":");print $2}')
    echo "$ACTIVE_SESSIONS"
    for instance in $ACTIVE_SESSIONS; do
        openvpn3 session-manage --disconnect --session-path "${instance}"
    done
    openvpn3 session-manage --disconnect --config "$VPN_PROFILE"
}

########################################################################################
# Misc
SSH_OPTS="ssh -o StrictHostKeyChecking=accept-new -o Batchmode=yes -o LogLevel=info -o ConnectionAttempts=3 -o ConnectTimeout=120 -o ServerAliveInterval=120 -o ServerAliveCountMax=3"
multi_rsync() {
    if [[ -n "$ZSH_VERSION" ]]; then
        setopt local_options ksh_arrays sh_word_split
    fi
    local extra_opts=""
    local dest=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            cat <<'EOF'
Usage: multi_rsync [--dest <path>] [--extra-opts "<rsync flags>"] <source> <target> [target ...]

Sync a local directory to multiple local/remote targets using rsync in parallel.

Default rsync opts: -avz --delete --rsh="$SSH_OPTS"

Arguments:
  source       Local source directory (trailing / recommended)
  target ...   One or more targets:
                 user@host         remote (no path, requires --dest)
                 user@host:/path   remote (with explicit path)
                 /local/path       local (no colon = local, same as rsync)

Options:
  --dest <path>          Shared destination path (applies to all targets)
  --extra-opts "<flags>" Additional rsync options (appended to defaults)
  -h, --help             Show this help

Examples:
  # Remote with per-target paths:
  multi_rsync /var/www/deploy/ user@web1:/opt/app/ user@web2:/opt/app/

  # Remote with shared --dest:
  multi_rsync --dest /opt/app/ /var/www/deploy/ user@web1 user@web2

  # Mixed local + remote:
  multi_rsync --dest /opt/app/ /var/www/deploy/ /opt/local-copy user@web1 user@web2
EOF
            return 0
            ;;
        --dest)
            [[ $# -lt 2 ]] && {
                echo "Error: --dest requires a value" >&2
                return 1
            }
            dest="$2"
            shift 2
            ;;
        --extra-opts)
            [[ $# -lt 2 ]] && {
                echo "Error: --extra-opts requires a value" >&2
                return 1
            }
            extra_opts="$2"
            shift 2
            ;;
        *)
            break
            ;;
        esac
    done

    local source="${1:?Usage: multi_rsync <source> <target> [target ...] (see --help)}"
    shift
    local -a hosts=("$@")

    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo "Error: at least one target required" >&2
        return 1
    fi

    # Build per-target specs (rsync convention: contains ":" = remote, else local)
    local -a targets=()
    local -a remote_hosts=()
    local host h
    for host in "${hosts[@]}"; do
        if [[ "$host" == *:* ]]; then
            # Remote: user@host or user@host:/path
            if [[ -n "$dest" ]]; then
                h="${host#*@}"
                if [[ "$h" == *:* ]]; then
                    echo "Error: with --dest, remote targets must not include :/path (got: $host)" >&2
                    return 1
                fi
                targets+=("$host$dest")
            else
                targets+=("$host")
            fi
            remote_hosts+=("${host#*@}")
        else
            # Local path (no colon)
            if [[ -n "$dest" ]]; then
                targets+=("$dest")
            else
                targets+=("$host")
            fi
        fi
    done

    # --- Logging ---
    local log_file="/tmp/multi_rsync_$(date +%Y%m%d_%H%M%S).log"
    : >"$log_file"
    log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$log_file"; }

    local -a opts=(-avz --delete --rsh="$SSH_OPTS")
    if [[ -n "$extra_opts" ]]; then
        local -a extra_arr
        extra_arr=($extra_opts)
        opts+=("${extra_arr[@]}")
    fi

    local -a pids failed=()

    log "Log file:  $log_file"
    log "Source:    $source"
    log "Targets:   ${targets[*]}"
    log "Opts:      ${opts[*]}"

    # Phase 0: Remove stale host keys (remote only)
    for h in "${remote_hosts[@]}"; do
        local bare="${h%%:*}"
        if [[ "$bare" == "localhost" || "$bare" == "127.0.0.1" || "$bare" == "::1" ]]; then
            continue
        fi
        log "Phase 0: ssh-keygen -f $HOME/.ssh/known_hosts -R $bare"
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$bare" >/dev/null 2>&1
    done
    log ""

    # Sync every target directly and in parallel. (No batch-mode replay:
    # rsync --read-batch refuses any remote destination, so a single
    # write-once/read-many scheme cannot work once a target is remote.)
    local i
    for i in $(seq 0 $((${#targets[@]} - 1))); do
        log "rsync ${opts[*]} $source ${targets[$i]}"
        rsync "${opts[@]}" "$source" "${targets[$i]}" >>"$log_file" 2>&1 &
        pids+=($!)
    done

    for ((i = 0; i < ${#pids[@]}; i++)); do
        wait "${pids[$i]}" || failed+=("${targets[$i]}")
    done

    if [[ ${#failed[@]} -eq 0 ]]; then
        log "✓ All ${#targets[@]} targets synced."
    else
        log "✗ Failed: ${failed[*]}"
        return 1
    fi
}

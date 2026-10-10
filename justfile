# vexos-nix justfile
#
# Recipes live in just/*.just, imported below in the order their groups
# appear in `just --list` (root-file recipes list first, then each import in
# turn). Everything shares one namespace, so `just switch` etc. are unchanged.

# Disable the systemd pager for every recipe. systemctl spawns a pager when it
# thinks it has a terminal; if the pager cannot start (e.g. the host lacks a
# terminfo entry for the client's TERM), systemctl dies of SIGPIPE and exits
# 141. That made `if ! systemctl ...` guards report healthy units as missing.
export SYSTEMD_PAGER := ""

# How recipes call other recipes: the same `just` binary and justfile as this
# run, rather than whatever `just` is on PATH and whichever justfile the current
# directory happens to resolve to.
_just := quote(just_executable()) + " --justfile " + quote(justfile())

import 'just/system.just'
import 'just/admin.just'
import 'just/vpn.just'
import 'just/features.just'
import 'just/ai.just'
import 'just/storage.just'
import 'just/cache.just'
import 'just/server.just'
import 'just/server-enable.just'

# List all available recipes (default when running `just` with no arguments).
[private]
default:
    #!/usr/bin/env bash
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    # --unsorted keeps groups and recipes in file order (most-used first).
    heading="VexOS commands — ${variant:-variant unknown}"$'\n'
    heading+="Commands marked (menu) open a menu when run on their own. Search everything: just pick"$'\n\n'
    {{_just}} --list --unsorted --list-heading "$heading"
    if [[ "$variant" == *stateless* ]]; then
        echo ""
        echo "Active role: stateless (ephemeral / tmpfs root)"
        echo ""
        echo "Reminder:"
        echo "    The primary user account starts LOCKED (no password) until you"
        echo "    set one. Run 'sudo bash scripts/bare-metal-install.sh', or manually"
        echo "    create /etc/nixos/stateless-user-override.nix with a hash from"
        echo "    'mkpasswd -m sha-512'. Once set, the password persists across"
        echo "    reboots — it lives in that file, not on the wiped tmpfs root."
        echo ""
    fi

# Fuzzy-search every command and run the one you pick (needs fzf). Private so
# VexPortal's catalog does not report it as an unknown recipe; the default
# listing's heading advertises it instead. Recipes that need an argument are
# left out by `just --choose` itself.
[private]
pick:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v fzf >/dev/null 2>&1; then
        echo "error: fzf is not installed — run 'just' for the full list." >&2
        exit 1
    fi
    JUST="{{just_executable()}}"
    JF="{{justfile()}}"
    exec "$JUST" --justfile "$JF" --choose --chooser \
        "fzf --height=60% --reverse --prompt='just › ' --header='Type to filter · Enter to run · Esc to cancel' --preview='\"$JUST\" --justfile \"$JF\" --show {} 2>/dev/null | sed -n \"1,/^[^[]/p\"' --preview-window=down,5,wrap"

# Prompt for a yes/no confirmation, printing `prompt` verbatim and reading a
# response exactly as the inline call sites did before this helper existed.
# When VEXOS_ASSUME_YES=1 (set by the VexPortal daemon, never by a human
# session), skips the prompt and answers yes immediately.
# Usage: if [ "$(just _confirm 'Continue? [y/N]: ')" = "true" ]; then ... fi
[private]
_confirm prompt:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${VEXOS_ASSUME_YES:-}" = "1" ]; then
        echo "true"
        exit 0
    fi
    printf '%s' {{quote(prompt)}} >&2
    read -r ANSWER || true
    case "${ANSWER,,}" in
        y|yes) echo "true" ;;
        *)     echo "false" ;;
    esac

# Typed-keyword confirmation for destructive actions: the user must type "yes".
# VEXOS_ASSUME_YES=1 satisfies it too — the VexPortal daemon only sets it after
# its own destructive-action confirmation dialog has already run.
# Usage: if [ "$({{_just}} _confirm-typed)" = "true" ]; then ... fi
[private]
_confirm-typed:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${VEXOS_ASSUME_YES:-}" = "1" ]; then
        echo "true"
        exit 0
    fi
    read -r -p "Type 'yes' to continue: " ANSWER || true
    if [ "${ANSWER:-}" = "yes" ]; then echo "true"; else echo "false"; fi

# Shared menu + dispatcher behind the grouped recipes (vpn, feature, service, ...).
#   $1 group   $2 menu title   $3 action ("" = show the menu)
#   $4 extra arguments as ONE string (forwarded to the action)
#   $5.. items, each "key|description" or "key|description|prompt" — a prompt marks
#        an action that needs an argument and asks for it when none was given.
#        A 4th field (prompt may be empty) flags the action:
#          "stay" — read-only: picked from the menu it returns to the menu
#                   afterwards instead of exiting. Direct calls (`just vpn
#                   status`) always just run.
#          "warn" — disruptive or destructive: shown with a ⚠ in the menu.
# Runs the hidden recipe _<group>-<key>, so `just vpn up` == `just _vpn-up`.
[positional-arguments]
[private]
_menu group title action argstr *items:
    #!/usr/bin/env bash
    set -euo pipefail
    group="$1"; title="$2"; action="${3:-}"; argstr="${4:-}"
    shift 4
    keys=(); descs=(); prompts=(); stays=()
    for item in "$@"; do
        IFS='|' read -r k d p s <<< "$item"
        keys+=("$k"); descs+=("$d"); prompts+=("${p:-}"); stays+=("${s:-}")
    done

    # Colour only on a terminal that wants it (https://no-color.org); the
    # non-TTY path (VexPortal, pipes) prints plain usage text to stderr.
    B="" D="" C="" Y="" R=""
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        B=$'\e[1m' D=$'\e[2m' C=$'\e[36m' Y=$'\e[33m' R=$'\e[0m'
    fi
    cols=$(tput cols 2>/dev/null || echo 72)
    [ "$cols" -le 72 ] || cols=72

    usage() {
        echo "usage: just $group <action> [args]" >&2
        for i in "${!keys[@]}"; do
            printf "  %-14s %s\n" "${keys[$i]}" "${descs[$i]}" >&2
        done
    }

    picked=0
    while true; do
        if [ -z "$action" ]; then
            [ -t 0 ] || { usage; exit 1; }
            fill=$(( cols - ${#title} - 4 ))
            [ "$fill" -ge 3 ] || fill=3
            rule=$(printf '%*s' "$fill" '' | sed 's/ /─/g')
            echo ""
            printf '%s── %s %s%s\n\n' "$B" "$title" "$rule" "$R"
            for i in "${!keys[@]}"; do
                kc="$C"; mark=" "
                if [ "${stays[$i]}" = "warn" ]; then kc="$Y"; mark="${Y}⚠${R}"; fi
                printf "  %s%2d%s  %s%-12s%s %s %s\n" "$B" "$((i+1))" "$R" "$kc" "${keys[$i]}" "$R" "$mark" "${descs[$i]}"
            done
            printf "  %s%2d  quit%s\n\n" "$D" 0 "$R"
            while true; do
                read -r -p "Choice [1-${#keys[@]}, a name, or 0 to quit]: " sel || exit 0
                sel="${sel,,}"; sel="${sel// /}"
                case "$sel" in 0|q|quit) exit 0 ;; esac
                if [[ "$sel" =~ ^[0-9]+$ ]]; then
                    if [ "$sel" -ge 1 ] && [ "$sel" -le "${#keys[@]}" ]; then
                        action="${keys[$((sel-1))]}"
                    fi
                else
                    for i in "${!keys[@]}"; do
                        [ "${keys[$i]}" = "$sel" ] && action="$sel"
                    done
                fi
                if [ -n "$action" ]; then
                    picked=1
                    break
                fi
                echo "  Enter 1-${#keys[@]}, an action name, or 0 to quit."
            done
        fi

        idx=-1
        for i in "${!keys[@]}"; do
            [ "${keys[$i]}" = "$action" ] && idx=$i
        done
        if [ "$idx" -lt 0 ]; then
            echo "error: unknown action '$action'" >&2
            usage
            exit 1
        fi

        # Only a read-only item picked from the menu keeps the menu open.
        stay=""
        if [ "$picked" -eq 1 ] && [ "${stays[$idx]}" = "stay" ]; then stay=1; fi

        args=()
        [ -z "$argstr" ] || read -r -a args <<< "$argstr"
        if [ -n "${prompts[$idx]}" ] && [ "${#args[@]}" -eq 0 ]; then
            [ -t 0 ] || { echo "error: '$action' needs an argument: ${prompts[$idx]}" >&2; usage; exit 1; }
            read -r -p "${prompts[$idx]}: " a || a=""
            if [ -z "$a" ]; then
                echo "cancelled" >&2
                if [ -n "$stay" ]; then action=""; continue; fi
                exit 1
            fi
            args=("$a")
        fi

        if [ -n "$stay" ]; then
            {{_just}} "_${group}-${action}" "${args[@]}" || true
            # Hold the output on screen until the user is done reading it.
            read -r -s -p "${D}Press Enter to return to the menu…${R}" _ || exit 0
            echo ""
            action=""
            continue
        fi
        exec {{_just}} "_${group}-${action}" "${args[@]}"
    done

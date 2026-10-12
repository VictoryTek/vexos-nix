# just/lib.sh — shell helpers shared by the justfile's bash recipes.
# Sourced, not executed:  source "{{justfile_directory()}}/just/lib.sh"
# Lives in just/ (not scripts/lib/) because just/ is deployed and relinked
# alongside /etc/nixos/justfile on every role, stateless included.
# shellcheck shell=bash

# Directory holding the justfile (/etc/nixos on a host, the repo in a checkout).
VEXOS_JF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# nix_set FILE OPTION VALUE
# Set OPTION to VALUE (a literal Nix expression: true, "a string", [ "x" ]) in
# one of the flat /etc/nixos side-files, keeping any trailing comment and never
# leaving two lines for one option:
#   - an uncommented line for the option exists -> rewritten in place; commented
#     template lines are left alone;
#   - only commented template lines exist -> the first is uncommented in place;
#   - neither exists -> the line is added before the file's closing brace.
nix_set() {
    local file="$1" opt="$2" val="$3" opt_re val_esc
    opt_re="${opt//./\\.}"
    # Escape the sed replacement's special characters: \ & and the | delimiter.
    val_esc=$(printf '%s' "$val" | sed -e 's/[\\&|]/\\&/g')
    if grep -qP "^\s*${opt_re}\s*=" "$file" 2>/dev/null; then
        sudo sed -i -E "s|^(\s*)${opt_re}\s*=\s*[^;]*;|\1${opt} = ${val_esc};|" "$file"
    elif grep -qP "^\s*#\s*${opt_re}\s*=" "$file" 2>/dev/null; then
        sudo sed -i -E "0,/^\s*#\s*${opt_re}\s*=/ s|^(\s*)#\s*${opt_re}\s*=\s*[^;]*;|\1${opt} = ${val_esc};|" "$file"
    else
        sudo sed -i "\$ s|^}|  ${opt} = ${val_esc};\n}|" "$file"
    fi
}

# nix_is_set FILE OPTION VALUE — true if an uncommented line sets OPTION to VALUE.
nix_is_set() {
    local file="$1" opt_re="${2//./\\.}" val_re
    val_re=$(printf '%s' "$3" | sed -e 's/[][\\.^$*+?(){}|]/\\&/g')
    grep -qP "^\s*${opt_re}\s*=\s*${val_re}\s*;" "$1" 2>/dev/null
}

# nix_get_str FILE OPTION — print the string value of an uncommented
# `OPTION = "...";` line (nothing when the option is unset).
nix_get_str() {
    local file="$1" opt_re="${2//./\\.}"
    grep -oP "^\s*${opt_re}\s*=\s*\"\K[^\"]*" "$file" 2>/dev/null | head -1 || true
}

# public_url_info SERVICE — print "option|default-port|default-host|required"
# for a service whose module has an option holding the address users type to
# reach it. Behind a reverse proxy its http://<host>:<port> default breaks the
# app (rejected origins, bad links), so `just service enable` / `set-url` ask
# for it. default-host is "hostname" or "localhost"; required is "yes" where
# the module's default is an invalid placeholder guarded by a build assertion.
# Returns 1 for a service with no such option.
# Keep in sync with the options in modules/server/*.nix.
public_url_info() {
    case "$1" in
        wishlist)     echo "origin|3280|hostname|no" ;;
        joplin)       echo "baseUrl|22300|hostname|no" ;;
        mediamanager) echo "frontendUrl|8000|hostname|no" ;;
        arcane)       echo "appUrl|3552|localhost|no" ;;
        vaultwarden)  echo "domain|||yes" ;;
        headscale)    echo "serverUrl|||yes" ;;
        *)            return 1 ;;
    esac
}

# prompt_public_url FILE SERVICE
# Ask for SERVICE's public URL and write it as vexos.server.<SERVICE>.<option>.
#   - Enter keeps the module default and writes nothing; vaultwarden and
#     headscale have no usable default, so for them an answer is required.
#   - The answer must start with http:// or https://; trailing slashes are
#     dropped and invalid input is re-asked.
#   - An option that is already set is shown and only changed on a "y".
#   - Without a terminal (VexPortal runs recipes with stdin closed) nothing is
#     asked, so enabling a service never blocks or fails on it.
# Returns 0 if a value was written, 1 if nothing was changed (including a
# service that has no public-URL option).
prompt_public_url() {
    local file="$1" svc="$2" info opt port host required opt_full cur ans dflt prompt set_port
    info=$(public_url_info "$svc") || return 1
    IFS='|' read -r opt port host required <<< "$info"
    opt_full="vexos.server.${svc}.${opt}"

    if [ ! -t 0 ]; then
        echo "  Public URL for $svc not asked (no terminal) — run 'just service set-url $svc' if it is served behind a reverse proxy."
        return 1
    fi

    cur=$(nix_get_str "$file" "$opt_full")
    if [ -n "$cur" ]; then
        echo "  Public URL for $svc is currently $cur"
        read -r -p "  Change it? [y/N] " ans || return 1
        [[ "$ans" =~ ^[Yy]$ ]] || return 1
    fi

    if [ "$required" = yes ]; then
        prompt="  Public URL for $svc (the address users type, e.g. https://$svc.example.org) — required: "
    else
        set_port=$(grep -oP "^\s*vexos\.server\.${svc}\.port\s*=\s*\K[0-9]+" "$file" 2>/dev/null | head -1 || true)
        if [ -n "$set_port" ]; then port="$set_port"; fi
        if [ "$host" = localhost ]; then dflt="http://localhost:${port}"; else dflt="http://$(uname -n):${port}"; fi
        prompt="  Public URL for $svc (the address users type, e.g. https://$svc.example.org). Press Enter to keep the default $dflt: "
    fi

    while true; do
        read -r -p "$prompt" ans || return 1
        if [ -z "$ans" ]; then
            [ "$required" = yes ] || return 1
            echo "  $svc has no usable default — enter its public URL."
            continue
        fi
        while [[ "$ans" == */ ]]; do ans="${ans%/}"; done
        # Only characters that are safe inside a Nix string and nix_set's sed
        # replacement: no space, quote, backslash, $ or ;.
        if printf '%s' "$ans" | grep -qP '^https?://[A-Za-z0-9\[][A-Za-z0-9._~:/?#@%+=&,\[\]-]*$'; then
            break
        fi
        echo "  Invalid URL. It must start with http:// or https:// (e.g. https://$svc.example.org)."
    done

    nix_set "$file" "$opt_full" "\"${ans}\""
    echo "✓ Set $opt_full = $ans"
}

# nix_disable FILE OPTION — flip an uncommented `OPTION = true;` to false in
# place, keeping indentation, padding and any trailing comment. Commented-out
# lines are left alone. Returns 0 if a line was changed, 1 if none was enabled.
nix_disable() {
    local file="$1" opt_re="${2//./\\.}"
    nix_is_set "$file" "$2" true || return 1
    sudo sed -i -E "s|^(\s*${opt_re}\s*=\s*)true(\s*;)|\1false\2|" "$file"
}

# arr_any_enabled FILE — true if the *arr stack is enabled as a whole
# (vexos.server.arr.enable) or through any per-component flag
# (vexos.server.arr.<component>.enable) on an uncommented line.
arr_any_enabled() {
    grep -qP '^\s*vexos\.server\.arr\.(\w+\.)?enable\s*=\s*true\s*;' "$1" 2>/dev/null
}

# seed_from_template NAME DEST
# Copy template/NAME to DEST (as root, CRLF stripped) from the first known
# location. Prints an error and returns 1 when no copy of the template exists.
seed_from_template() {
    local name="$1" dest="$2" dir
    for dir in "$VEXOS_JF_DIR" /etc/nixos "$HOME/Projects/vexos-nix"; do
        if [ -f "$dir/template/$name" ]; then
            sudo cp "$dir/template/$name" "$dest"
            sudo sed -i 's/\r//' "$dest"  # strip CRLF if checked out on Windows
            return 0
        fi
    done
    echo "error: cannot find template/$name in any known location" >&2
    echo "searched: $VEXOS_JF_DIR /etc/nixos $HOME/Projects/vexos-nix" >&2
    return 1
}

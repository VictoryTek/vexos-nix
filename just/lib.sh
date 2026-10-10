# just/lib.sh — shell helpers shared by the justfile's bash recipes.
# Sourced, not executed:  source "{{justfile_directory()}}/just/lib.sh"
# Lives in just/ (not scripts/lib/) because just/ is deployed and relinked
# alongside /etc/nixos/justfile on every role, stateless included.
# shellcheck shell=bash

# Directory holding the justfile (/etc/nixos on a host, the repo in a checkout).
VEXOS_JF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# nix_set FILE OPTION VALUE
# Set OPTION to VALUE (a literal Nix expression: true, "a string", [ "x" ]) in
# one of the flat /etc/nixos side-files. A line for the option that already
# exists — commented out or not — is rewritten in place, keeping any trailing
# comment; otherwise the line is added before the file's closing brace.
nix_set() {
    local file="$1" opt="$2" val="$3" opt_re val_esc
    opt_re="${opt//./\\.}"
    # Escape the sed replacement's special characters: \ & and the | delimiter.
    val_esc=$(printf '%s' "$val" | sed -e 's/[\\&|]/\\&/g')
    if grep -qP "^\s*#?\s*${opt_re}\s*=" "$file" 2>/dev/null; then
        sudo sed -i -E "s|^(\s*)#?\s*${opt_re}\s*=\s*[^;]*;|\1${opt} = ${val_esc};|" "$file"
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

# pkgs/vexos-prune-services/prune.awk
# Filter dead vexos.server.<name> statements out of a server-services.nix.
#
# Input : the host's server-services.nix
# Output: the same file with dead statements dropped (stdout)
# Side   : one line per dead name written to `deadfile`, as "<name> <true|false>"
#          where the flag records whether the entry was set enable = true.
#
# -v valid="<space separated known names>"
# -v deadfile="<path>"
#
# A statement is dead when the first path segment after "vexos.server." is not
# in `valid`. Comments are ignored for matching, so the commented-out catalogue
# that ships in template/server-services.nix survives untouched.

BEGIN {
    n = split(valid, known, " ")
    for (i = 1; i <= n; i++) ok[known[i]] = 1
    skip = 0
    depth = 0
}

{
    # Analyse the code part only; a "#" starts a comment in Nix.
    code = $0
    sub(/#.*/, "", code)

    if (!skip && match(code, /^[ \t]*vexos\.server\.[A-Za-z0-9_-]+/)) {
        seg = substr(code, RSTART, RLENGTH)
        sub(/^[ \t]*vexos\.server\./, "", seg)
        if (!(seg in ok)) {
            skip = 1
            depth = 0
            current = seg
            enabled[current] = 0
        }
    }

    if (skip) {
        if (code ~ /enable[ \t]*=[ \t]*true/) enabled[current] = 1

        opened = gsub(/[{[]/, "", code)
        closed = gsub(/[}\]]/, "", code)
        depth += opened - closed

        # A statement ends when every brace it opened is closed and the line
        # terminates with ";". Until then it keeps consuming lines.
        if (depth <= 0 && code ~ /;[ \t]*$/) skip = 0
        next
    }

    print
}

END {
    for (name in enabled) printf "%s %s\n", name, (enabled[name] ? "true" : "false") > deadfile
}

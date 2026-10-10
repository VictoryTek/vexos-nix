# just/cache.just — Binary caches (Attic, Harmonia) and the custom kernel builder.
# Imported by the root justfile; recipe names share one namespace.

# Binary caches: Attic (push/bootstrap) and Harmonia (status and client config).
[group('Binary Cache')]
[doc('Binary caches: Attic push/bootstrap, Harmonia status (menu)')]
cache action="" *args:
    @{{_just}} _menu cache "Binary cache" {{quote(action)}} {{quote(args)}} \
        "push|Build this repo's custom packages and push them to Attic (optional: cache)" \
        "bootstrap|One-time Attic setup: create the cache and mint tokens (optional: cache)" \
        "harmonia|Check Harmonia is live and print the client configuration||stay"

# Custom kernel builder (server): build now, check status, follow the log.
[group('Binary Cache')]
[doc('Custom kernel builder: build now, status, follow the log (menu)')]
kernel action="" *args:
    @{{_just}} _menu kernel "Custom kernel builder" {{quote(action)}} {{quote(args)}} \
        "now|Build the kernel now instead of waiting for the nightly timer (optional: name)" \
        "status|Show build status and the pinned kernel version||stay" \
        "log|Follow a build log live (optional: name)"

# Build this repo's custom pkgs/* packages and push them to a configured Attic
# cache. Requires `attic login <cache> <url> <token>` to have already been run
# once (see `just service enable attic`'s setup guidance). Usage: just cache push [cache]
[private]
[arg('cache', pattern='[A-Za-z0-9][A-Za-z0-9._-]*')]
_cache-push cache="vexos":
    #!/usr/bin/env bash
    set -euo pipefail
    CACHE={{quote(cache)}}

    if ! command -v attic &>/dev/null; then
        echo "error: 'attic' CLI not found on PATH." >&2
        echo "  Install it, then run: attic login ${CACHE} <url> <token>" >&2
        echo "  See 'just service enable attic' for setup guidance." >&2
        exit 1
    fi

    PACKAGES="cockpit-navigator cockpit-file-sharing cockpit-identities brave-origin kiji-proxy vexos-update"

    # Some packages (kiji-proxy) use a placeholder hash until `just service enable
    # kiji-proxy` patches it in locally, so a single package failing to build
    # shouldn't abort the whole push — build/push each independently and
    # report a summary at the end.
    FAILED=""
    BUILD_LOG=$(mktemp)
    trap 'rm -f "$BUILD_LOG"' EXIT
    echo "Building and pushing custom packages..."
    for pkg in $PACKAGES; do
        echo "  building vexos.${pkg}..."
        if out_path=$(nix build --impure --no-link --print-out-paths \
            ".#nixosConfigurations.vexos-desktop-amd.pkgs.vexos.${pkg}" 2>"$BUILD_LOG"); then
            echo "  pushing ${pkg} -> ${CACHE}..."
            if ! attic push "${CACHE}" "$out_path"; then
                echo "  ✗ push failed: ${pkg}" >&2
                FAILED="$FAILED $pkg"
            fi
        else
            echo "  ✗ build failed: ${pkg} (skipping — run 'just service enable ${pkg}' first if it needs a one-time setup step)" >&2
            tail -5 "$BUILD_LOG" >&2
            FAILED="$FAILED $pkg"
        fi
    done

    echo ""
    if [ -n "$FAILED" ]; then
        echo "✗ Pushed with failures. Skipped/failed:${FAILED}" >&2
        exit 1
    fi
    echo "✓ Pushed all custom packages to Attic cache '${CACHE}'."

# One-time Attic cache bootstrap: mint an admin token, create the cache if it
# doesn't exist, print the public key for client substituter config, and mint
# a push-only token for CI (e.g. GitHub Actions). Run once after `just service enable
# attic && just rebuild`. Safe to re-run — cache creation is idempotent.
# Usage: just cache bootstrap [cache]
[private]
[arg('cache', pattern='[A-Za-z0-9][A-Za-z0-9._-]*')]
_cache-bootstrap cache="vexos":
    #!/usr/bin/env bash
    set -euo pipefail
    CACHE={{quote(cache)}}

    if ! systemctl is-active --quiet atticd; then
        echo "error: atticd.service is not running." >&2
        echo "  Run 'just service enable attic && just rebuild' first." >&2
        exit 1
    fi

    if ! command -v attic &>/dev/null; then
        echo "error: 'attic' CLI not found on PATH." >&2
        echo "  It's installed automatically when Attic is enabled — run 'just rebuild' first." >&2
        exit 1
    fi

    echo "Minting a local admin token..."
    ADMIN_TOKEN=$(sudo atticd-atticadm make-token --sub "admin" \
        --pull "*" --push "*" --delete "*" \
        --create-cache "*" --configure-cache "*" --configure-cache-retention "*" \
        --validity "10 years")

    attic login local http://localhost:8400 "$ADMIN_TOKEN" >/dev/null

    if attic cache info "${CACHE}" &>/dev/null; then
        echo "Cache '${CACHE}' already exists — skipping creation."
    else
        echo "Creating cache '${CACHE}'..."
        attic cache create "${CACHE}"
    fi

    PUBLIC_KEY=$(attic cache info "${CACHE}" | grep -oP '(?<=Public Key: ).*')

    echo "Minting a push-only token for CI..."
    PUSH_TOKEN=$(sudo atticd-atticadm make-token --sub "github-actions" \
        --push "${CACHE}" --validity "1 year")

    echo ""
    echo "=========================================================="
    echo " Attic bootstrap complete"
    echo "=========================================================="
    echo ""
    echo "Admin token (private — keep for your own future cache administration):"
    echo "  $ADMIN_TOKEN"
    echo ""
    echo "Client substituter config (safe to commit — paste into e.g."
    echo "configuration-desktop.nix or a host-specific file):"
    echo "  vexos.attic.cacheUrl  = \"http://<server-ip>:8400/${CACHE}\";"
    echo "  vexos.attic.publicKey = \"$PUBLIC_KEY\";"
    echo ""
    echo "CI push token (secret — add as a GitHub Actions repo secret,"
    echo "e.g. ATTIC_PUSH_TOKEN):"
    echo "  $PUSH_TOKEN"
    echo ""

# Verify the Harmonia binary cache is live and print client configuration.
# Harmonia has no bootstrap step — the signing key is generated automatically
# on rebuild and there are no tokens or logins — so this recipe exists purely
# to answer "is it ready?" and "what do I paste on the other machines?".
# Usage: just cache harmonia
[private]
_cache-harmonia:
    #!/usr/bin/env bash
    set -euo pipefail

    PORT=5000

    # The signing key path is configurable, and the sops backend forces it into
    # /run/secrets (modules/secrets-sops.nix) — so resolve it from the running
    # configuration rather than assuming the default location.
    KEY="/var/lib/harmonia/cache-priv-key.pem"
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || true)
    if [ -n "$target" ]; then
        RESOLVED=$(nix eval --impure --raw \
            "path:/etc/nixos#nixosConfigurations.${target}.config.vexos.server.harmonia.signKeyPath" \
            2>/dev/null || true)
        if [ -n "$RESOLVED" ]; then
            KEY="$RESOLVED"
        fi
    fi

    # harmonia.service is socket-activated (harmonia.socket) — it is
    # legitimately "inactive (dead)" whenever idle. Check the socket, since
    # that's what determines whether the cache is actually ready to serve.
    if ! systemctl is-active --quiet harmonia.socket; then
        echo "error: harmonia.socket is not running." >&2
        echo "  Run 'just service enable harmonia && just rebuild' first." >&2
        echo "  Then check: systemctl status harmonia.socket" >&2
        exit 1
    fi

    # /nix-cache-info is the first document any Nix client fetches. If this
    # returns, the cache is genuinely serving — not merely "the unit started".
    echo "Probing http://localhost:${PORT}/nix-cache-info ..."
    if ! CACHE_INFO=$(curl -fsS --max-time 5 "http://localhost:${PORT}/nix-cache-info"); then
        echo "error: harmonia.service is active but not answering on port ${PORT}." >&2
        echo "  Check: journalctl -u harmonia -n 50" >&2
        exit 1
    fi

    # Prefer the .pub written next to the key by the activation script. Under
    # the sops backend no .pub exists (the secret is the private half only, 0400
    # root), so fall back to deriving the public half from the private key —
    # which needs root, hence sudo.
    if [ -r "${KEY}.pub" ]; then
        PUBLIC_KEY=$(cat "${KEY}.pub")
    else
        # `sudo nix ... < "$KEY"` would not work: the redirect is opened by the
        # calling (unprivileged) shell. Read the key as root, convert as user.
        echo "No readable ${KEY}.pub — deriving the public key from $KEY (needs sudo)."
        if ! PUBLIC_KEY=$(sudo cat "$KEY" | nix --extra-experimental-features nix-command \
                key convert-secret-to-public); then
            echo "error: could not read or convert the signing key at $KEY." >&2
            echo "  Confirm it exists:  sudo ls -l $KEY" >&2
            echo "  If it is missing, it is generated on activation — try 'just rebuild'." >&2
            exit 1
        fi
    fi
    HOST=$(hostname)

    echo ""
    echo "=========================================================="
    echo " Harmonia is live"
    echo "=========================================================="
    echo ""
    echo "$CACHE_INFO" | sed 's/^/  /'
    echo ""
    echo "Client config (safe to commit — paste into /etc/nixos/features.nix,"
    echo "a host file, or configuration-desktop.nix on your other machines):"
    echo "  vexos.harmonia.cacheUrl  = \"http://${HOST}:${PORT}\";"
    echo "  vexos.harmonia.publicKey = \"${PUBLIC_KEY}\";"
    echo ""
    echo "Note: Harmonia serves only what is currently in THIS host's"
    echo "      /nix/store, and nix.settings min-free/max-free will garbage-"
    echo "      collect unreferenced paths. Pin anything that must stay served:"
    echo "        nix-store --add-root /var/lib/harmonia/roots/<name> -r <store-path>"
    echo ""

# These recipes drive modules/server/kernel-builder.nix. Run them on the host
# that builds kernels (the one running Harmonia), not on a desktop.

# Build a custom kernel now instead of waiting for the nightly timer.
# Takes hours and runs in the background — safe to disconnect.
# Usage: just kernel now [name]
[private]
[arg('name', pattern='[A-Za-z0-9][A-Za-z0-9._-]*')]
_kernel-now name="ogc":
    #!/usr/bin/env bash
    set -euo pipefail
    NAME={{quote(name)}}
    UNIT="kernel-build-${NAME}"

    if ! systemctl list-unit-files "${UNIT}.service" &>/dev/null \
       || ! systemctl cat "${UNIT}.service" &>/dev/null; then
        echo "error: ${UNIT}.service does not exist." >&2
        echo "  Enable the builder first: just service enable kernel-builder && just rebuild" >&2
        exit 1
    fi

    if systemctl is-active --quiet "$UNIT"; then
        echo "A build is already running. Watch it with: just kernel log ${NAME}"
        exit 0
    fi

    echo "Starting ${UNIT}..."
    sudo systemctl start --no-block "$UNIT"
    echo ""
    echo "Build started in the background. It takes hours on modest hardware."
    echo "  Watch:  just kernel log ${NAME}"
    echo "  Status: just kernel status"

# Show custom kernel build status: running or not, how long, last result,
# and which version is currently pinned and served.
[private]
_kernel-status:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob

    found=0
    for unit in /etc/systemd/system/kernel-build-*.service \
                /run/systemd/system/kernel-build-*.service \
                /etc/systemd/system/*.wants/kernel-build-*.service; do
        name=$(basename "$unit" .service)
        [ -n "$name" ] || continue
        found=1
        printf "\n\033[1m%s\033[0m\n" "$name"

        if systemctl is-active --quiet "$name"; then
            since=$(systemctl show -p ActiveEnterTimestamp --value "$name" 2>/dev/null || echo "")
            printf "  State:    \033[33mBUILDING\033[0m (since %s)\n" "${since:-unknown}"
        else
            result=$(systemctl show -p Result --value "$name" 2>/dev/null || echo "unknown")
            last=$(systemctl show -p ExecMainExitTimestamp --value "$name" 2>/dev/null || echo "")
            if [ "$result" = "success" ]; then
                printf "  State:    \033[32midle\033[0m (last run: success%s)\n" \
                    "${last:+, $last}"
            else
                printf "  State:    \033[31midle (last run: %s)\033[0m\n" "$result"
                echo   "  Logs:     just kernel log ${name#kernel-build-}"
            fi
        fi

        next=$(systemctl show -p NextElapseUSecRealtime --value "${name}.timer" 2>/dev/null || echo "")
        [ -n "$next" ] && [ "$next" != "0" ] && printf "  Next run: %s\n" "$next"
    done

    if [ "$found" = "0" ]; then
        echo "No kernel build units found."
        echo "  Enable the builder: just service enable kernel-builder && just rebuild"
        exit 0
    fi

    echo ""
    # pkgs/ is not deployed next to /etc/nixos/justfile, so fall back to the
    # locked vexos-nix flake input — the pins this host actually builds.
    PKGS_DIR="{{justfile_directory()}}/pkgs"
    if [ ! -d "$PKGS_DIR/kernels" ]; then
        _src=$(nix eval --impure --raw --expr \
            '(builtins.getFlake "git+file:///etc/nixos").inputs.vexos-nix.outPath' 2>/dev/null || true)
        PKGS_DIR="${_src}/pkgs"
    fi
    echo "Pinned kernel versions (pkgs/kernels/*/version.json):"
    _pins=("$PKGS_DIR"/kernels/*/version.json)
    [ "${#_pins[@]}" -gt 0 ] || echo "  (could not locate pkgs/kernels)"
    for f in "${_pins[@]}"; do
        k=$(basename "$(dirname "$f")")
        printf "  %-10s %s\n" "$k" "$(grep -oP '\"tag\"\s*:\s*\"\K[^\"]+' "$f" 2>/dev/null || echo '?')"
    done

# Follow a custom kernel build's log output live.
# Usage: just kernel log [name]
[private]
[arg('name', pattern='[A-Za-z0-9][A-Za-z0-9._-]*')]
_kernel-log name="ogc":
    journalctl -fu {{quote("kernel-build-" + name)}}

# Spec: Maintainerr + Individually-Selectable Arr Services

## Current State Analysis

- `modules/server/arr.nix` declares a single `vexos.server.arr.enable` flag.
  When true, it unconditionally enables SABnzbd, Sonarr, Radarr, Lidarr, and
  Prowlarr together (`lib.mkIf cfg.enable { services.sabnzbd.enable = true; ... }`).
  `qbittorrent` and `bazarr` are already independent opt-in sub-flags
  (`vexos.server.arr.qbittorrent.enable`, `vexos.server.arr.bazarr.enable`),
  gated by assertions requiring `cfg.enable = true` first.
- `justfile`'s `enable <service>` recipe (line 1625) is generic: it toggles
  `vexos.server.<service>.enable = true;` in `/etc/nixos/server-services.nix`
  via sed, with special-cased interactive prompts already present for
  `plex`, `proxmox`, `backup`, and an auto-generated secret for `searxng`/`vexboard`.
  This is the pattern to extend for `arr`.
- `disable <service>` (line 2394) is generic and only flips the single
  `vexos.server.<service>.enable` flag to false.
- `service-info` (`_info`, line 1358) prints per-service access info; the
  no-arg mode (line 1464) detects "enabled" services by grepping for
  `vexos.server.<svc>.enable = true;` in the services file.
- `status <service>` (line 1479) maps `arr` to a fixed list of 5 systemd
  units/URLs to check.
- No NixOS/nixpkgs package or module exists for Maintainerr (checked stable
  `nixos-26.05` and `nixpkgs-unstable` — no `maintainerr` attribute in either).
  It ships only as a Docker image, so it must follow this repo's established
  OCI-container pattern (see `modules/server/arcane.nix`,
  `modules/server/stirling-pdf.nix`): `virtualisation.oci-containers.containers.*`.
  Latest stable image as of 2026-07-11: `ghcr.io/maintainerr/maintainerr:3.17.1`
  (project renamed org from `jorenn92` to `maintainerr` on GitHub/GHCR).
  Container listens on port 6246, persists state under `/opt/data`, and reads
  `TZ` from the environment (matches `config.time.timeZone` convention already
  used in `modules/server/authelia.nix`).

## Problem Definition

1. Add Maintainerr (automated Plex/Jellyfin/Emby library cleanup) as a new
   component of the arr stack.
2. Let `just enable arr` prompt: enable the **full** arr stack, or select
   **individual** components. If individual, accept a space- or
   comma-separated list of component names and enable only those.

## Proposed Solution

### 1. `modules/server/arr.nix` — per-component enable options

Give every core service (`sabnzbd`, `sonarr`, `radarr`, `lidarr`, `prowlarr`)
its own `enable` sub-option, matching the existing `qbittorrent`/`bazarr`
pattern, plus a new `maintainerr` sub-option. `vexos.server.arr.enable`
becomes a convenience meta-flag: when true, it defaults (via `lib.mkDefault`)
all five core sub-options to true, but each remains independently settable.
This is the standard "option gated by an option the same module declares"
carve-out in the Module Architecture Pattern — not role-smuggling.

```nix
options.vexos.server.arr = {
  enable = lib.mkEnableOption "Arr stack (SABnzbd, Sonarr, Radarr, Lidarr, Prowlarr) — enables all core services";
  sabnzbd.enable     = lib.mkEnableOption "SABnzbd Usenet downloader — part of the arr stack";
  sonarr.enable      = lib.mkEnableOption "Sonarr TV management — part of the arr stack";
  radarr.enable      = lib.mkEnableOption "Radarr movie management — part of the arr stack";
  lidarr.enable      = lib.mkEnableOption "Lidarr music management — part of the arr stack";
  prowlarr.enable    = lib.mkEnableOption "Prowlarr indexer manager — part of the arr stack";
  qbittorrent.enable = lib.mkEnableOption "qBittorrent torrent client (part of the arr stack)"; # unchanged
  bazarr.enable      = lib.mkEnableOption "Bazarr subtitle manager (part of the arr stack)";      # unchanged
  maintainerr.enable = lib.mkEnableOption "Maintainerr automated library cleanup (part of the arr stack)";
  maintainerr.port = lib.mkOption {
    type = lib.types.port;
    default = 6246;
    description = "Port Maintainerr's web UI listens on.";
  };
};

config = lib.mkMerge [
  (lib.mkIf cfg.enable {
    vexos.server.arr.sabnzbd.enable  = lib.mkDefault true;
    vexos.server.arr.sonarr.enable   = lib.mkDefault true;
    vexos.server.arr.radarr.enable   = lib.mkDefault true;
    vexos.server.arr.lidarr.enable   = lib.mkDefault true;
    vexos.server.arr.prowlarr.enable = lib.mkDefault true;
  })
  (lib.mkIf cfg.sabnzbd.enable  { services.sabnzbd  = { enable = true; openFirewall = true; }; })
  (lib.mkIf cfg.sonarr.enable   { services.sonarr   = { enable = true; openFirewall = true; }; })
  (lib.mkIf cfg.radarr.enable   { services.radarr   = { enable = true; openFirewall = true; }; })
  (lib.mkIf cfg.lidarr.enable   { services.lidarr   = { enable = true; openFirewall = true; }; })
  (lib.mkIf cfg.prowlarr.enable { services.prowlarr = { enable = true; openFirewall = true; }; })
  (lib.mkIf cfg.qbittorrent.enable { services.qbittorrent = { enable = true; openFirewall = true; webuiPort = 8081; torrentingPort = 6881; }; })
  (lib.mkIf cfg.bazarr.enable      { services.bazarr      = { enable = true; openFirewall = true; }; })
  (lib.mkIf cfg.maintainerr.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    virtualisation.oci-containers.containers.maintainerr = {
      image = "ghcr.io/maintainerr/maintainerr:3.17.1";
      ports = [ "${toString cfg.maintainerr.port}:6246" ];
      volumes = [ "maintainerr-data:/opt/data" ];
      environment = { TZ = config.time.timeZone; };
    };
    networking.firewall.allowedTCPPorts = [ cfg.maintainerr.port ];
  })
  {
    users.users.${config.vexos.user.name}.extraGroups =
      lib.optional cfg.sabnzbd.enable "sabnzbd"
      ++ lib.optional cfg.sonarr.enable "sonarr"
      ++ lib.optional cfg.radarr.enable "radarr"
      ++ lib.optional cfg.lidarr.enable "lidarr"
      ++ lib.optional cfg.qbittorrent.enable "qbittorrent"
      ++ lib.optional cfg.bazarr.enable "bazarr";
  }
];
```

The old assertions requiring `cfg.enable` before `qbittorrent`/`bazarr` are
removed — every sub-component is now independently enable-able by design, so
the constraint no longer applies.

### 2. `justfile` — interactive full/individual prompt for `enable arr`

Extend the existing special-case block pattern (used for `plex`, `proxmox`,
`backup`) in the `enable` recipe. Add a small helper to avoid duplicating the
existing "insert-or-replace a `key = value;` line in `$SVC_FILE`" sed logic
(currently inlined 3+ times) — factor it into a bash function
`_set_flag OPTION VALUE` used by the new arr logic (and left available for,
but not forced onto, the pre-existing call sites, to keep the diff minimal —
only the new arr code path uses it).

New flow when `SERVICE = "arr"`, inserted right after the base
`OPTION="vexos.server.${SERVICE}.enable"` toggle logic and before the
generic "already enabled" / insert-or-replace block runs for `arr` specifically
(the generic block is skipped for `arr` and replaced by this dedicated path):

```
if [ "$SERVICE" = "arr" ]; then
    echo "  Enable the full *arr stack, or select individual components?"
    read -r -p "  [F]ull / [i]ndividual: " _arr_mode
    ARR_COMPONENTS="sabnzbd sonarr radarr lidarr prowlarr qbittorrent bazarr maintainerr"
    if [[ "$_arr_mode" =~ ^[Ii]$ ]]; then
        read -r -p "  Enter components (space or comma separated: ${ARR_COMPONENTS// /, }): " _arr_selected
        _arr_selected="${_arr_selected//,/ }"
        _arr_enabled=""
        for _c in $_arr_selected; do
            if ! echo "$ARR_COMPONENTS" | tr ' ' '\n' | grep -qx "$_c"; then
                echo "  error: unknown arr component '$_c' — skipping"
                continue
            fi
            _set_flag "vexos.server.arr.${_c}.enable" true
            _arr_enabled="$_arr_enabled $_c"
        done
        if [ -z "$_arr_enabled" ]; then
            echo "  error: no valid components selected" >&2
            exit 1
        fi
        echo "✓ Enabled arr components:$_arr_enabled"
    else
        _set_flag "$OPTION" true
        echo "✓ Enabled: $SERVICE (full stack)"
    fi
    # ... fall through to the existing vexboard auto-enable + closing
    # "Run 'just rebuild' to apply." + case-based access-info block, using
    # a variant of the `arr)` info case that reflects what was actually enabled.
    ARR_HANDLED=true
fi
```

The existing generic block (the `grep -q "${OPTION}\s*=\s*true"` /
insert-or-replace logic, and the final `echo "✓ Enabled: $SERVICE"`) must be
skipped when `ARR_HANDLED=true` to avoid double-processing — wrap that
section in `if [ "${ARR_HANDLED:-false}" != "true" ]; then ... fi`, or
simply `continue`/return early via the arr branch handling its own
`echo "  → Run 'just rebuild' to apply."` and case block, then exiting the
script before reaching the generic path. Exiting early (`exit 0` at the end
of the arr branch, after printing the same access-info the `arr)` case would
print) is simplest and keeps the diff localized to one new `if` block near
the top of the recipe, rather than threading a flag through the rest of the
script.

The closing `arr)` case in the access-info `case "$SERVICE" in` block
(line 1833) must become conditional on what was actually enabled instead of
unconditionally listing all 5 core services + assuming qbittorrent/bazarr/
maintainerr are absent. Since the arr branch now exits early with its own
tailored info print (listing exactly the components enabled, with their
ports, e.g. `SABnzbd → :8080` only if sabnzbd was selected, plus
`Maintainerr → :6246` if selected), the old static `arr)` case is replaced
by this dynamic version and only reached from the "full" path (where all 5
core ports are always printed, matching current behavior) — the individual
path prints its own subset directly in the new `if` block instead of falling
into the `case` at all.

### 3. `justfile` — `disable arr` must handle both modes

Currently `disable <service>` only flips the single top-level
`vexos.server.arr.enable` flag. With individual mode, that flag is never
set, so `disable arr` after an individual enable would silently no-op. Add
an `arr`-specific branch to `disable`: after the generic top-level-flag
check, additionally sweep for any `vexos.server.arr.<component>.enable = true;`
line (for all 8 components) and flip each to `false`. This keeps `disable arr`
correct regardless of which mode was used to enable it, with no new command
surface for the user.

### 4. `justfile` — `service-info` (no-arg) detection

The no-arg enabled-services loop (line 1464) only matches the top-level
`vexos.server.arr.enable = true;` line. Add an `arr`-specific fallback: if
the top-level flag isn't found, also check for any
`vexos.server.arr.<component>.enable = true;` line before deciding `arr` is
enabled. The `_info arr)` case itself (line 1367) becomes dynamic: read
`$SVC_FILE`, and if the top-level flag is true print all 5 core ports
(existing static string, unchanged) plus Maintainerr's port if that flag is
also true; if the top-level flag is false, print only the components whose
individual flag is true, each with its known port.

### 5. `justfile` — `status arr`

Add `maintainerr` to the existing static `UNITS`/`URLS` pair for `arr`
(line 1496) — `status` already tolerates checking units that aren't present
(reports inactive/not-found), so no dynamic logic is needed here, just
extend the two space-separated strings with `podman-maintainerr` (n.b.:
actual oci-container systemd unit name — confirm exact unit naming
convention used by other oci-container services in this repo, e.g.
`docker-arcane` vs `podman-arcane`, during implementation) and
`http://localhost:6246`.

### 6. `template/server-services.nix`

Update the doc comment listing `arr (SABnzbd + Sonarr + Radarr + Lidarr +
Prowlarr)` to mention Maintainerr, and update the commented example line
(currently line 60) to show the new sub-options, e.g.:

```
# ── Media Automation (Arr Stack) ─────────────────────────────────────────
# vexos.server.arr.enable = false;                    # Full stack: SABnzbd:8080 Sonarr:8989 Radarr:7878 Lidarr:8686 Prowlarr:9696
#   Or enable individually via `just enable arr` → individual mode, or set directly:
# vexos.server.arr.sabnzbd.enable = false;             # Port 8080
# vexos.server.arr.sonarr.enable = false;              # Port 8989
# vexos.server.arr.radarr.enable = false;              # Port 7878
# vexos.server.arr.lidarr.enable = false;              # Port 8686
# vexos.server.arr.prowlarr.enable = false;            # Port 9696
# vexos.server.arr.qbittorrent.enable = false;         # Port 8081 — torrent client
# vexos.server.arr.bazarr.enable = false;               # Port 6767 — subtitle manager
# vexos.server.arr.maintainerr.enable = false;          # Port 6246 — automated library cleanup
```

## Dependencies

No new flake inputs. Maintainerr is consumed as a pinned OCI image
(`ghcr.io/maintainerr/maintainerr:3.17.1`), same mechanism as `arcane` and
`stirling-pdf` — no Context7/nixpkgs library lookup applies (not a packaged
language dependency).

## Configuration Changes

- `modules/server/arr.nix` — restructured per-component options (breaking
  change for anyone with `vexos.server.arr.enable = true;` already set: no
  behavior change, since `cfg.enable` still defaults all 5 core services on).
- `justfile` — `enable`, `disable`, `service-info` recipes gain arr-specific
  logic; a small `_set_flag` bash helper is introduced for the new code path.
- `template/server-services.nix` — doc comments updated.

## Risks and Mitigations

- **Risk:** Existing hosts with `vexos.server.arr.enable = true;` in their
  `/etc/nixos/server-services.nix` must keep working unchanged.
  **Mitigation:** `cfg.enable` still `mkDefault`s all 5 core sub-options to
  true, so existing configs evaluate identically.
- **Risk:** Users invoking `just enable arr` non-interactively (e.g. scripted)
  will now hit a `read -r -p` prompt where none existed for other services
  in bulk-scripted contexts — but this already matches existing behavior for
  `plex`/`proxmox`/`backup`, which are also interactive-only recipes.
- **Risk:** OCI container unit naming for `status arr` must be verified
  against this repo's actual oci-containers systemd unit naming convention
  before hardcoding `podman-maintainerr` / `docker-maintainerr`.
  **Mitigation:** confirm via `systemctl status` unit name pattern used by
  `arcane`/`stirling-pdf` service definitions (`virtualisation.oci-containers.containers.<name>` → typically `docker-<name>.service` or `podman-<name>.service` depending on backend) during implementation, before adding to the `status` case.
- **Risk:** Docker image version `3.17.1` will drift from upstream over
  time. **Mitigation:** matches existing pinning convention (e.g. `arcane`
  pins `v1.19.4`) — acceptable, bump manually like other pinned images.

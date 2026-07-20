# docker_nftables — Spec

## Current State Analysis

- `modules/server/docker.nix` enables Docker via `virtualisation.docker.enable = true`
  and pins `virtualisation.docker.package = pkgs.docker_29` (line 15).
- `environment.systemPackages` in that module only includes `docker-compose` and
  `lazydocker` (lines 28-31) — `nftables` is not installed anywhere in the repo
  (confirmed via repo-wide grep; only unrelated matches in doc/spec files and an
  unrelated systemd unit name in `vexboard.nix`).
- `networking.nftables.enable` is not set anywhere in the repo, so it defaults to
  `false` — this system uses the legacy iptables-based `networking.firewall`
  (set in `modules/network.nix:150`). This is intentional and must not change:
  the NixOS `networking.nftables` module documents a conflict with Docker, which
  manages its own iptables rules internally.

## Problem Definition

Docker Engine 28+ (this repo pins `docker_29`) defaults to an nftables-based
firewall backend for managing container network rules. On boot, dockerd logs:

```
level=warning msg="Failed to find nft tool" error="exec: \"nft\": executable file not found in $PATH"
level=info msg="Deleting nftables IPv4 rules" error="failed to find nft tool..."
level=info msg="Deleting nftables IPv6 rules" error="failed to find nft tool..."
```

Because the `nft` binary is not on dockerd's `PATH`, dockerd cannot properly
manage firewall/network rules for user-defined bridge networks. Observed effect
on `vexos-server-intel` (host `vexos-vmc`): a custom docker network
(`joplin-net`, created by the `joplin-network.service` oneshot via
`docker network create`) appears to exist, but shortly afterward a dependent
container (`docker-joplin-db.service`) fails to start with:

```
docker: Error response from daemon: failed to set up container networking: network joplin-net not found
```

This causes `docker-joplin-db.service` to fail its restart-limit and
`docker-joplin-server.service` to fail via dependency (`dependsOn`), taking
down the whole Joplin stack after a reboot. The same custom-network pattern is
used by `modules/server/grimmory.nix` (`grimmory-net`), so it is at risk of
the identical failure.

## Proposed Solution

Add `pkgs.nftables` to `environment.systemPackages` in `modules/server/docker.nix`,
scoped inside the existing `lib.mkIf cfg.enable` block (alongside
`docker-compose` and `lazydocker`). This puts the `nft` binary on `PATH` so
dockerd can find and use it, without touching `networking.nftables.enable`
(which stays `false`, avoiding the documented conflict between that option and
Docker's own iptables management).

This is a minimal, additive change: one package added to one existing list, in
the module that already owns Docker's runtime configuration. No new options,
no new modules, no role-specific `lib.mkIf` guards — `docker.nix` already gates
everything behind its own `cfg.enable` option per the Module Architecture
Pattern carve-out (a module gating by an option it declares itself).

## Implementation Steps

1. Edit `modules/server/docker.nix`: add `nftables` to the `environment.systemPackages`
   list inside `lib.mkIf cfg.enable { ... }` (lines 28-31).

## Dependencies

- `pkgs.nftables` — confirmed present in nixpkgs unstable via NixOS MCP
  (`nftables` v1.1.6, GPL-2.0, https://netfilter.org/projects/nftables/).
  No new flake input required; it's a standard nixpkgs package.

## Configuration Changes

None beyond the one-line package addition. `system.stateVersion` untouched.
`networking.nftables.enable` remains unset (`false`).

## Risks and Mitigations

- **Risk:** Installing the `nftables` package alone (without
  `networking.nftables.enable`) could theoretically interact with the
  system's active iptables-based firewall.
  **Mitigation:** Installing the package only puts the `nft` CLI binary on
  PATH — it does not enable the `nftables.service` or NixOS's declarative
  nftables ruleset management (that only happens via
  `networking.nftables.enable`, which is deliberately left untouched here).
  Docker itself decides at runtime whether to use `nft` or fall back to
  `iptables`; providing the binary just removes the "not found" failure mode.
- **Risk:** Fix only addresses `docker.nix`, but `grimmory.nix` uses an
  identical custom-network pattern (`grimmory-net`) and could hit the same
  failure.
  **Mitigation:** Not in scope — the fix lives in the shared `docker.nix`
  module, so once `nft` is on PATH, dockerd's networking behavior improves for
  *all* Docker-based services (Joplin, Grimmory, etc.) system-wide. No
  per-service changes needed.

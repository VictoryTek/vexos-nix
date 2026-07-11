# Review: Maintainerr + Individually-Selectable Arr Services

## Spec Compliance

Implementation matches `.github/docs/subagent_docs/arr_maintainerr_individual_spec.md`:

1. `modules/server/arr.nix` — every core service (`sabnzbd`, `sonarr`, `radarr`,
   `lidarr`, `prowlarr`) now has its own `enable` option; `vexos.server.arr.enable`
   is a meta-flag that `lib.mkDefault`s all five to true. `qbittorrent`/`bazarr`
   kept their existing independent flags (assertions requiring `cfg.enable`
   removed, since they're no longer needed). `maintainerr.enable` +
   `maintainerr.port` added, implemented as a pinned OCI container
   (`ghcr.io/maintainerr/maintainerr:3.17.1`) matching the `arcane.nix` /
   `stirling-pdf.nix` convention — no NixOS module exists for Maintainerr in
   nixpkgs stable or unstable (confirmed via `nix eval`).
2. `justfile` `enable arr` now prompts full-stack vs. individual selection;
   individual mode accepts space/comma-separated component names, validates
   each, and writes `vexos.server.arr.<component>.enable = true;` directly.
   VexBoard auto-enable preserved for both paths.
3. `justfile` `disable arr` sweeps both the top-level flag and all 8
   per-component flags, so it correctly undoes either enable mode.
4. `justfile` `service-info` (`_info arr`, and the no-arg enabled-service
   detection loop) and the `services` catalog's `_check arr` now correctly
   detect and report individually-enabled arr components, not just the
   top-level flag.
5. `justfile` `status arr` extended with Maintainerr's unit
   (`docker-maintainerr`, matching this repo's `virtualisation.oci-containers.backend
   = "docker"` convention) and URL (`:6246`).
6. `template/server-services.nix` doc comments updated with all 8 sub-options.

## Best Practices / Consistency (Module Architecture Pattern)

- The per-component `lib.mkIf cfg.<x>.enable { ... }` blocks are the documented
  carve-out ("option gated by an option the same module declares") — not
  role-smuggling. No new role/display/gaming-flag `lib.mkIf` guards introduced.
- Maintainerr's OCI-container block follows the exact structural pattern of
  `arcane.nix`/`stirling-pdf.nix` (backend defaulting, pinned image tag,
  named volume, `networking.firewall.allowedTCPPorts`).
- `TZ = config.time.timeZone` matches the existing convention in
  `modules/server/authelia.nix`.

## Completeness

All 6 spec items implemented. `justfile` changes cover enable, disable,
service-info (both `_info` case and detection loop), the `services` catalog
check, and `status`, which is a superset of what the user explicitly asked
for (enable individually) but necessary — without it, `disable arr` and
`service-info` would silently misreport state after an individual-mode
enable, since the file only originally recognized the single top-level flag.

## Security

- No hardcoded secrets. No plaintext credentials introduced.
- Maintainerr's port is user-configurable (`vexos.server.arr.maintainerr.port`)
  and firewall-opened only for that port, matching sibling modules.
- No world-writable files or permission changes.

## Build Validation

- `nix flake show --impure`: passed, all 30 `nixosConfigurations` + modules listed.
- `nix eval --impure` (CI-equivalent to `nixos-rebuild dry-build`, since `sudo`
  is unavailable in this sandboxed session) for:
  - `vexos-desktop-amd` — passed
  - `vexos-desktop-nvidia` — passed
  - `vexos-desktop-vm` — passed
  - `vexos-server-amd` — passed (with CI's `networking.hostId = "cafebabe"`
    stub override, matching `.github/workflows/ci.yml`'s handling of the
    intentional shared-placeholder ZFS assertion — confirmed pre-existing
    and unrelated to this change)
  - `vexos-headless-server-amd` — passed (same stub)
- `git ls-files hardware-configuration.nix` — empty, not tracked.
- `system.stateVersion` — no changes in any `configuration-*.nix`.
- `flake.nix` — untouched, no new inputs.
- `just --list` — justfile syntax parses cleanly after edits.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Notes

- Minor: the `_set_flag` bash helper introduced in the `enable` recipe is
  only used by the new `arr` code path, not retrofitted onto the
  pre-existing `plex`/`proxmox`/`backup` special cases, per the spec's
  explicit intent to keep the diff minimal/surgical.
- Pre-existing dead/unrelated items noticed but not touched: none beyond the
  known CI-stubbed `networking.hostId` placeholder.

## Result: PASS

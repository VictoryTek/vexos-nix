# PIA Nixified Implementation Plan

## Objective
Replace installer-driven mutable PIA runtime behavior with a declarative Nix-managed package path that still uses official PIA Linux binaries.

Target result:
- PIA works across required roles.
- PIA artifacts are deterministic and version-pinned.
- Universal update path remains clean and predictable.

## High-Level Approach
Use a binary-repack package model:
1. Fetch official PIA Linux installer artifact with pinned hash.
2. Extract payload during derivation build.
3. Install payload into Nix store structure.
4. Provide wrappers/services from Nix paths.
5. Remove host-level dependence on mutable `/opt/piavpn`.

This avoids full upstream source-compilation complexity while remaining declarative.

## Exact Implementation Steps

### Phase 1: Create PIA Package Derivation
Files to add/edit:
- Add `pkgs/pia-client-bin/default.nix`
- Edit `pkgs/default.nix`

`pkgs/pia-client-bin/default.nix` requirements:
1. Inputs:
   - `stdenvNoCC`
   - `fetchurl`
   - `makeWrapper`
   - `bash`
2. Package metadata:
   - `pname = "pia-client-bin"`
   - explicit `version`
3. Source fetch:
   - use direct official `.run` URL pinned with fixed hash.
4. Build/install behavior:
   - run installer in noexec mode to extract payload.
   - copy runtime payload to `$out/share/pia-client`.
   - create wrapper binaries in `$out/bin`:
     - `pia-client`
     - `piactl`
     - `pia-daemon`
   - wrappers set `NIX_LD_LIBRARY_PATH` and `LD_LIBRARY_PATH` correctly.
5. Include desktop entry in package output when relevant.
6. Mark package as unfree with clear license metadata.

`pkgs/default.nix` changes:
1. Export attribute `pia-client-bin = callPackage ./pia-client-bin { };`
2. Keep existing package exports unchanged.

### Phase 2: Refactor Modules to Use Store Paths
Files to edit:
- `modules/pia.nix`
- `modules/pia-server.nix`
- optionally add `modules/pia-runtime.nix` if splitting common base

Required changes:
1. Replace hardcoded `/opt/piavpn/...` references with `${pkgs.pia-client-bin}/...` paths.
2. Keep role behavior:
   - desktop roles keep GUI + desktop integration.
   - server/headless roles keep CLI-only usage.
3. Service updates:
   - `ExecStart` points to packaged daemon path.
4. Keep kernel modules and routing table setup where currently defined.
5. Keep nix-ld requirements, but reduce to what is actually needed after package test.

Architecture rule alignment:
- Keep shared content in a base module.
- Keep role-specific additions in role modules.
- No new `lib.mkIf` gates inside shared module content.

### Phase 3: Replace Installer-Centric Workflow
Files to edit:
- `justfile`
- `README.md`

Changes:
1. Deprecate installer-heavy steps for normal path.
2. Keep `just pia` as control/status UI, but remove dependency on running installer first.
3. Add version bump procedure:
   - update package version/url/hash
   - rebuild and validate
4. Document recovery commands and service checks.

### Phase 4: Integrate with Universal Updater Policy
Files to edit:
- `modules/nix.nix`

Changes:
1. Ensure miss-class policy treats small PIA packaging derivations as known-small local only if needed.
2. Keep unknown derivations blocking.
3. Emit explicit status messages for PIA-related local derivations.

### Phase 5: Migration Strategy

#### Step A: Parallel Compatibility Window
1. Keep legacy runtime checks for `/opt/piavpn` only during migration.
2. Prefer packaged path first.
3. Log warning if legacy path is detected.

#### Step B: Cutover
1. Remove legacy `/opt/piavpn` fallbacks after validation window.
2. Remove runtime fallback unit generation paths not needed anymore.

#### Step C: Cleanup
1. Remove obsolete comments/instructions that assume interactive installer.
2. Ensure docs match declarative package model.

## Validation Plan

### Functional checks
1. `piactl --version`
2. `systemctl start piavpn`
3. `systemctl is-active piavpn`
4. connect/disconnect basic flow via existing `just pia` actions

### Build checks
1. `nix flake show`
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
3. `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`
4. `bash scripts/preflight.sh`

### Update-path checks
1. Run `just update` with expected-only small local PIA derivations.
2. Verify no permanent hold loop from PIA helper artifacts.
3. Verify unknown derivation still blocks and restores lock.

## Rollback Strategy

### Package rollback
1. Keep previous known-good `pia-client-bin` version and hash in git history.
2. Revert package commit if runtime regression appears.
3. Rebuild affected hosts.

### Runtime rollback
1. `sudo nixos-rebuild switch --rollback`
2. confirm generation state and daemon status.

### Emergency fallback
If packaged PIA fails unexpectedly:
1. Temporarily disable PIA module import on impacted hosts.
2. Restore prior generation.
3. Re-enable once package fix is validated.

## Risks and Mitigations
1. Upstream installer format changes.
- Mitigation: resilient extraction logic with explicit failure messages.
2. Runtime library mismatch.
- Mitigation: keep nix-ld library set explicit and test on desktop + server roles.
3. Unfree policy friction.
- Mitigation: clearly document unfree enablement expectations.

## Definition of Done
- [ ] `pia-client-bin` package exists and builds reproducibly.
- [ ] PIA modules use Nix store paths instead of mutable `/opt/piavpn`.
- [ ] `just pia` remains functional for operational commands.
- [ ] `just update` remains universal and predictable.
- [ ] Required dry-build/preflight checks pass.

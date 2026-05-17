# papermc_eula_spec

## Metadata
- Date: 2026-05-16
- Finding: [BUG] services.minecraft-server with eula=true accepts the EULA on operator's behalf.
- Primary local file: modules/server/papermc.nix
- Scope: Phase 1 research and specification only (no implementation in this document)

## Implementation Status (updated 2026-05-16)

**modules/server/papermc.nix has already been updated to match this spec.**

Verified state of the file:
- `vexos.server.papermc.acceptEula` option is present (`lib.mkOption`, `type = lib.types.bool`, `default = false`).
- `assertions` block is present with the exact message specified in this spec.
- `services.minecraft-server.eula = cfg.acceptEula` (not hardcoded `true`).

The review phase must confirm the live file matches the exact before/after snippets in §7 below
and that `nix flake check --impure` and `nixos-rebuild dry-build` for at least one server
variant pass without errors.

## Current State Analysis

### Local wiring and behavior
1. modules/server/papermc.nix currently defines two options under vexos.server.papermc:
- enable (mkEnableOption)
- memory (string, default "2G")

2. When vexos.server.papermc.enable = true, modules/server/papermc.nix unconditionally sets:
- services.minecraft-server.enable = true
- services.minecraft-server.eula = true
- services.minecraft-server.package = pkgs.unstable.papermc
- services.minecraft-server.openFirewall = true
- services.minecraft-server.declarative = false
- services.minecraft-server.jvmOpts from vexos.server.papermc.memory

3. modules/server/default.nix imports ./papermc.nix under the game-servers section, making the module available to all roles that import ./modules/server.

4. Both configuration-server.nix and configuration-headless-server.nix import ./modules/server, so both server roles can enable vexos.server.papermc.

5. flake.nix wires optional /etc/nixos/server-services.nix as serverServicesModule for server and headless-server roles. This is where per-host toggles are usually applied.

6. template/server-services.nix currently exposes commented examples for:
- vexos.server.papermc.enable = false;
- vexos.server.papermc.memory = "2G";

There is currently no explicit vexos.server.papermc option for legal acceptance of the Minecraft EULA.

### Why this matters
The current module behavior accepts the upstream Minecraft EULA on behalf of the operator whenever papermc is enabled, because eula is hardcoded to true.

## Problem Definition

The unresolved finding is valid:
- The module currently makes legal acceptance implicit by setting services.minecraft-server.eula = true inside the service enable path.
- The operator is not required to make an explicit, deliberate acceptance decision in local config.

This creates a policy and compliance concern:
- Enabling a service should not silently imply legal agreement acceptance.
- Acceptance should be explicit in host-owned configuration and auditable.

## Research Sources (Credible, >= 6)

1. NixOS minecraft-server module source (nixos-25.11)
- URL: https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/games/minecraft-server.nix
- Used for:
  - services.minecraft-server.eula option default false
  - assertion requiring eula=true when service is enabled
  - module message text pointing users to Mojang EULA

2. Nixpkgs lib option helpers source (nixos-25.11)
- URL: https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/lib/options.nix
- Used for:
  - mkEnableOption behavior (bool default false)
  - mkOption conventions for explicit boolean options

3. NixOS Manual - Writing NixOS Modules
- URL: https://nixos.org/manual/nixos/stable/#sec-writing-modules
- Used for module architecture and option declaration conventions.

4. NixOS Manual - Warnings and Assertions
- URL: https://nixos.org/manual/nixos/stable/#sec-assertions
- Used for best-practice guidance on enforcing invalid configurations with assertions.

5. NixOS option search entry for services.minecraft-server.eula (25.11)
- URL: https://search.nixos.org/options?channel=25.11&show=services.minecraft-server.eula&from=0&size=50&sort=relevance&type=packages&query=minecraft-server.eula
- Used to verify official option presence and discoverability in current channel docs.

6. Official Minecraft EULA
- URL: https://www.minecraft.net/en-us/eula
- Used as the legal source that acceptance must refer to.

7. Official Minecraft Java server download page
- URL: https://www.minecraft.net/en-us/download/server
- Used for explicit distribution-language context that downloading server software implies agreement to EULA.

## Proposed Solution (Minimal Safe Fix)

### Design goals
- Make EULA acceptance explicit and opt-in.
- Keep blast radius minimal.
- Follow current vexos server module style (option declarations + assertion in module config).

### Proposed behavior
1. Add vexos.server.papermc.acceptEula as an explicit boolean option.
- Type: bool
- Default: false
- Purpose: operator must set to true only after reviewing Mojang EULA.

2. Add an assertion in modules/server/papermc.nix when cfg.enable is true.
- Requirement: cfg.acceptEula must be true.
- Failure message should clearly point to the option and EULA URL.

3. Wire services.minecraft-server.eula to cfg.acceptEula.
- Replace hardcoded eula = true with eula = cfg.acceptEula.

4. Update template/server-services.nix to surface the new option.
- Add commented toggle for vexos.server.papermc.acceptEula = false; with a short note that it must be set to true to run PaperMC.

### Why this is minimal and aligned
- No structural changes to role imports or flake wiring.
- Only service-specific module and its operator template are touched.
- Matches existing assertion style already used in server modules (for example proxmox and cockpit sub-options).

## Exact File Edits

### 1) modules/server/papermc.nix
Planned edits:
- Add new option under options.vexos.server.papermc:
  - acceptEula = lib.mkOption { type = lib.types.bool; default = false; ... }
- In config = lib.mkIf cfg.enable { ... } add:
  - assertions = [ { assertion = cfg.acceptEula; message = ...; } ];
- Replace:
  - services.minecraft-server.eula = true;
  with:
  - services.minecraft-server.eula = cfg.acceptEula;

Implementation note for message style:
- Keep message explicit and actionable, for example:
  - "vexos.server.papermc.acceptEula must be set to true when vexos.server.papermc.enable = true. Read https://www.minecraft.net/en-us/eula before enabling."

### 2) template/server-services.nix
Planned edits:
- In the Game Servers section, add:
  - # vexos.server.papermc.acceptEula = false;  # Set to true only after reading Mojang EULA

No changes required in:
- modules/server/default.nix
- flake.nix
- configuration-server.nix
- configuration-headless-server.nix

## Risks and Mitigations

1. Risk: Existing hosts with papermc enabled but without the new option will fail evaluation/build after implementation.
- Mitigation: This is intentional and safe-by-default. The assertion message will direct the operator to set vexos.server.papermc.acceptEula = true explicitly.

2. Risk: Operators might miss the new option in local service toggles.
- Mitigation: Update template/server-services.nix so the option appears alongside enable and memory.

3. Risk: Legal URL or wording changes upstream.
- Mitigation: Keep a stable canonical URL in assertion and option description (minecraft.net/eula), and revisit only if URL changes.

## Validation Plan

### Static and evaluation checks
1. Parse-level check for module syntax:
- nix-instantiate --parse modules/server/papermc.nix >/dev/null

2. Flake-level evaluation:
- nix flake check --impure

### Functional policy checks (assertion semantics)
3. Negative path (should fail):
- Evaluate/build with:
  - vexos.server.papermc.enable = true
  - vexos.server.papermc.acceptEula = false
- Expected: assertion failure with clear message.

4. Positive path (should pass):
- Evaluate/build with:
  - vexos.server.papermc.enable = true
  - vexos.server.papermc.acceptEula = true
- Expected: services.minecraft-server.eula evaluates to true via cfg.acceptEula.

### Role-level dry-build checks
5. Validate at least one variant for each server role:
- sudo nixos-rebuild dry-build --flake .#vexos-server-amd
- sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd

### Project preflight
6. Run project preflight:
- bash scripts/preflight.sh

## Expected Modified Files (Implementation Phase)
- modules/server/papermc.nix
- template/server-services.nix

(Phase 1 output file created now: .github/docs/subagent_docs/papermc_eula_spec.md)

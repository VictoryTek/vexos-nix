# Cockpit Sub-Plugin Defaults Refactor Spec

Project: vexos-nix
Phase: 1 (Research and Specification)
Status: Specification ready for implementation
Date: 2026-05-16
Target finding: [BUG] Cockpit sub-plugins use default = cfg.enable and merge-order is hard to reason about.

---

## 1) Current State Analysis

### 1.1 Target module

File: modules/server/cockpit.nix

Current option declarations:
- vexos.server.cockpit.enable: mkEnableOption, default false semantics.
- vexos.server.cockpit.navigator.enable: bool option, default = cfg.enable.
- vexos.server.cockpit.fileSharing.enable: bool option, default = cfg.enable.
- vexos.server.cockpit.identities.enable: bool option, default = cfg.enable.

Current config behavior:
- Cockpit service enabled by mkIf cfg.enable.
- Navigator package installed by mkIf (cfg.enable && cfg.navigator.enable).
- File-sharing package and Samba/NFS config enabled by mkIf cfg.fileSharing.enable, with assertion that fileSharing => cfg.enable.
- Identities package installed by mkIf (cfg.enable && cfg.identities.enable).

Observation:
- navigator/identities are gated by parent + child.
- fileSharing body is gated only by child, then asserted against parent.

### 1.2 Related override module

File: modules/server/nas.nix

Current behavior:
- vexos.server.nas.enable controls an umbrella override block.
- When nas.enable = true, module sets mkDefault true for:
  - vexos.server.cockpit.enable
  - vexos.server.cockpit.navigator.enable
  - vexos.server.cockpit.fileSharing.enable
  - vexos.server.cockpit.identities.enable

Priority implication:
- mkDefault is mkOverride 1000 (lower number wins).
- Option-level default values are mkOptionDefault (priority 1500).
- User assignments (plain values) are priority 100 by default.

### 1.3 Template/operator surface

File: template/server-services.nix

Current comments expose:
- One-shot toggle: vexos.server.nas.enable = true.
- Individual toggles for cockpit and each sub-plugin.

Operator impact:
- Users can set combinations that are syntactically valid but behaviorally surprising (especially when parent and child are set in opposite directions).

### 1.4 Import chain / merge context

File: modules/server/default.nix

Relevant import order in server module umbrella:
- ./cockpit.nix
- ./nas.nix

Important nuance:
- Option merge semantics are fixed-point and priority-driven, not simple "last assignment wins".
- Import order still contributes to mental complexity, but priority (100 vs 1000 vs 1500) is the decisive factor for these bool values.

---

## 2) Verified Current Behavior Matrix

Matrix validated via nix eval against vexos-server-amd using extendModules.

Legend:
- Values = resolved option values.
- Effects = resulting service/package effects.
- buildOk = tryEval of config.system.build.toplevel.drvPath success.

| Scenario | cockpit | navigator | fileSharing | identities | cockpitService | navigatorPkg | fileSharingPkg | identitiesPkg | buildOk | Notes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| defaults | false | false | false | false | false | false | false | false | true | Baseline |
| parentTrue | true | true | true | true | true | true | true | true | true | Child defaults follow parent |
| parentTrueNavFalse | true | false | true | true | true | false | true | true | true | Child override works |
| parentTrueFsFalse | true | true | false | true | true | true | false | true | true | Child override works |
| parentTrueIdFalse | true | true | true | false | true | true | true | false | true | Child override works |
| parentFalseNavTrue | false | true | false | false | false | false | false | false | true | "Staged" true has no runtime effect |
| parentFalseIdTrue | false | false | false | true | false | false | false | false | true | "Staged" true has no runtime effect |
| parentFalseFsTrue | false | false | true | false | false | false | true | false | false | Assertion fails (fileSharing => cockpit) |
| nasTrue | true | true | true | true | true | true | true | true | true | Umbrella on |
| nasTrueNavFalse | true | false | true | true | true | false | true | true | true | Explicit nav override beats mkDefault |
| nasTrueParentFalse | false | true | true | true | false | false | true | false | false | Parent forced off, fileSharing still true -> assertion failure |

Key takeaway:
- The dynamic option defaults (default = cfg.enable) produce correct "happy path" behavior but obscure where values are coming from and how they interact with mkDefault overrides from nas.nix.
- Contradictory states are possible and require deep knowledge of merge priorities + assertions to reason about.

---

## 3) Problem Definition

The unresolved finding is valid:
- Sub-plugin defaults are currently encoded as option defaults derived from another option (cfg.enable).
- That pattern works but is hard to reason about in a multi-module setup with mkDefault and user overrides.
- The real policy intended is:
  - Base state: all sub-plugins default false.
  - If parent cockpit is enabled, sub-plugins should default to true unless overridden.

Current implementation expresses that policy indirectly via dynamic option defaults, which increases cognitive load and review friction.

---

## 4) Research Sources (>= 6 credible references)

1. NixOS manual, option definitions:
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/doc/manual/development/option-def.section.md
   - Confirms mkIf usage, override priorities, mkDefault/mkForce equivalence, mkMerge semantics.

2. NixOS manual, writing modules:
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/doc/manual/development/writing-modules.chapter.md
   - Confirms module structure and composition patterns.

3. nixpkgs module system source of truth:
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/lib/modules.nix
   - Confirms exact priority constants:
     - mkOptionDefault = mkOverride 1500
     - mkDefault = mkOverride 1000
     - defaultOverridePriority = 100
     - mkForce = mkOverride 50
   - Confirms mkIf and mkMerge internals.

4. NixOS Cockpit module implementation:
   - https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/monitoring/cockpit.nix
   - Confirms environment.pathsToLink = [ "/share/cockpit" ] and package-driven plugin discovery.

5. Cockpit official package documentation:
   - https://cockpit-project.org/guide/latest/packages.html
   - Confirms package discovery from XDG data dirs and required manifest.json under share/cockpit/<package>.

6. 45Drives cockpit-file-sharing README:
   - https://raw.githubusercontent.com/45Drives/cockpit-file-sharing/main/README.md
   - Confirms plugin role and Samba/NFS integration expectations.

7. 45Drives cockpit-navigator README:
   - https://raw.githubusercontent.com/45Drives/cockpit-navigator/main/README.md
   - Confirms plugin role as Cockpit-integrated file browser.

8. 45Drives cockpit-identities README:
   - https://raw.githubusercontent.com/45Drives/cockpit-identities/main/README.md
   - Confirms plugin role for Cockpit user/group management.

Research conclusion:
- The requested refactor pattern (base false defaults + conditional mkDefault true via mkIf parent) is fully aligned with Nix module best practice and preserves intended behavior while making merge provenance clearer.

---

## 5) Minimal Fix Design

### 5.1 Desired semantics

- Sub-options should declare static defaults:
  - navigator.enable default false
  - fileSharing.enable default false
  - identities.enable default false

- Parent-on defaults should be expressed in config definitions:
  - Under mkIf cfg.enable, set mkDefault true for each sub-option.

This yields:
- Clear base defaults at option declaration level.
- Clear conditional policy at config level.
- Predictable override behavior:
  - user value (100) beats mkDefault (1000)
  - mkDefault (1000) beats option default (1500)

### 5.2 Proposed structural change in modules/server/cockpit.nix

Inside config = lib.mkMerge [ ... ], add a new early block:

- mkIf cfg.enable {
  - vexos.server.cockpit.navigator.enable = lib.mkDefault true;
  - vexos.server.cockpit.fileSharing.enable = lib.mkDefault true;
  - vexos.server.cockpit.identities.enable = lib.mkDefault true;
}

Then keep existing service and package install mkIf blocks intact.

### 5.3 Why this resolves the finding

- Removes dynamic option-default dependency on cfg.enable from option declarations.
- Moves default-on policy into explicit conditional config definitions.
- Makes precedence and merge origin auditable in one place.
- Retains existing behavior for common valid scenarios.

---

## 6) Implementation Steps (Phase 2)

1. Edit modules/server/cockpit.nix:
   - Change three sub-option default values from cfg.enable to false.
   - Add conditional mkDefault true block under config.mkMerge gated by cfg.enable.

2. Keep existing assertions and service/package blocks unchanged unless needed for formatting consistency.

3. Validate behavior:
   - nix flake check --impure
   - bash scripts/preflight.sh
   - Optional targeted eval matrix check (same expression used in this spec) to confirm expected outcomes.

---

## 7) Risks and Mitigations

Risk 1: Subtle behavior drift for edge-case combinations.
- Mitigation: Re-run matrix checks for parent/child contradictory combinations.

Risk 2: Reviewer confusion if docs/comments still imply old default mechanics.
- Mitigation: Update descriptions in the three sub-option descriptions to state default false plus parent-enabled mkDefault behavior.

Risk 3: NAS override interactions remain non-intuitive when parent is explicitly forced false while nas.enable true.
- Mitigation: Keep this out of scope for minimal bug fix; document as known behavior from nas umbrella design + fileSharing assertion.

---

## 8) Expected Modified Files for Implementation

Mandatory:
- modules/server/cockpit.nix

Likely unchanged (analysis-only context):
- modules/server/nas.nix
- template/server-services.nix

If implementation updates inline docs for clarity, still only modules/server/cockpit.nix should need changes.

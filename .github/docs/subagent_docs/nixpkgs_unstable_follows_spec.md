# Specification: nixpkgs-unstable follows decision

Feature name: `nixpkgs_unstable_follows`
Spec path: `.github/docs/subagent_docs/nixpkgs_unstable_follows_spec.md`
Date: 2026-05-18

---

## 1) Current state analysis

### 1.1 Exact flake input lines and comments

From `flake.nix`:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  # nixpkgs-unstable: used to supply latest GNOME application packages in
  # modules/gnome.nix via the pkgs.unstable overlay.
  # Do NOT add inputs.nixpkgs-unstable.follows = "nixpkgs" - that would
  # pin unstable to the stable revision, defeating its purpose.
  nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  home-manager = {
    url = "github:nix-community/home-manager/release-25.11";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  up = {
    url = "github:VictoryTek/Up";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # proxmox-nixos: Proxmox VE hypervisor on NixOS. Used by modules/server/proxmox.nix.
  # Do NOT add inputs.proxmox-nixos.inputs.nixpkgs.follows = "nixpkgs" - the upstream
  # flake manages its own nixpkgs-stable pin; overriding it breaks package builds.
  proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
};
```

From `flake.nix` (overlay wiring):

```nix
unstableOverlayModule = {
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import nixpkgs-unstable {
        inherit (final) config;
        inherit (final.stdenv.hostPlatform) system;
      };
    })
  ];
};
```

From `.github/docs/subagent_docs/full_code_analysis.md`:

- Line 64 marks this as:
  - `[BUG] nixpkgs-unstable input lacks inputs.nixpkgs.follows = "nixpkgs" - N/A (intentional; documented known cost)`
- Line 66 explicitly states this is currently a known tradeoff and recommends no code change unless cost becomes material.

From `scripts/preflight.sh`:

- `CHECK 5` validates lockfile presence, pinning, and freshness.
- There is no preflight gate for counting duplicate nixpkgs graph nodes or enforcing blanket follows on all inputs.

### 1.2 Lock graph snapshot relevant to this decision

From `flake.lock`:

- `root.inputs.nixpkgs = "nixpkgs_2"` (nixos-25.11)
- `root.inputs.nixpkgs-unstable = "nixpkgs-unstable"` (nixos-unstable)
- `root.inputs.proxmox-nixos = "proxmox-nixos"` where upstream keeps `nixpkgs-stable`

Important detail:

- The `nixpkgs-unstable` node itself has no nested `inputs.nixpkgs` edge in this lockfile.
- Practically, a nested override style `inputs.nixpkgs-unstable.inputs.nixpkgs.follows = "nixpkgs"` has no direct target to deduplicate here.
- The only direct dedup action for this input is to alias the whole input (`nixpkgs-unstable.follows = "nixpkgs"`), which removes unstable separation by design.

### 1.3 Actual unstable usage in this repo

`pkgs.unstable` is not cosmetic. It is currently used in multiple places, including:

- `home-desktop.nix` (`pkgs.unstable.vscode-fhs`)
- `modules/gnome.nix` (GNOME stack and extensions)
- `modules/server/papermc.nix` (`pkgs.unstable.papermc`)
- `modules/server/seerr.nix` (`pkgs.unstable.seerr`)

This means collapsing unstable to stable changes behavior and potentially package availability, not just graph shape.

---

## 2) Research sources (minimum 6)

1. Nix Reference Manual (`nix flake`, Flake inputs and follows semantics)
   - https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake.html
   - Key point: `follows` is a path-based input inheritance mechanism.

2. Nix flake spec source (`src/nix/flake.md`)
   - https://github.com/NixOS/nix/blob/master/src/nix/flake.md
   - Key point: docs explicitly note that eliminating transitive nixpkgs inputs via follows is often not useful because module/overlay composition happens at top-level nixpkgs.

3. NixOS Wiki Flakes page
   - https://wiki.nixos.org/wiki/Flakes
   - Key point: demonstrates follows as a dedup tool and frames it as optional, context-dependent.

4. NixOS Discourse thread: "Recommendations for use of flakes' input-follows"
   - https://discourse.nixos.org/t/recommendations-for-use-of-flakes-input-follows/17413
   - Key point: follows is commonly used for dedup, with `nix flake metadata` graph inspection to decide where it helps.

5. NixOS Discourse thread: "Flake: how make nixpkgs' self follow another input's nixpkgs?"
   - https://discourse.nixos.org/t/flake-how-make-nixpkgs-self-follow-another-inputs-nixpkgs/10867
   - Key point: shows practical follows aliasing patterns and that follows changes graph wiring, not just lockfile cosmetics.

6. Home Manager README (release alignment and compatibility constraints)
   - https://raw.githubusercontent.com/nix-community/home-manager/release-25.11/README.md
   - Key point: Home Manager release branches are aligned to NixOS release compatibility; forcing mismatched branches can break configs.

7. Home Manager docs search hits (`docs/manual/usage/upgrading.md`, `docs/manual/faq/unstable.md`)
   - https://github.com/nix-community/home-manager
   - Key point: release-branch alignment and unstable/stable mixing are documented and branch-aware.

8. Proxmox-NixOS README and flake
   - https://raw.githubusercontent.com/SaumonNet/proxmox-nixos/main/README.md
   - https://github.com/SaumonNet/proxmox-nixos/blob/main/flake.nix
   - Key point: upstream explicitly says do not override `nixpkgs-stable`; this is a concrete example where forced follows can break supported behavior.

9. Up flake definition
   - https://github.com/VictoryTek/Up/blob/main/flake.nix
   - Key point: upstream pins its own nixpkgs branch; local follows policy should respect upstream compatibility expectations.

---

## 3) Problem definition

The decision is a tradeoff between:

- Dedup/eval ergonomics:
  - Fewer nixpkgs nodes can reduce lock graph complexity and may improve `nix flake check`/evaluation behavior.
- Functional compatibility and intent:
  - This repo intentionally uses both stable (`nixos-25.11`) and unstable (`nixos-unstable`) for different roles.
  - Several modules consume `pkgs.unstable` directly for newer application stacks.
  - Some upstream dependencies (notably proxmox-nixos) are branch-sensitive and explicitly advise against forced nixpkgs override.

In short: dedup pressure exists, but forcing follows on branch-sensitive or intentionally split inputs can regress functionality.

---

## 4) Decision options

### Option A: Keep as-is intentional (status quo)

Summary:

- Keep `nixpkgs-unstable.url = ".../nixos-unstable"`.
- Keep current comments that document why follows is intentionally absent.

Pros:

- Preserves explicit stable + unstable split.
- Keeps current behavior for all `pkgs.unstable.*` call sites.
- Aligns with documented upstream compatibility constraints.

Cons:

- Maintains known extra lock graph complexity and evaluation cost.

### Option B: Add follows now

Summary:

- Effective way to force dedup here is aliasing `nixpkgs-unstable` to stable (`nixpkgs-unstable.follows = "nixpkgs"`) and dropping its URL.

Pros:

- Simplifies one direct nixpkgs branch split.
- May marginally reduce evaluation overhead.

Cons:

- Defeats the stated purpose of unstable input.
- Changes package set under all `pkgs.unstable.*` consumers.
- High compatibility risk for modules expecting newer unstable package state.

### Option C: Hybrid/guarded strategy

Summary:

- Keep unstable split now.
- Add monitoring and explicit reevaluation trigger.
- Dedup only where upstream compatibility docs permit.

Pros:

- Preserves behavior while adding operational discipline.
- Avoids broad forced follows that can break branch-sensitive flakes.

Cons:

- Does not immediately reduce graph complexity.
- Requires periodic review or instrumentation.

---

## 5) Recommended path with rationale

Recommendation: **Option A now, with Option C guardrails.**

Decision rationale:

1. The current design intentionally depends on unstable packages in multiple modules, not just one GNOME tweak.
2. Forced follow would collapse the intentional split and risks behavior regressions.
3. Upstream compatibility guidance for proxmox-nixos explicitly warns against overriding its stable pin, demonstrating real-world branch-coupling risk.
4. Nix docs describe follows as a graph tool, not a universal best-practice mandate; blanket dedup can be counterproductive.

Conclusion:

- Keep the current `nixpkgs-unstable` non-followed design.
- Treat the known cost as accepted technical tradeoff.

---

## 6) Implementation steps

### Phase 2 action: explicit no code change

1. Do not edit `flake.nix` for this item.
2. Do not add `nixpkgs-unstable.follows`.
3. Do not add nested `inputs.nixpkgs-unstable.inputs.nixpkgs.follows`.
4. Leave `scripts/preflight.sh` unchanged for this specific decision.
5. Mark this finding as intentional no-op in the implementation summary.

Optional follow-up (separate scoped task, not part of this Phase 2):

- Add an informational preflight warning that reports count of nixpkgs-like lock nodes and trend over time.

---

## 7) Risks and mitigations

Risk: Ongoing duplicate nixpkgs nodes increase eval/lock complexity.

- Mitigation: monitor check latency and lock graph growth; revisit if costs become material.

Risk: Future contributor "optimizes" by forcing follows and silently changes package behavior.

- Mitigation: keep explicit comments in `flake.nix`; keep this spec in subagent docs; require review for any follows policy changes.

Risk: Upstream branch-sensitive inputs break if forced to follow root nixpkgs.

- Mitigation: keep per-input policy based on upstream docs (example: proxmox-nixos stable pin policy).

---

## 8) Validation plan

For this no-op decision:

1. Verify no changes were applied to `flake.nix` for this item.
2. Verify no changes were applied to `scripts/preflight.sh` for this item.
3. Confirm decision is documented in this spec file.

If reevaluated later in a dedicated change set:

1. Run `nix flake metadata` and compare nixpkgs node graph before/after.
2. Run `nix flake check`.
3. Run role coverage dry-builds used by project policy:
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
4. Validate `pkgs.unstable` call sites still resolve to intended package set.

---

## Decision for next phase

Phase 2 should treat this item as: **NO-OP (no code edits for this target).**

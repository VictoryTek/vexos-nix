# NixOS 26.05 "Yarara" Upgrade — Specification

**Feature:** `nixos-26.05-upgrade`
**Date:** 2026-06-13
**Scope:** All roles (desktop, stateless, htpc, server, headless-server, vanilla)

---

## 1. Current State

| Item | Current value |
|------|---------------|
| nixpkgs channel | `github:NixOS/nixpkgs/nixos-25.11` |
| home-manager branch | `github:nix-community/home-manager/release-25.11` |
| `system.nixos.label` | `"25.11"` (in `modules/branding.nix`) |
| `system.stateVersion` | `"25.11"` in all six `configuration-*.nix` files |
| Razer backport overlay | Present in `modules/razer.nix` (lines 18–38) |
| NixOS codename (25.11) | Xantusia |

---

## 2. Problem Definition

vexos-nix is pinned to NixOS 25.11. NixOS 26.05 "Yarara" was released 2026-05-30.
Two weeks have elapsed — the initial post-release bug wave has settled.

Active tech debt that 26.05 resolves:
- `modules/razer.nix` carries a manual backport patch for openrazer 3.10.3 that does not
  compile against Linux 6.18.32+ (hid_report_raw_event gained a bufsize parameter).
  openrazer 3.12.3, which contains the upstream fix, ships in nixpkgs 26.05.
  The overlay has an explicit "Remove once bumped to 26.05+" instruction.

---

## 3. NixOS 26.05 Breaking Change Analysis

Breaking changes from the 26.05 release notes evaluated against vexos-nix:

| Breaking change | Impact on vexos-nix |
|-----------------|---------------------|
| GNOME: Geary no longer auto-installed | **None** — `pkgs.geary` is in `environment.systemPackages` in `modules/gnome.nix:167`, not via GNOME auto-install |
| D-Bus: switched to dbus-broker by default | **None** — `dbus.service` systemd alias is preserved by dbus-broker; `modules/server/vexboard.nix` `after` reference is safe |
| Kernel default: 6.12 → 6.18 | **None** — desktop/htpc/stateless use `linuxPackages_latest` which already tracks latest kernel |
| systemd initrd by default (scripted deprecated) | **None** — all `boot.initrd.kernelModules` entries use the standard NixOS option compatible with both initrd implementations; Plymouth works with systemd initrd |
| `systemd.coredump.extraConfig` removed | **None** — not used anywhere in vexos-nix |
| `systemd.sleep.extraConfig` removed | **None** — not used anywhere in vexos-nix |
| `/dev/root` removed (systemd initrd) | **None** — no vexos-nix module references `/dev/root` |
| `linux_hardened` / `linux-rt` kernels removed | **None** — not used |
| `profiles/hardened` removed | **None** — not used |
| `reiserfs` removed | **None** — not used |

**Conclusion:** No breaking changes require code changes beyond the version bump itself.

---

## 4. Proposed Solution Architecture

Minimal surgical upgrade: change two URL strings in `flake.nix`, update one label string in
`modules/branding.nix`, delete the now-obsolete razer backport overlay, update the
preflight script header comment, and run `nix flake update` to refresh `flake.lock`.

`system.stateVersion` is intentionally unchanged (stays at `"25.11"` in all
`configuration-*.nix` files — this value must not be changed after initial installation).

---

## 5. Implementation Steps

### Step 1 — `flake.nix` (2 line edits)

```
flake.nix:5   nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"
           →  nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"

flake.nix:15  url = "github:nix-community/home-manager/release-25.11"
           →  url = "github:nix-community/home-manager/release-26.05"
```

### Step 2 — `modules/branding.nix` (1 line edit + 2 comment lines)

```
branding.nix:98   system.nixos.label = "25.11"
              →   system.nixos.label = "26.05"

branding.nix:130  # Auto-generated: "… Xantusia 25.11 (Linux 6.6.132))"
              →   # Auto-generated: "… Yarara 26.05 (Linux 6.18.x))"

branding.nix:131  # Trimmed to:     "… Xantusia 25.11)"
              →   # Trimmed to:     "… Yarara 26.05)"
```

### Step 3 — `modules/razer.nix` (delete overlay block)

Delete lines 18–38 entirely (the `nixpkgs.overlays` block with the
`linuxPackages_latest.extend` backport). The fixed openrazer 3.12.3 ships in nixpkgs
26.05 — the patch is no longer needed.

Remove the patch-note comment block (lines 9–14) and the "Remove this overlay once"
instruction (lines 12–14 / 29–30) since they are only meaningful while the workaround
exists.

The `hardware.openrazer` and `environment.systemPackages` config blocks (lines 40–49)
are unaffected and remain.

### Step 4 — `scripts/preflight.sh` (1 comment line)

```
preflight.sh:4  # Project: vexos-nix — Personal NixOS Flake (NixOS 25.11)
            →   # Project: vexos-nix — Personal NixOS Flake (NixOS 26.05)
```

### Step 5 — `nix flake update` (refresh flake.lock)

Run `nix flake update` from the repo root to pull all inputs to their latest revisions
on the newly pinned channels. This updates `flake.lock` to pin 26.05 nixpkgs,
home-manager release-26.05, and refreshes all other inputs.

---

## 6. Out of Scope

- `system.stateVersion` — must NOT change (NixOS invariant)
- `CLAUDE.md` framework version string — documentation-only, not a tracked NixOS config
- `modules/server/plex.nix` TODO(2026-05) workaround — separate tracked task (MASTER_PLAN
  L-17); the Phase 3 review MUST evaluate
  `.#nixosConfigurations.vexos-server-amd.config.systemd.services.plex.environment.LD_LIBRARY_PATH`
  and note the result, but removal is not in scope for this PR unless the value is
  confirmed empty/absent (i.e., upstream fix landed).
- proxmox-nixos 26.05 compatibility — confirmed functionally working per upstream PR #237;
  Phase 3 server dry-builds are the gate.

---

## 7. Dependencies

No new external dependencies. All inputs are existing tracked flake inputs.

- `home-manager/release-26.05` — matches nixpkgs 26.05 (community project, branches
  track NixOS releases)
- `sops-nix`, `impermanence`, `up`, `vexboard` — track nixos-unstable/master, unaffected
- `proxmox-nixos` — manages its own pin, functionally compatible with 26.05 per upstream

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| proxmox-nixos 26.05 eval failure | Low — PR #237 reports working | Phase 3 server dry-builds are hard gate; if they fail the PR is blocked |
| Razer overlay removal breaks openrazer on kernel 7.x | None — fix ships in 26.05 nixpkgs | Phase 3 desktop dry-build validates the package resolves cleanly |
| home-manager release-26.05 API change | Very low — HM tracks NixOS closely | Phase 3 dry-builds cover all home-manager wired roles |
| Stale TODO in plex.nix creates confusion | Low | Phase 3 review explicitly checks plex LD_LIBRARY_PATH eval result and notes it |

---

## 9. Files Modified

| File | Change |
|------|--------|
| `flake.nix` | 2 URL changes (nixpkgs + home-manager channels) |
| `flake.lock` | Full refresh via `nix flake update` |
| `modules/branding.nix` | `system.nixos.label` value + 2 codename comments |
| `modules/razer.nix` | Delete obsolete backport overlay block |
| `scripts/preflight.sh` | Header comment version string |

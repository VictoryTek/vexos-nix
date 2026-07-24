# Migrate Discord/Vesktop from nixpkgs to Flatpak — Review

Spec: `discord_vesktop_flatpak_migration_spec.md`
Modified files: `modules/gaming.nix`, `modules/gnome-desktop.nix`,
`home-desktop.nix`

## Findings

1. **Specification compliance:** matches spec exactly — nixpkgs packages
   removed from `environment.systemPackages`, both apps added to
   `vexos.flatpak.extraApps` and `vexos.flatpak.managedApps`, `.desktop`
   references updated in both GNOME app-folder locations.
2. **Fix verification:** unlike every other attempt this session, this fix
   is backed by the user's own direct, real-hardware confirmation (Bazzite
   comparison test, then Vesktop-as-Flatpak tested working on this actual
   system) — not a hypothesis awaiting a rebuild-and-pray cycle.
3. **Consistency (Module Architecture Pattern):** follows the exact existing
   pattern in the same file for Lutris/ProtonPlus/PrismLauncher — no new
   `lib.mkIf` guard added, uses the module's own `vexos.flatpak.extraApps`/
   `managedApps` options.
4. **Completeness:** confirmed via `nix eval` that the Flatpak app IDs
   resolve into both `extraApps` and `managedApps`, and that no
   `discord`/`vesktop` nixpkgs derivation remains in `systemPackages`
   (empty-list check).
5. **Maintainability:** stale comment about `pkgs.unstable.vesktop`'s
   CVE-flagged-pnpm build removed along with the code it described (would
   have been misleading dead documentation otherwise). New comment explains
   *why* Flatpak was chosen (screen-share failure investigation) with a
   pointer to the full diagnostic record.
6. **Surgical scope:** diff is limited to the three files that needed to
   change — package list, Flatpak app registration, and the two `.desktop`
   ID references. No unrelated reformatting.

## Build validation

- `nix eval --impure` toplevel, `vexos-desktop-nvidia` (directly affected
  host): PASS
- `vexos-desktop-amd`, `vexos-desktop-vm`, `vexos-htpc-amd`: PASS
  (`gnome-desktop.nix`/`home-desktop.nix` are desktop-role shared files —
  htpc included since `gaming.nix` is also imported there)
- `vexos-server-amd`: FAIL — pre-existing, unrelated `hostId` placeholder
  assertion (documented in this session's earlier reviews; confirmed
  untouched by this diff via `git diff`)
- `bash scripts/preflight.sh`: PASS (same pre-existing WARN-level findings
  as every prior review this session — repo-wide formatting gap, stale
  flake.lock inputs, vexboard placeholder secret string; none introduced by
  this change)
- No new flake inputs, no `hardware-configuration.nix` committed, no
  `stateVersion` changes

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A (user-verified working fix, not theoretical) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result

**PASS.** This closes out the multi-session Discord/Vesktop investigation:
native nixpkgs builds are structurally incompatible with screen-share on
this hybrid AMD+NVIDIA laptop's current driver/kernel/compositor stack;
Flatpak sidesteps whatever incompatibility exists (likely runtime graphics
library version pinning) and is confirmed working by the user directly.

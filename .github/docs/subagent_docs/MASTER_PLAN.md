# vexos-nix — Master Plan

Generated: 2026-06-11
Consolidates: ANALYSIS_BUGS.md · ANALYSIS_ARCH.md · ANALYSIS_FEATURES.md
Duplicates removed; items ordered by effort within each priority band.

Legend: `[B]` Bug · `[A]` Architecture · `[F]` Feature
Check boxes are ticked as items are completed in this session.

---

## HIGH PRIORITY

### Quick wins (< 1 hour each)

- [x] **H-01** `[B/F]` CI: make daily auto-update skip `nixpkgs-unstable` as the README documents
  - **Source:** FEATURES 1.3, ARCH 2.3
  - Change `nix flake update` → named inputs only in `update-flake-lock.yml`; add a `workflow_dispatch` "bump unstable" job
  - **Resolution:** CI behaviour kept as-is (updates all inputs including unstable). README corrected to accurately document this. (`README.md`)

- [x] **H-02** `[B]` CI: add 4 missing server/headless-server legacy-NVIDIA outputs to the eval matrix
  - **Source:** BUGS M20, FEATURES 1.5
  - Add `vexos-server-nvidia-legacy535/470` and `vexos-headless-server-nvidia-legacy535/470` to `.github/workflows/ci.yml` matrix groups
  - **Resolution:** Expanded scope after research — `legacy_470` (Kepler) dropped entirely to align with Bazzite's driver model (Bazzite ships `akmod-nvidia-580xx` for Maxwell/Pascal/Volta only; Kepler is unsupported upstream). `legacy_535` added to server and headless-server CI groups. All `legacy470` outputs removed from `flake.nix`, `modules/gpu/nvidia.nix`, `ci.yml`, `README.md`, `template/etc-nixos-flake.nix`, `scripts/install.sh`. CI count comment corrected (6 groups, 29 configs). `legacy_580` migration deferred pending nixpkgs issue #503740. Also partially resolves **H-11** (template and installer no longer reference nonexistent legacy470 outputs).

### Bugs — Contained / Surgical

- [x] **H-03** `[B]` `vexos.network.staticWired` writes an invalid NM keyfile — static IP silently ignored
  - **Source:** BUGS H3 · `modules/network.nix:116-121`
  - Replace `addresses=` with `address1 = "${cfg.address},${cfg.gateway}"` per nm-settings-keyfile(5)
  - **Resolution:** Replaced `addresses` + `gateway` keys with single `address1 = "ip/prefix,gateway"` per nm-settings-keyfile(5). (`modules/network.nix`)

- [x] **H-04** `[B]` `just version-upgrade` rewrites `system.stateVersion` — violates the project's hard invariant
  - **Source:** BUGS H5 · `justfile:646-652`
  - Delete the `sed -i` stateVersion rewrite step; keep steps 1–2 (input URL bumps) intact
  - **Resolution:** Deleted the `stateVersion` rewrite loop; updated recipe description comment to explicitly document that `stateVersion` is intentionally not changed. README was already correct. (`justfile`)

- [x] **H-05** `[B]` fail2ban cockpit jail references a nonexistent filter — breaks fail2ban on all servers
  - **Source:** BUGS H8 · `modules/security-server.nix:74-79`
  - Ship `environment.etc."fail2ban/filter.d/cockpit.local"` with a journal-based filter, or drop the jail
  - **Resolution:** Dropped the Cockpit jail. Research confirmed Cockpit's PAM logs omit the remote IP (upstream bug #722, open since 2014), making IP-based banning impossible regardless of filter. Fail2ban now starts cleanly; SSH and recidive jails function correctly. Comment documents the reason. (`modules/security-server.nix`)

- [x] **H-06** `[B]` `migrate-to-stateless.sh` always crashes at the end — `$CUSTOM_PASSWORD_SET` is never set
  - **Source:** BUGS H7 · `scripts/migrate-to-stateless.sh:420`
  - Set `CUSTOM_PASSWORD_SET=true/false` based on which password branch (lines 316–345) executed; fix the misleading "vexos default" message
  - **Resolution:** Initialised `CUSTOM_PASSWORD_SET=false` before the password detection block; set to `true` when existing hash is found. Fixed the `else` summary message from "vexos (default)" to "the new password you just set". (`scripts/migrate-to-stateless.sh`)

- [x] **H-07** `[B]` install.sh NVIDIA-branch prompt accepts any non-empty input and silently selects "latest"
  - **Source:** BUGS H6 · `scripts/install.sh:171-183`
  - Remove the stray `[[ -n "$INPUT" ]] && break` line; rewrite loop with a proper answered-flag (matching the pattern in `justfile:302-318`)
  - **Resolution:** Rewrote install.sh prompt to `while true` with explicit `break` per valid case; removed stray break. Also removed legacy470 from both NVIDIA sub-selection blocks in justfile (H-02 straggler). (`scripts/install.sh`, `justfile`)

### Bugs — Security / Data Integrity

- [x] **H-08** `[B]` Odysseus clones a moving HEAD and docker-builds it as root at service start — arbitrary code exec risk
  - **Source:** BUGS M14, ARCH 1.4 · `modules/server/odysseus.nix:96-121`
  - Pin a specific commit SHA in the clone (or rewrite with `pkgs.fetchFromGitHub` + `dockerTools`); replace `chromadb/chroma:latest` with a pinned tag
  - **Resolution:** Module removed entirely. The app requires building ~50 Python deps from source with no published image — not suitable for a declarative NixOS module. Can be run ad-hoc via `docker compose` using the upstream README. (`modules/server/odysseus.nix` deleted, `modules/server/default.nix`, `template/server-services.nix`)

- [x] **H-09** `[B]` VexBoard ships a literal "change-me" auth secret with firewall open by default
  - **Source:** BUGS M13 · `modules/server/vexboard.nix:50-58`
  - Add `lib.mkIf (cfg.secretFile == null) (throw "...")` assertion; default `openFirewall = false`
  - **Resolution:** Added NixOS `assertions` block that hard-fails evaluation if `secretFile` is null, with a message that provides the exact `openssl rand` command to generate a secret. Changed `openFirewall` default from `true` to `false` — LAN exposure is now explicit opt-in. Service discovery is unaffected (local systemd/Docker polling). (`modules/server/vexboard.nix`)

- [x] **H-10** `[B]` Plaintext secrets under `/etc/nixos/secrets` are copied into the world-readable Nix store on every rebuild
  - **Source:** BUGS H2 · `justfile:1988-1995`, `modules/nix.nix:128-240`
  - Switch rebuild URIs from `path:/etc/nixos` to `git+file:/etc/nixos` (the installer already git-inits `/etc/nixos` so untracked files are excluded); or move secrets root outside the flake directory
  - **Resolution:** Changed all 15 occurrences of `path:/etc/nixos` → `git+file:///etc/nixos` across `modules/nix.nix` (4), `justfile` (7), `scripts/install.sh` (4). Added `.gitignore` to `template/` and wrote it in all three init paths, excluding `secrets/`, `hardware-configuration.nix`, `*.bak`, `vexos-variant`, `kernel-install-override.nix`, `stateless-user-override.nix`. Fixed `stateless-setup.sh` to persist the `.git` directory to `/persistent/etc/nixos`. Added a one-time auto-init guard in `vexos-update` that initializes the git repo on first run for existing installs.

### Bugs — Functional Correctness

- [x] **H-11** `[B]` Template missing NVIDIA legacy outputs — installer builds config names that don't exist in the template
  - **Source:** BUGS H4 · `template/etc-nixos-flake.nix`, `scripts/install.sh:160-184`
  - Add `vexos-<role>-nvidia-legacy535` and `vexos-<role>-nvidia-legacy470` outputs (or a `mkVariant` helper) to the template for all five roles
  - **Resolution:** Added all 6 `nvidia-legacy535` outputs to `template/etc-nixos-flake.nix` (desktop, stateless, htpc, server, headless-server, vanilla). Added `vexos-vanilla-nvidia-legacy535` to `flake.nix` hostList (count 29→30) and CI vanilla group. Removed vanilla exclusion from NVIDIA driver branch selection in `scripts/install.sh`. (`template/etc-nixos-flake.nix`, `flake.nix`, `.github/workflows/ci.yml`, `scripts/install.sh`)

- [x] **H-12** `[B/A]` `vexos.user.name` option is non-functional — account is hardcoded as `nimda`, overriding the option breaks home-manager
  - **Source:** BUGS H1, ARCH 1.3 · `modules/users.nix:10-27`
  - Change `users.users.nimda = { ... }` → `users.users.${cfg.name} = { ... }`; audit all ~15 consumer sites (gaming, development, audio, virtualization, gnome, network, flake.nix, etc.)
  - **Resolution:** Fixed the one-line bug — `users.users.nimda` → `users.users.${cfg.name}`. All 15+ consumer modules already used `${config.vexos.user.name}` correctly; no other code changes needed. Cleaned up stale "nimda" references in 10 comment-only locations. Default "nimda" preserved. The original intent (auto-detect existing NixOS username at install time) is feasible on the migration path only; flagged as a future item. (`modules/users.nix`, `modules/audio.nix`, `modules/gaming.nix`, `modules/server/jellyfin.nix`, `modules/impermanence.nix`, `home-headless-server.nix`, `home-htpc.nix`, `home-server.nix`, `home-stateless.nix`, `home-vanilla.nix`)

- [x] **H-13** `[A]` Personal ASUS hardware config baked into shared desktop host variants
  - **Source:** ARCH 2.1, BUGS L11 · `hosts/desktop-{amd,nvidia,intel}.nix:11-12`
  - Move `vexos.hardware.asus.enable = true` and `batteryChargeLimit = 80` to a per-machine overlay path; default the option to `false` in the shared variant files
  - **Resolution:** Removed the two hardcoded ASUS lines from all three desktop host files. Updated `scripts/install.sh` ASUS prompt: renamed "laptop?" → "device?", removed the incorrect stateless role exclusion, added a follow-up "Is this device a laptop?" question that sets `batteryChargeLimit = 80` only for laptops. Updated `template/etc-nixos-flake.nix` comment to show both device and laptop forms. (`hosts/desktop-amd.nix`, `hosts/desktop-nvidia.nix`, `hosts/desktop-intel.nix`, `scripts/install.sh`, `template/etc-nixos-flake.nix`)

### Features — High Value

- [x] **H-14** `[F]` ~~Re-land snapper btrfs snapshots~~ — DECLINED
  - **Source:** FEATURES 1.1 · `modules/system.nix` (existing `vexos.btrfs.enable` block)
  - **Resolution:** Declined by user — NixOS generation rollback already covers the primary use case for this project; the added complexity of a second snapshot/rollback system (snapper) wasn't judged worth it. `btrfs-assistant` remains installed but without a configured backend.

- [x] **H-15** `[F]` Complete the sops-nix "phased migration" — it stalled at 5 secrets; plaintext backend leaks into store (see H-10)
  - **Source:** FEATURES 1.2, ARCH 4.2 · `modules/secrets-sops.nix`, `modules/server/vexboard.nix`
  - **Resolution:** Wired vexboard, kiji-proxy, and listmonk (all already had file-based secret inputs) into `secrets-sops.nix`. Added new `environmentFile`/`jwtSecretFile`/`sessionSecretFile`/`storageEncryptionKeyFile` options to `vaultwarden.nix` and `authelia.nix` (neither had any secret plumbing before) and wired those too. Added `just secrets-init` (age key + guidance) and VexBoard plaintext-path auto-generation at activation. `code-server` explicitly excluded — upstream module has no file-based secret input, only an eval-time string, incompatible with sops's runtime-only decryption. (`modules/secrets-sops.nix`, `modules/server/vaultwarden.nix`, `modules/server/authelia.nix`, `modules/server/vexboard.nix`, `justfile`)

- [x] **H-16** `[F]` Declarative restic backup module — no backup tooling exists anywhere for 50+ stateful services
  - **Source:** FEATURES 2.1
  - **Resolution:** Added `modules/server/backup.nix` (`vexos.server.backup`) using `services.restic.backups`, with a static `_server_service_names`-keyed table of default data paths assembled via `lib.optionals config.vexos.server.<x>.enable`, a PostgreSQL `pg_dumpall` pre/cleanup hook gated on `services.postgresql.enable`, and Syncthing deliberately excluded (its dataDir is the whole user home directory). Registered in `modules/server/default.nix` and wired into `justfile` (service list, enable-time repository/password prompts, status mapping, `backup-now` recipe). Failure-alert hook left as a documented comment for H-17 (ntfy), which doesn't exist yet. (`modules/server/backup.nix`, `modules/server/default.nix`, `justfile`)

- [x] **H-17** `[F]` Wire system events into the self-hosted ntfy server that currently has zero producers
  - **Source:** FEATURES 2.2 · `modules/server/ntfy.nix`
  - **Resolution:** Added `modules/notify.nix` (cross-role, imported by all six `configuration-*.nix` alongside `modules/nix.nix`) with `vexos.notify.ntfyUrl`/`tokenFile` options, a safe-no-op-by-default `vexos-notify` script, and a generic `notify-failure@.service` template. Wired two producers: `restic-backups-main` (H-16) fires `notify-failure@backup` on failure, and `vexos-update` sends a completion notice after a successful `nixos-rebuild switch`. ntfy token provisioning remains a documented manual step (`ntfy token add`) — upstream `services.ntfy-sh` has no declarative token/ACL mechanism. (`modules/notify.nix`, `modules/server/backup.nix`, `modules/nix.nix`, all six `configuration-*.nix`)

### Architecture — Large Scope

- [x] **H-18** `[A]` `mkHost` vs `mkBaseModule` share the same `roles` table but re-implement `baseModules` independently — vanilla overlay divergence already present
  - **Source:** ARCH 1.2 · `flake.nix:285-314` vs `:125-170`
  - **Resolution:** `mkBaseModule` now reads `roles.${role}.baseModules` directly instead of three separate hand-derived copies (a re-inlined overlay block, an `environment.systemPackages` role-string predicate, and two `lib.optionals (role == ...)` blocks for proxmox/sops/vexboard). Confirmed via synthetic `nixosSystem` builds that `nixosModules.vanillaBase` no longer carries the unstable/custom-pkgs overlays (the actual bug — overlay count 2 → 0), while `serverBase`/`headlessServerBase` are unaffected. All `nixosConfigurations` (`mkHost`) `.drv` hashes are byte-identical before/after, confirming zero blast radius on the tracked repo's own builds. (`flake.nix`)

- [x] **H-19** `[A]` Builder-machine `/etc/nixos` state leaks into flake outputs via `builtins.pathExists` at eval time
  - **Source:** ARCH 1.1 · `flake.nix:89-99`
  - **Resolution:** Split `roles.<role>.extraModules` into `extraModules` (shared, pure — e.g. impermanence) and a new `hostLocalModules` (the three impure `/etc/nixos/*` checks: `serverServicesModule`, `featuresModule` — folded in for consistency, same defect shape — and `statelessUserOverrideModule`). `mkHost` includes both (preserving real repo-checkout deployment behavior — confirmed via byte-identical `.drv` hashes before/after); `mkBaseModule` includes only `extraModules`, since `template/etc-nixos-flake.nix` (the actual `nixosModules.*Base` consumer) already performs the equivalent host-local check itself with its own relative paths. (`flake.nix`)

- [x] **H-12b** `[F]` Auto-detect and adopt existing NixOS username at install time
  - **Source:** H-12 design intent — original goal was to adopt the username set during NixOS install
  - **Resolution:** `migrate-to-stateless.sh` now detects the real UID 1000 account (`getent passwd 1000`, falling back to `"nimda"`) and uses it for the shadow-password lookup, the final login printout, and — only when it differs from the default — writes `vexos.user.name = "<detected>";` into the existing `stateless-user-override.nix` mechanism. Verified end-to-end with a synthetic `nixosSystem` build that `modules/users.nix` correctly creates the detected account. The optional `install.sh` prompt was explicitly declined by the user — there's no prior account to detect on a fresh ISO install, so it would be a separate feature, not a fix. (`scripts/migrate-to-stateless.sh`)

---

## MEDIUM PRIORITY

### Bugs — Medium Impact

- [x] **M-01** `[B]` boot-discovery finds at most one ESP — `by-parttype/` is a last-one-wins symlink, not per-partition
  - **Source:** BUGS M1 · `modules/boot-discovery.nix:35`
  - **Resolution:** The `by-parttype/` issue itself had already been superseded by a prior rewrite to `sfdisk --dump`-based discovery (module header already documented this). Found and fixed two remaining real defects via code review: (1) ESP matching only recognized the GPT GUID, silently skipping MBR-labeled disks (MBR ESP type code `ef` never matched) — plausible root cause for the user's reported dual-boot-on-separate-drives failure. (2) `efibootmgr --create` failures were unconditionally swallowed via `|| true`, so no failure was ever visible in the journal. Both fixed; verified the new GPT+MBR matching logic against synthetic sfdisk-dump lines for all four cases (GPT ESP/non-ESP, MBR ESP/non-ESP). Not verified against real dual-boot hardware — live diagnostics weren't available this session. (`modules/boot-discovery.nix`)

- [x] **M-02** `[B]` Container backend conflict — `podman.nix` and six docker-backed modules all set the same option at priority 100
  - **Source:** BUGS M2 · `modules/server/podman.nix:34`, `modules/server/{dozzle,portainer,homepage,authelia,uptime-kuma,stirling-pdf,nginx-proxy-manager}.nix`
  - **Resolution:** Changed all seven docker-backed modules' `virtualisation.oci-containers.backend = "docker";` to `lib.mkDefault "docker"`, letting podman's plain-priority `"podman"` win cleanly when both are enabled. While validating the full combination, found and fixed (by user decision) a second, adjacent, pre-existing conflict: nixpkgs's own dockerCompat/docker assertion, since the seven modules' `virtualisation.docker.enable = lib.mkDefault true` was never overridden when podman is active — added `virtualisation.docker.enable = lib.mkForce false;` to `podman.nix`. Verified both the podman+all-seven-services combination and the docker-only (no podman) path build cleanly. (`modules/server/{dozzle,portainer,homepage,authelia,uptime-kuma,stirling-pdf,nginx-proxy-manager,podman}.nix`)

- [x] **M-03** `[B]` Unbound on port 5353 collides with Avahi mDNS, which is enabled on every role
  - **Source:** BUGS M3 · `modules/server/unbound.nix:19`
  - **Resolution:** Changed Unbound to port 5335 (conventional Unbound-behind-AdGuard/Pi-hole port) across `settings.server.port`, both firewall port lists, and the header comment. Updated matching references in `template/server-services.nix` and two `justfile` spots. Verified via forced-branch build that Unbound (5335) and Avahi (5353) now coexist without conflict. (`modules/server/unbound.nix`, `template/server-services.nix`, `justfile`)

- [x] **M-04** `[B]` headscale `serverUrl = "http://0.0.0.0:<port>"` — clients cannot connect to a bind address
  - **Source:** BUGS M4 · `modules/server/headscale.nix:24`
  - **Resolution:** Confirmed the current nixpkgs uses `services.headscale.settings.server_url` — the top-level `serverUrl` this module previously set is deprecated (renamed via `mkRenamedOptionModule`). Added a required `vexos.server.headscale.serverUrl` option (invalid-placeholder-default + assertion, matching `vaultwarden.nix`'s established pattern) and wired it to the current option path. Verified via forced builds that the assertion fires without a real value and that a supplied value correctly reaches `settings.server_url`. (`modules/server/headscale.nix`)

- [x] **M-05** `[B]` `lib.mkDefault [ "btrfs" ]` in initrd discarded by every generated `hardware-configuration.nix`
  - **Source:** BUGS M5 · `modules/stateless-disk.nix:74`
  - **Resolution:** Changed to plain `[ "btrfs" ]` so it shares priority 100 with `hardware-configuration.nix`'s own always-present `boot.initrd.kernelModules` definition, merging (concatenating) instead of being discarded whenever that list happens to be empty. Verified with synthetic builds against both an empty and a non-empty stub `hardware-configuration.nix` that `btrfs` is now always present in the final merged list. (`modules/stateless-disk.nix`)

- [x] **M-06** `[B]` Bluetooth codec list omits SBC — SBC-only devices cannot establish A2DP audio
  - **Source:** BUGS M6 · `modules/audio.nix:38`
  - **Resolution:** Added `"sbc" "sbc_xq"` to `bluez5.codecs`, ahead of the existing higher-quality codecs. `bluez5.codecs` is an allowlist, not a preference-with-fallback list, so devices supporting only the mandatory baseline SBC codec previously shared zero codecs with the host and couldn't establish A2DP at all. Verified the final merged codec list on `vexos-desktop-amd`. (`modules/audio.nix`)

- [x] **M-07** `[B]` `gnome-background-reload` resume service is `wantedBy` targets that this same module masks
  - **Source:** BUGS M7 · `modules/system-nosleep.nix:69-93`
  - **Resolution:** Deleted the dead resume service block. Its `wantedBy` targets (suspend/hibernate/hybrid-sleep) are permanently masked by this same file's Layer 4, so the service could never activate. Verified the service is absent from the built config. (`modules/system-nosleep.nix`)

- [x] **M-08** `[B]` AppArmor wineserver profile attaches to `/usr/bin/wineserver` — that path doesn't exist on NixOS
  - **Source:** BUGS M8 · `modules/gaming.nix:111-124`
  - **Resolution:** Changed the profile's attachment path to `${pkgs.wineWow64Packages.stagingFull}/bin/wineserver` — the exact real store path of the Wine package this same file already installs — instead of the suggested glob, since it's more precise and automatically stays correct if the package changes. Verified the rendered profile text contains a real, concrete store path. (`modules/gaming.nix`)

- [x] **M-09** `[B]` `plugdev` group is never created — user membership is a silent no-op
  - **Source:** BUGS M9 · `modules/gaming.nix:103`
  - **Resolution:** Dropped the `plugdev` membership rather than declaring an empty group — repo-wide grep confirmed no udev rule in this project ever targets `GROUP="plugdev"` (all controller rules already use `GROUP="input"`), so creating the group would have had no functional effect. Verified the merged `extraGroups` list no longer contains `plugdev`. (`modules/gaming.nix`)

- [x] **M-10** `[B]` `elevator=kyber` kernel boot parameter was removed in kernel 5.0 — I/O scheduler not set
  - **Source:** BUGS M10 · `modules/system.nix:91-95`
  - **Resolution:** Replaced the dead boot parameter with a `services.udev.extraRules` entry (`ACTION=="add|change", KERNEL=="nvme*|sd*", ATTR{queue/scheduler}="kyber"`), the current supported mechanism. Verified the rule merges correctly with `modules/gaming.nix`'s own udev rules block rather than conflicting. (`modules/system.nix`)

- [x] **M-11** `[B]` `just reset-defaults` removes wrong stamp name and leaves all GNOME extensions permanently disabled
  - **Source:** BUGS M11 · `justfile:804-820`
  - **Resolution:** Replaced the single hardcoded `.dconf-app-folders-initialized-v2` removal with a `.dconf-*-initialized*` glob, covering all four stamp variants actually in use (app-folders v2/v3, extensions unversioned/v3 — desktop's stamps were `-v3`, not `-v2`, and `extensions-initialized` wasn't being cleared at all, which is why extensions stayed disabled). Verified against real stamp names in an isolated scratch `$HOME` that exactly the four dconf stamps are removed and unrelated migration stamps are preserved. (`justfile`)

- [x] **M-12** `[B]` Attic `just enable-attic` help text instructs HS256 token; atticd requires RS256 RSA key
  - **Source:** BUGS M12 · `justfile:1437-1444`
  - **Resolution:** Fixed the post-enable info block for attic to match `attic.nix`'s own correct documentation: `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64` → `RS256`, and the generation command → `openssl genrsa -traditional 4096 | base64 -w0`. Confirmed no `HS256` references remain anywhere in the repo. (`justfile`)

- [x] **M-13** `[B]` All server host variants share the same placeholder ZFS `hostId` — pool-import protection bypassed
  - **Source:** BUGS M15 · `hosts/server-*.nix`, `hosts/headless-server-*.nix`
  - **Resolution:** Wrapped all 8 host files' hostId placeholders in `lib.mkDefault`; extended `zfs-server.nix`'s assertion to reject all 8 committed placeholders (not just `"00000000"`), moving its own fallback to `lib.mkOverride 1500` to avoid a same-priority conflict with the host files. This correctly broke CI (every server/headless-server config now fails the strengthened assertion by design, since none carry a real per-machine value) — resolved by user decision: added a `networking.hostId` line to the stub `hardware-configuration.nix` CI already writes, mirroring the existing stateless-password CI fixture pattern. `template/etc-nixos-flake.nix` (the real thin-wrapper deployment path) was already correct and untouched. (`hosts/{server,headless-server}-{amd,nvidia,intel,vm}.nix`, `modules/zfs-server.nix`, `.github/workflows/ci.yml`)

- [x] **M-14** `[B]` `vexos-update` deletes the `flake.lock` backup before the step that can still fail
  - **Source:** BUGS M21 · `modules/nix.nix:168-239`
  - **Resolution:** Moved `flake.lock.bak` removal to after a successful `nixos-rebuild switch` (relies on `set -euo pipefail` aborting before that line on failure — verified with an isolated bash simulation). Both `nixos-rebuild dry-build` calls now detect their own failure instead of swallowing it via `|| true`, restoring/removing the lock backup as appropriate before exiting. (`modules/nix.nix`)

- [x] **M-15** `[B]` kavita requires a manually created token file with no assertion — enable → permanent crash loop
  - **Source:** BUGS M22 · `modules/server/kavita.nix:22`
  - **Resolution:** Added `system.activationScripts.kavitaTokenKey`, auto-generating the 512-bit token key idempotently on first activation, matching VexBoard's existing secret-auto-generation pattern (H-15) — appropriate here since the key is a purely internal secret never typed by a user, unlike code-server's password. Verified byte length, permissions, and idempotency directly. The noted unrelated `services.kavita.port` deprecation warning was fixed in the same pass as M-16, at the user's request (`port` → `settings.Port`). (`modules/server/kavita.nix`)

- [x] **M-16** `[B]` `just enable` corrupts `server-services.nix` once the file contains nested braces
  - **Source:** BUGS M23 · `justfile:1330-1334`
  - **Resolution:** Anchored all 4 occurrences of the fragile `sed -i "s|}|..."` pattern (enable-feature, enable service, and both VexBoard auto-secret/auto-enable insertions — not just the one named in the source) to `"\$ s|^}|..."` — only the file's actual final line. Directly reproduced the corruption with a synthetic nested-brace file and confirmed the old pattern corrupts it while the new pattern doesn't. (`justfile`)

- [x] **M-17** `[B]` Homepage container rejects all requests — `HOMEPAGE_ALLOWED_HOSTS` is unset on v0.10+
  - **Source:** BUGS M24 · `modules/server/homepage.nix:30-38`
  - **Resolution:** Added `vexos.server.homepage.allowedHosts` option (default `"localhost:<port>"`, works out of the box) wired to the container's `HOMEPAGE_ALLOWED_HOSTS` env var. Homepage has no wildcard support for this value, so the option description documents adding every real access hostname/IP. Verified both default and custom-override behavior. (`modules/server/homepage.nix`)

- [x] **M-18** `[B]` PhotoGIMP launcher ships on desktop but `org.gimp.GIMP` is never installed
  - **Source:** BUGS M17 · `home-desktop.nix:13`, `home/photogimp.nix`
  - **Resolution:** Confirmed with the user (whose working GIMP install predates or exists outside this repo's declarative management) before proceeding. Added `org.gimp.GIMP` to `modules/flatpak-desktop.nix`'s `extraApps` list — the exact file already scoped to the desktop role, matching `photogimp.nix`'s own scope. Verified in the merged Flatpak app list. (`modules/flatpak-desktop.nix`)

- [x] **M-19** `[B]` `just` alias broken on the vanilla role — it points to a justfile that vanilla never deploys
  - **Source:** BUGS M18 · `home/bash-common.nix`, `configuration-vanilla.nix:10-16`
  - **Resolution:** Made the alias conditional (`lib.optionalAttrs (osConfig.environment.etc ? "nixos/justfile")`) rather than importing `packages-common.nix`, since that would add several CLI tools (git, curl, wget, btop, inxi, pciutils) contradicting vanilla's own stated "mirrors stock NixOS+GNOME, no custom packages" design intent. Verified the alias is present on desktop and correctly absent on vanilla, with zero behavior change for every other role. (`home/bash-common.nix`)

- [x] **M-20** `[B]` SSH password auth + open port 22 + GNOME auto-login on non-server roles with no fail2ban
  - **Source:** BUGS M19 · `modules/network.nix:156-175`, `modules/gnome.nix:126-130`
  - **Resolution:** Per explicit user preference (password auth was deliberately restored in a prior session), only the fail2ban option was implemented — `PasswordAuthentication` untouched. Added `modules/security-desktop.nix` (Option B module, matching `security-server.nix`'s fail2ban config) imported by desktop/htpc/stateless — the three roles with SSH+password-auth that lacked it (server/headless-server already had it). Removed the redundant `allowedTCPPorts = [ 22 ]` line, verified port 22 stays open via `openssh.openFirewall`. GNOME auto-login noted as compounding context but left out of scope. (`modules/security-desktop.nix`, `configuration-{desktop,htpc,stateless}.nix`, `modules/network.nix`)

- [x] **M-21** `[B]` ~~install.sh cache check excludes `linux-[0-9]` from `SOURCE_BUILDS`~~ — STALE, no longer applicable
  - **Source:** BUGS M16 · `scripts/install.sh:359,401`
  - **Resolution:** Investigated; the current `install.sh` has no `linux-[0-9]` exclusion pattern anywhere, and its cache-check section is explicitly documented as informational-only — `nixos-rebuild` always proceeds regardless of what's found, with no "abort rule" left to bypass. That abort-and-restore-lock behavior lives in `vexos-update` (`HEAVY_BUILD_REGEX`, already covered by M-14), not `install.sh`. The script has evolved past the described bug since the original analysis; user confirmed to mark resolved rather than invent an abort mechanism install.sh doesn't use by design. No code changes made.

- [x] **M-22** `[B]` Seven OCI containers track `:latest` — silently self-updating, non-reproducible, one already broken (M-17)
  - **Source:** BUGS M25, ARCH 3.2 · `portainer.nix`, `homepage.nix`, `stirling-pdf.nix`, `authelia.nix`, `nginx-proxy-manager.nix`, `dockhand.nix`, `dozzle.nix`
  - **Resolution:** Pinned all 7 (not just the two "at minimum") to versions verified live against Docker Hub/GHCR (`portainer-ce:2.43.0`, `homepage:v1.13.2`, `s-pdf:2.14.0`, `authelia:4.39.20`, `nginx-proxy-manager:2.15.1`, `dockhand:v1.0.36`, `dozzle:v10.6.7`). Per user request, added `.github/workflows/update-container-images.yml` — a new Wednesday-scheduled workflow (matching `update-flake-lock.yml`'s direct-commit style) that checks each registry for a newer matching tag and bumps the pin automatically, resolving the reproducibility-vs-staying-current tradeoff. Verified all 7 images resolve correctly together in a forced build. (`modules/server/{portainer,homepage,stirling-pdf,authelia,nginx-proxy-manager,dockhand,dozzle}.nix`, `.github/workflows/update-container-images.yml`)

- [x] **M-23** `[B]` Several services exposed LAN-wide with no authentication by module design, no opt-out
  - **Source:** BUGS M26 · `loki.nix`, `netdata.nix`, `zigbee2mqtt.nix`, `kiji-proxy.nix`, `portbook.nix`
  - **Resolution:** Added `openFirewall` option to all five (default `true` for loki/netdata/zigbee2mqtt/portbook, preserving current behavior; default `false` for kiji-proxy, matching its documented localhost-only usage). kiji-proxy's `PROXY_PORT` bind format is undocumented upstream, so loopback restriction is enforced via the firewall rather than guessing at an app-level bind-address change. Added warning comments to all five noting the lack of built-in auth. Verified both defaults and overrides. Found and separately fixed a pre-existing, unrelated `services.zigbee2mqtt.settings.homeassistant` shape conflict (upstream nixpkgs now expects `homeassistant.enabled = ...`, not a bare boolean) — `homeassistant = false;` → `homeassistant.enabled = false;`; confirmed the full build now succeeds. (`modules/server/{loki,netdata,zigbee2mqtt,kiji-proxy,portbook}.nix`)

- [x] **M-24** `[B]` ~~SMB1 re-enabled globally on every display role~~ — INTENTIONALLY SKIPPED, no code change
  - **Source:** BUGS M27 · `modules/network-desktop.nix:30-33`
  - **Resolution:** User explicitly flagged that SMB network-drive discovery in this repo was hard-won (significant past debugging pain) and is currently working — asked to be extremely careful with any SMB change. Investigated: `"client min protocol" = "NT1"` is a *minimum*, not a forced value — modern SMB2/3 shares are unaffected; it only matters for the one legacy SMB1-only NAS this was added for. Both of the MASTER_PLAN's literal fixes carry real regression risk here: defaulting a new `allowSmb1` option to `false` would break the legacy NAS on next rebuild unless immediately re-enabled, and Samba's client `min protocol` has no true per-remote-host scoping (only a manual fstab `vers=1.0` mount, a materially different workflow from the current automatic Nautilus network browsing). Presented the tradeoff; user chose to leave the setting exactly as-is rather than risk a regression. No files modified.

### Architecture — Medium Impact

- [x] **M-25** `[A]` ~~Three deployment paradigms in `modules/server/` — odysseus compose-in-systemd bypasses service management~~ — RESOLVED BY REMOVAL
  - **Source:** ARCH 1.5
  - **Resolution:** `modules/server/odysseus.nix` (the specific offender — an ad-hoc `preStart` git-clone + docker-compose pattern) was deleted entirely under H-08, per user preference to run it ad-hoc via `docker compose` directly rather than as a declarative module. Confirmed no other file in `modules/server/` uses a compose-in-systemd pattern — the only remaining `docker-compose` reference anywhere is the CLI tool itself in `docker.nix`. No "compose exception rule" needs documenting since no current instance requires one. No files modified.

- [x] **M-26** `[A]` `vexos-update` (240-line shell application) embedded as a Nix string — no shellcheck, wrong module
  - **Source:** ARCH 1.6 · `modules/nix.nix:130-243`
  - **Resolution:** Moved verbatim to `pkgs/vexos-update/default.nix` using `writeShellApplication` (shellchecks at build time); confirmed byte-for-byte content equivalence via a whitespace-normalized diff, which also caught and fixed a heredoc-indentation mistake introduced during the move. Registered as `pkgs.vexos.vexos-update`; `modules/nix.nix` now just references it. Added preflight `[8/8]` that builds the package directly, forcing the shellcheck to run independent of the full per-variant dry-build. (`pkgs/vexos-update/default.nix`, `pkgs/default.nix`, `modules/nix.nix`, `scripts/preflight.sh`)

- [x] **M-27** `[A]` Option B "no lib.mkIf in shared modules" rule violated by the project's own core modules
  - **Source:** ARCH 2.2 · `modules/system.nix:63,73,148,161`, `modules/network.nix:108`, `modules/flatpak.nix:51`, etc.
  - **Resolution:** Verified all 5 cited instances individually — every one gates by a plain option the *same* module declares (bootloader choice, swap/btrfs enable, static-IP config, flatpak master toggle), never by role/display/gaming flag. This is the standard NixOS enable-flag pattern, not the role-smuggling anti-pattern the rule targets. Updated CLAUDE.md's Module Architecture Pattern to explicitly carve this out, rather than removing legitimate, working functionality to satisfy an overly broad rule statement. No `.nix` source files changed. (`CLAUDE.md`)

- [x] **M-28** `[A]` Output/group counts wrong in CLAUDE.md, CI comment, and preflight script
  - **Source:** ARCH 2.3
  - Update CLAUDE.md "30 outputs" → 34; `ci.yml:64-65` "4 groups/22 configs" → 6 groups/34 configs; `preflight.sh:14` "5 configuration-*.nix" → 6; remove `# NEW` markers from `flake.nix:250-259`
  - **Resolution:** Re-verified every sub-claim directly rather than trusting the plan text. `ci.yml`'s group/config counts (6 groups, 30 configs total) were already correct, and no `# NEW` markers exist in `flake.nix` — no changes needed for either. Found the real bugs by direct count: `flake.nix:351` said "34 outputs" while `flake.nix:277` (same file) correctly said "30 outputs" — fixed the contradiction to 30 (confirmed via `hostList` entry count). `CLAUDE.md` said preflight has "7 checks" (actual: 9 stages, `[0/8]`-`[8/8]`, since M-26 added stage 8) — fixed. `CLAUDE.md` also listed a nonexistent `nvidia-legacy470` GPU variant and said "six variants" when only 5 exist (`amd`, `nvidia`, `nvidia-legacy535`, `intel`, `vm`) — removed the phantom variant and corrected the count. `preflight.sh:14` said "5 configuration-*.nix files"; actual is 6 — fixed. (`flake.nix`, `CLAUDE.md`, `scripts/preflight.sh`)

- [x] **M-29** `[A]` Firewall exposure is inconsistent: 18 modules offer an `openFirewall` option, ~35 open ports unconditionally
  - **Source:** ARCH 3.1 · scattered across `modules/server/*`
  - Add `openFirewall ? default true` and a typed `port` option to the ~35 unconditional modules; standardize naming
  - **Resolution:** Re-verified counts directly: 23 of 58 server modules already had `openFirewall`; found 29 true unconditional-exposure modules, of which 28 needed the fix (`syncthing` already conforms via its own correctly-scoped `openGuiFirewall` toggle — left as-is rather than cosmetically renamed). Added `openFirewall` (default `true`, preserves existing behavior) to all 28, gating their firewall port assignment via `lib.optional`/`lib.optionals`. `kavita` and `ntfy` additionally gained a typed `port` option, replacing hardcoded literals. `traefik` and `nextcloud` combine the new toggle with their existing conditional port logic. Validation via `extendModules` caught a real gap: Proxmox's upstream `proxmox-nixos` module manages ports 8006/111/80/443 through its own `services.proxmox-ve.openFirewall` option, independent of this repo's wrapper — threaded `cfg.openFirewall` into it so the toggle now fully suppresses Proxmox's exposure, not just the one port (8007) this repo adds directly. Confirmed via `extendModules` sampling that default behavior (`openFirewall = true`) reproduces the exact pre-change port set, and `openFirewall = false` fully suppresses it, for every sampled module. (28 files under `modules/server/`)

- [ ] **M-30** `[A]` `HEAVY_BUILD_REGEX` defined in three places with two different values — will drift again
  - **Source:** ARCH 3.3, BUGS M16 · `modules/nix.nix:147,194`, `scripts/install.sh:368`
  - Consolidate into one sourced fragment in `scripts/`; remove duplicates

### Features — Medium Value

- [ ] **M-31** `[F]` Finish observability: Loki has no log shipper, Grafana has no dashboards, nothing alerts
  - **Source:** FEATURES 2.3
  - Add `promtail.nix` wired to local Loki; provision Loki datasource + stock dashboards (node-exporter-full, systemd/journal) into Grafana; optional Alertmanager webhook → ntfy (from H-17)

- [ ] **M-32** `[F]` Add qBittorrent + Bazarr opt-in options to the arr stack
  - **Source:** FEATURES 2.4 · `modules/server/arr.nix`
  - Add `vexos.server.arr.qbittorrent.enable` and `vexos.server.arr.bazarr.enable` following the existing one-file-per-service pattern

- [ ] **M-33** `[F]` Caddy LAN reverse-proxy layer — service names and local TLS instead of 40 raw ports
  - **Source:** FEATURES 2.5
  - `modules/server/proxy.nix` with `vexos.server.proxy.enable`; generate `<service>.<hostname>.local` virtualHosts from enabled service port options; Avahi publication

- [ ] **M-34** `[F]` cockpit-zfs NAS Phase B — reserved one-line landing site in `nas.nix`, blocked on upstream packaging
  - **Source:** FEATURES 1.4 · `modules/server/nas.nix:16-19`
  - Re-check 45drives/cockpit-zfs packageability; if buildable: add `pkgs/cockpit-zfs/`, sub-option in `cockpit.nix`, and the reserved `nas.nix` line

- [ ] **M-35** `[F]` `just update-containers` — `:latest` containers never actually update without an explicit pull
  - **Source:** FEATURES 3.1
  - Add just recipe that pulls each enabled OCI service image and restarts the `docker-<name>.service` unit; print before/after digest

- [ ] **M-36** `[F]` CI should build and push `pkgs/*` custom packages to the Attic cache the modules advertise
  - **Source:** FEATURES 4.1 · `modules/nix.nix:25-46`
  - Add CI workflow job: `nix build .#<pkg outputs>`, then `attic push` via repo-secret token

- [ ] **M-37** `[F]` NixOS VM boot test to gate `nixpkgs-unstable` bumps (the manual procedure the README prescribes)
  - **Source:** FEATURES 4.2
  - Add `checks.x86_64-linux.gnome-boot` flake output using `pkgs.nixosTest`; wire into the manual "bump unstable" workflow from H-01

---

## LOW PRIORITY

### Bugs — Minor / Cosmetic

- [ ] **L-01** `[B]` Stale comments contradicting live code (kernel version in vm.nix, Bottles missing, bash-common VS Code path, etc.)
  - **Source:** BUGS L1 · `modules/gpu/vm.nix:5-8`, `modules/gaming.nix:4,70-71`, `home-desktop.nix:21-23`, others
  - Fix kernel comment in vm.nix; add Bottles to flatpak or remove the two claims it's present; fix VS Code comment; fix authorized_keys comment

- [ ] **L-02** `[B]` justfile default recipe claims "vexos" default password and tells user to edit the wrong file
  - **Source:** BUGS L2 · `justfile:22-30`
  - Fix to describe the actual `hashedPassword` / `stateless-user-override.nix` mechanism

- [ ] **L-03** `[B]` VSCode overlay tooling references non-existent `overlays/vscode.nix` — ~120 lines of dead recipes
  - **Source:** BUGS L3 · `justfile:330-348`, `justfile:693-790`
  - Delete the `update-vscode` and version-check recipes (VS Code comes from `pkgs.unstable.vscode-fhs` now)

- [ ] **L-04** `[B]` `secrets-sops.nix` assertions are tautologically true — they assert names the same block declares
  - **Source:** BUGS L4 · `modules/secrets-sops.nix:50-75`
  - Remove the self-referential assertion blocks; only the `sopsFile != null` check does real work

- [ ] **L-05** `[B]` preflight gitleaks hides its own findings via `2>/dev/null` then prints "review output above"
  - **Source:** BUGS L5 · `scripts/preflight.sh:374-380`
  - Remove `2>/dev/null`; cache the `nix flake show --impure` JSON (called twice at lines 83–84)

- [ ] **L-06** `[B]` `stateless-setup.sh` writes the password hash world-readable (0644) and git-adds it
  - **Source:** BUGS L6 · `scripts/stateless-setup.sh:29-32`
  - Change `sudo tee` → `install -m 0600` for `stateless-user-override.nix`

- [ ] **L-07** `[B]` Install scripts fetch moving refs mid-run (disko `latest`, install.sh `main` chain)
  - **Source:** BUGS L7 · `scripts/stateless-setup.sh:191`, `scripts/install.sh:119,126`
  - Pin disko to a tag/rev; pin install.sh curl to a specific release tag

- [ ] **L-08** `[B]` `zfs-server.nix` installs `pkgs.zfs` alongside the module-managed build — potential version skew
  - **Source:** BUGS L8 · `modules/zfs-server.nix:50-55`
  - Use `config.boot.zfs.package` instead of `pkgs.zfs` in `environment.systemPackages`

- [ ] **L-09** `[B]` `gnome-flatpak-install` installs all apps in one transaction — one bad ID fails everything
  - **Source:** BUGS L9 · `modules/gnome-flatpak-install.nix:67-70`
  - Mirror the per-app loop from `modules/flatpak.nix`

- [ ] **L-10** `[B]` `kernel-install-override` timing window: override file deleted in exit-2 path, not restored
  - **Source:** BUGS L10 · `modules/nix.nix:142-165`
  - Move override check to after the lock update, or restore the override file in the exit-2 branch

- [ ] **L-11** `[B]` `programs.git` ships `user.email = ""` — git refuses to commit with an explicit empty value
  - **Source:** BUGS L12 · `home/bash-common.nix:13-16`
  - Remove the `user.email` key entirely

- [ ] **L-12** `[B]` `nvidia-vaapi-driver` incorrectly gated on `latest` only — excludes `legacy_535` users who could use it
  - **Source:** BUGS L16 · `modules/gpu/nvidia.nix:90-93`
  - Gate on `variant != "legacy_470"` instead of `variant == "latest"`

- [ ] **L-13** `[B]` `flatpak-install-apps` exits 0 on failure — `systemctl status` shows green after a 100%-failed install
  - **Source:** BUGS L17 · `modules/flatpak.nix:143-158`
  - Add a `systemd-cat`-visible warning or a marker unit on failure so failures are observable

### Architecture — Low Impact

- [ ] **L-14** `[A]` Stale file-rename residue — three modules reference deleted `performance.nix`; stale file headers
  - **Source:** ARCH 2.4 · `modules/network.nix:3`, `modules/gpu/vm.nix:10`, `modules/branding.nix:5`, `hosts/desktop-amd.nix:1`
  - Update all four references to the correct current filename/path

- [ ] **L-15** `[A]` `distroName` priority arithmetic re-derived at every site — needs a single option with documented precedence
  - **Source:** ARCH 3.4 · `configuration-server.nix`, `configuration-htpc.nix`, `configuration-headless-server.nix`
  - Add `vexos.branding.distroName` with `lib.mkDefault`; remove the `lib.mkOverride 500` workarounds

- [ ] **L-16** `[A]` Empty `overlays/` directory listed as a key directory in CLAUDE.md
  - **Source:** ARCH 4.3
  - Remove the directory and the CLAUDE.md "Key Directories" entry; overlays live inline in `flake.nix` and `pkgs/default.nix`

- [ ] **L-17** `[A]` Expired `TODO(2026-05)` in `plex.nix` — re-check against nixpkgs 25.11
  - **Source:** ARCH 4.4 · `modules/server/plex.nix:43`
  - Verify the upstream Plex module fix; remove the workaround if resolved, or re-date with a new target version

- [ ] **L-18** `[A]` Retired stdout-protocol comment archaeology in `nix.nix` — two generations of dead protocol docs
  - **Source:** ARCH 4.5 · `modules/nix.nix:121-127,185-193`
  - Remove the retired-prefix and retired-three-class-engine comment blocks; git history retains them

- [ ] **L-19** `[A]` `intel-media-driver` shipped in all GPU closures — belongs in `modules/gpu/intel.nix` only
  - **Source:** ARCH 5.2 · `modules/gpu.nix:18`
  - Move to `modules/gpu/intel.nix`; remove from the shared GPU base

- [ ] **L-20** `[A]` Tracked Python bytecode artifact `scripts/__pycache__/` in git
  - **Source:** ARCH 5.3
  - `git rm -r scripts/__pycache__/`; add `__pycache__/` to `.gitignore`

- [ ] **L-21** `[A]` 384 spec/review process docs (4.9 MB) accumulating in `.github/docs/subagent_docs/`
  - **Source:** ARCH 5.4
  - Establish archive policy: keep latest spec per feature; prune superseded `_v2`/`_final` chains

### Features — Low Value / Effort

- [ ] **L-22** `[F]` Headless-server branding assets — spec written, directory is empty, implementation never happened
  - **Source:** FEATURES 3.3 · `wallpapers/headless-server/.gitkeep`
  - Implement `branding_headless_assetrole_clarity_spec.md` or copy server assets; remove `.gitkeep`

- [ ] **L-23** `[F]` Bootable installer ISO flake output (`packages.x86_64-linux.installer-iso`)
  - **Source:** FEATURES 3.2
  - Use `nixos-generators` or `installation-cd-minimal` module wrapping `install.sh` + template; slow iteration, hence LOW-MEDIUM

- [ ] **L-24** `[F]` Surface VexBoard discovery JSON in `just status` / `service-info`
  - **Source:** FEATURES 4.3
  - Point the two just recipes at the VexBoard HTTP endpoint when reachable; keep static tables as fallback; deletes ~150 lines of drift-prone tables

---

## Summary

| Band | Count |
|------|-------|
| HIGH | 19 |
| MEDIUM | 37 |
| LOW | 24 |
| **Total** | **80** |

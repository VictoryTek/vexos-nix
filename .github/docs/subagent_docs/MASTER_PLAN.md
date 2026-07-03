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

- [ ] **H-15** `[F]` Complete the sops-nix "phased migration" — it stalled at 5 secrets; plaintext backend leaks into store (see H-10)
  - **Source:** FEATURES 1.2, ARCH 4.2 · `modules/secrets-sops.nix`, `modules/server/vexboard.nix`
  - Extend `secrets-sops.nix` for remaining services (vexboard, code-server, kiji-proxy, vaultwarden, listmonk, authelia); add `just secrets-init` guided setup recipe; auto-generate VexBoard secret at activation; resolves ARCH 4.2 (sops unreachable by default)

- [ ] **H-16** `[F]` Declarative restic backup module — no backup tooling exists anywhere for 50+ stateful services
  - **Source:** FEATURES 2.1
  - New `modules/server/backup.nix` using `services.restic.backups`; assemble default paths from enabled services (`lib.optionals`); include PostgreSQL pre-hook dump; register in `modules/server/default.nix` and justfile extension points; failure alerts wire into H-17

- [ ] **H-17** `[F]` Wire system events into the self-hosted ntfy server that currently has zero producers
  - **Source:** FEATURES 2.2 · `modules/server/ntfy.nix`
  - New `modules/notify.nix` with `vexos.notify.ntfyUrl` option; `vexos-notify` helper script; parametrised `notify-failure@.service`; one-line hook at end of `vexos-update`

### Architecture — Large Scope

- [ ] **H-18** `[A]` `mkHost` vs `mkBaseModule` share the same `roles` table but re-implement `baseModules` independently — vanilla overlay divergence already present
  - **Source:** ARCH 1.2 · `flake.nix:285-314` vs `:125-170`
  - Refactor `mkBaseModule` to read `roles.<role>.baseModules` directly instead of duplicating the predicate logic; reuse `unstableOverlayModule` (defined at `:56-65`) instead of re-inlining it; fix vanilla variant receiving overlays it is documented not to have

- [ ] **H-19** `[A]` Builder-machine `/etc/nixos` state leaks into flake outputs via `builtins.pathExists` at eval time
  - **Source:** ARCH 1.1 · `flake.nix:89-99`
  - Move `serverServicesModule` and `statelessUserOverrideModule` path-existence checks to the host-side `nixosModules.*Base` consumption path (see `template/etc-nixos-flake.nix`) so evaluation is deterministic regardless of where `nix` runs

- [ ] **H-12b** `[F]` Auto-detect and adopt existing NixOS username at install time
  - **Source:** H-12 design intent — original goal was to adopt the username set during NixOS install
  - On the **migration path** (`migrate-to-stateless.sh`, running on a live system), detect UID 1000 user via `getent passwd 1000 | cut -d: -f1` and write `vexos.user.name = "<detected>";` to the local config. On a **fresh ISO install** there is no prior user to detect, so the default "nimda" remains. Scope: migration script + optional installer prompt.

---

## MEDIUM PRIORITY

### Bugs — Medium Impact

- [ ] **M-01** `[B]` boot-discovery finds at most one ESP — `by-parttype/` is a last-one-wins symlink, not per-partition
  - **Source:** BUGS M1 · `modules/boot-discovery.nix:35`
  - Switch to `by-parttypeuuid/` enumeration or `lsblk -o PATH,PARTTYPE -J`; add `trap` for mount-leak cleanup

- [ ] **M-02** `[B]` Container backend conflict — `podman.nix` and six docker-backed modules all set the same option at priority 100
  - **Source:** BUGS M2 · `modules/server/podman.nix:34`, `modules/server/{dozzle,portainer,homepage,authelia,uptime-kuma,stirling-pdf,nginx-proxy-manager}.nix`
  - Change docker-backed container modules to `lib.mkDefault "docker"`

- [ ] **M-03** `[B]` Unbound on port 5353 collides with Avahi mDNS, which is enabled on every role
  - **Source:** BUGS M3 · `modules/server/unbound.nix:19`
  - Change unbound to port 5335 (conventional unbound-behind-AdGuard port)

- [ ] **M-04** `[B]` headscale `serverUrl = "http://0.0.0.0:<port>"` — clients cannot connect to a bind address
  - **Source:** BUGS M4 · `modules/server/headscale.nix:24`
  - Replace with a required option for the real public URL; verify whether NixOS 25.11 uses `services.headscale.settings.server_url`

- [ ] **M-05** `[B]` `lib.mkDefault [ "btrfs" ]` in initrd discarded by every generated `hardware-configuration.nix`
  - **Source:** BUGS M5 · `modules/stateless-disk.nix:74`
  - Change to plain `[ "btrfs" ]` (list options merge at equal priority; no longer dropped by higher-priority empty list)

- [ ] **M-06** `[B]` Bluetooth codec list omits SBC — SBC-only devices cannot establish A2DP audio
  - **Source:** BUGS M6 · `modules/audio.nix:38`
  - Add `"sbc" "sbc_xq"` to `bluez5.codecs`

- [ ] **M-07** `[B]` `gnome-background-reload` resume service is `wantedBy` targets that this same module masks
  - **Source:** BUGS M7 · `modules/system-nosleep.nix:69-93`
  - Delete the dead resume service block (~25 lines); the masked targets can never activate it

- [ ] **M-08** `[B]` AppArmor wineserver profile attaches to `/usr/bin/wineserver` — that path doesn't exist on NixOS
  - **Source:** BUGS M8 · `modules/gaming.nix:111-124`
  - Change profile path to `/nix/store/*-wine-*/bin/wineserver` glob

- [ ] **M-09** `[B]` `plugdev` group is never created — user membership is a silent no-op
  - **Source:** BUGS M9 · `modules/gaming.nix:103`
  - Add `users.groups.plugdev = {};` or drop the membership in favour of the existing `input` group rule

- [ ] **M-10** `[B]` `elevator=kyber` kernel boot parameter was removed in kernel 5.0 — I/O scheduler not set
  - **Source:** BUGS M10 · `modules/system.nix:91-95`
  - Replace with a udev rule: `ACTION=="add|change", KERNEL=="nvme*|sd*", ATTR{queue/scheduler}="kyber"`

- [ ] **M-11** `[B]` `just reset-defaults` removes wrong stamp name and leaves all GNOME extensions permanently disabled
  - **Source:** BUGS M11 · `justfile:804-820`
  - Change `rm -f` to match all stamp variants with `.dconf-*-initialized*` glob (or explicit list of all current stamp names)

- [ ] **M-12** `[B]` Attic `just enable-attic` help text instructs HS256 token; atticd requires RS256 RSA key
  - **Source:** BUGS M12 · `justfile:1437-1444`
  - Fix help text to match `attic.nix` header: `openssl genrsa -traditional 4096 | base64 -w0` → `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`

- [ ] **M-13** `[B]` All server host variants share the same placeholder ZFS `hostId` — pool-import protection bypassed
  - **Source:** BUGS M15 · `hosts/server-*.nix`, `hosts/headless-server-*.nix`
  - Change to `lib.mkDefault` + assertion that the value differs from the placeholder; document per-machine override in the template path

- [ ] **M-14** `[B]` `vexos-update` deletes the `flake.lock` backup before the step that can still fail
  - **Source:** BUGS M21 · `modules/nix.nix:168-239`
  - Move `flake.lock.bak` removal to after successful `nixos-rebuild switch`; remove `|| true` from dry-build calls so evaluation failures surface

- [ ] **M-15** `[B]` kavita requires a manually created token file with no assertion — enable → permanent crash loop
  - **Source:** BUGS M22 · `modules/server/kavita.nix:22`
  - Add `systemd.tmpfiles` rule to generate the key, or add an assertion + `just enable kavita` prompt (matching code-server's pattern)

- [ ] **M-16** `[B]` `just enable` corrupts `server-services.nix` once the file contains nested braces
  - **Source:** BUGS M23 · `justfile:1330-1334`
  - Anchor substitution to the final `}` line (`$ s|^}|...|`) or append before EOF with awk

- [ ] **M-17** `[B]` Homepage container rejects all requests — `HOMEPAGE_ALLOWED_HOSTS` is unset on v0.10+
  - **Source:** BUGS M24 · `modules/server/homepage.nix:30-38`
  - Add `environment.HOMEPAGE_ALLOWED_HOSTS = "<allowedHost>"` to the container definition

- [ ] **M-18** `[B]` PhotoGIMP launcher ships on desktop but `org.gimp.GIMP` is never installed
  - **Source:** BUGS M17 · `home-desktop.nix:13`, `home/photogimp.nix`
  - Add `org.gimp.GIMP` to the desktop Flatpak install list, or gate `photogimp.enable` on GIMP being present

- [ ] **M-19** `[B]` `just` alias broken on the vanilla role — it points to a justfile that vanilla never deploys
  - **Source:** BUGS M18 · `home/bash-common.nix`, `configuration-vanilla.nix:10-16`
  - Make the alias conditional on the justfile existing, or import `packages-common.nix` in vanilla

- [ ] **M-20** `[B]` SSH password auth + open port 22 + GNOME auto-login on non-server roles with no fail2ban
  - **Source:** BUGS M19 · `modules/network.nix:156-175`, `modules/gnome.nix:126-130`
  - Enable fail2ban on desktop roles, or set `PasswordAuthentication = false`; remove redundant `allowedTCPPorts = [ 22 ]` (openssh `openFirewall` already covers it)

- [ ] **M-21** `[B]` install.sh cache check excludes `linux-[0-9]` from `SOURCE_BUILDS` — kernel compiles bypass the abort rule
  - **Source:** BUGS M16 · `scripts/install.sh:359,401`
  - Remove the `linux-[0-9]` exclusion from the `SOURCE_BUILDS` grep pattern

- [ ] **M-22** `[B]` Seven OCI containers track `:latest` — silently self-updating, non-reproducible, one already broken (M-17)
  - **Source:** BUGS M25, ARCH 3.2 · `portainer.nix`, `homepage.nix`, `stirling-pdf.nix`, `authelia.nix`, `nginx-proxy-manager.nix`, `dockhand.nix`, `dozzle.nix`
  - Pin to version tags (or digests); at minimum pin `authelia` (guards auth) and `nginx-proxy-manager` (terminates TLS) immediately

- [ ] **M-23** `[B]` Several services exposed LAN-wide with no authentication by module design, no opt-out
  - **Source:** BUGS M26 · `loki.nix`, `netdata.nix`, `zigbee2mqtt.nix`, `kiji-proxy.nix`, `portbook.nix`
  - Add `openFirewall ? default true` option; bind `kiji-proxy` to loopback by default; add warning comments

- [ ] **M-24** `[B]` SMB1 re-enabled globally on every display role — affects all SMB connections, not just the legacy NAS
  - **Source:** BUGS M27 · `modules/network-desktop.nix:30-33`
  - Convert to `vexos.network.allowSmb1 = false` opt-in; or scope to the specific NAS via per-server config

### Architecture — Medium Impact

- [ ] **M-25** `[A]` Three deployment paradigms in `modules/server/` — odysseus compose-in-systemd bypasses service management
  - **Source:** ARCH 1.5
  - Convert odysseus `preStart` clone+compose to proper `virtualisation.oci-containers` definition; document compose exception rule for genuinely multi-container topologies

- [ ] **M-26** `[A]` `vexos-update` (240-line shell application) embedded as a Nix string — no shellcheck, wrong module
  - **Source:** ARCH 1.6 · `modules/nix.nix:130-243`
  - Move to `pkgs/vexos-update/` using `writeShellApplication` (shellchecks at build time); add to preflight

- [ ] **M-27** `[A]` Option B "no lib.mkIf in shared modules" rule violated by the project's own core modules
  - **Source:** ARCH 2.2 · `modules/system.nix:63,73,148,161`, `modules/network.nix:108`, `modules/flatpak.nix:51`, etc.
  - Document the legitimate server-module enable-flag pattern as an explicit carve-out; eliminate `lib.mkIf` guards from shared base modules

- [ ] **M-28** `[A]` Output/group counts wrong in CLAUDE.md, CI comment, and preflight script
  - **Source:** ARCH 2.3
  - Update CLAUDE.md "30 outputs" → 34; `ci.yml:64-65` "4 groups/22 configs" → 6 groups/34 configs; `preflight.sh:14` "5 configuration-*.nix" → 6; remove `# NEW` markers from `flake.nix:250-259`

- [ ] **M-29** `[A]` Firewall exposure is inconsistent: 18 modules offer an `openFirewall` option, ~35 open ports unconditionally
  - **Source:** ARCH 3.1 · scattered across `modules/server/*`
  - Add `openFirewall ? default true` and a typed `port` option to the ~35 unconditional modules; standardize naming

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

# vexos-nix — Feature Opportunity Analysis

Date: 2026-06-11
Scope: full read of `flake.nix`, the justfile (all 1,996 lines), all `configuration-*.nix`, `modules/` (including all 57 `modules/server/*` files), `pkgs/`, `scripts/`, `template/`, CI workflows, and the spec/review history in `.github/docs/subagent_docs/`. Git history was used to distinguish "never built" from "built and removed."

This document covers **features worth building** — it deliberately does not repeat the defects in `ANALYSIS_BUGS.md` or the structural debt in `ANALYSIS_ARCH.md`, except where a bug blocks a feature.

Priority = value relative to effort. **HIGH** = large user-facing value, no rearchitecture, mostly existing infrastructure. **MEDIUM** = clear value, moderate effort or an external dependency. **LOW** = nice-to-have or trivial.

---

## 1. Partially built / clearly intended but never finished

### 1.1 HIGH — Re-land btrfs snapshots (snapper): the GUI is still shipped, the backend was removed

**What exists:** Commit `e14009e` added snapper config + `btrfs-assistant` to `modules/system.nix` (spec: `snapper_btrfs_spec.md`, reviews passed). Commit `91dd1e8` ("fix: remove snapper") then deleted the snapper config — but **`btrfs-assistant` is still installed** in the `vexos.btrfs.enable` block (`modules/system.nix:168-171`). btrfs-assistant is primarily a snapper front-end; shipping it without snapper gives users a GUI whose main tab is empty. The removal-era blockers are now solved infrastructure: `vexos.btrfs.enable` exists as a clean gate, and `modules/gpu/vm.nix:30-31` already opts VMs out ("VM btrfs layout is not snapper-compatible").

**Concrete feature:** Inside the existing `lib.mkIf config.vexos.btrfs.enable` block, add `services.snapper.configs.root` (e.g. `/` with `TIMELINE_CREATE`, sensible retention: 5 hourly / 7 daily / 4 weekly) and `services.snapper.snapshotRootOnBoot = false`. Optionally add a `vexos-update` pre-switch snapshot call in `modules/nix.nix` so every update is preceded by a restorable filesystem snapshot — complementing (not replacing) NixOS generations by covering `/etc/nixos`, service state, and user data that generations don't capture. The prior spec and review documents already cover layout pitfalls (`@`/`@home` subvolume naming) — start from those.

**Why now:** the desktop role targets btrfs by default (`vexos.btrfs.enable` defaults on for non-VM), monthly scrub is already configured, and users of an "immutable-feeling" distro expect snapshot rollback of data, not just of the system closure.

### 1.2 HIGH — Finish the sops-nix "phased migration" (it stalled at 5 secrets)

**What exists:** `modules/secrets-sops.nix` implements an encrypted backend (`vexos.secrets.backend = "sops"`) covering exactly five secrets: nextcloud, photoprism, minio (×2), attic. `template/server-services.nix:17` explicitly labels this "phased migration". Meanwhile these remain plaintext-or-manual with no sops path:

- `vexos.server.vexboard.secretFile` (and the module ships a literal `"change-me-set-…"` auth secret as the default — `modules/server/vexboard.nix:56`)
- `vexos.server.code-server.hashedPassword` (set as a plain string in `server-services.nix`)
- `vexos.server.kiji-proxy.environmentFile` (API keys)
- Vaultwarden `ADMIN_TOKEN`, listmonk admin password, authelia secrets

**Concrete feature:** (a) extend `modules/secrets-sops.nix` with optional declarations + `lib.mkForce` wiring for the remaining secret-consuming services, mirroring the existing pattern exactly; (b) add a `just secrets-init` recipe that generates the age key, scaffolds `secrets/server/secrets.yaml` with all required keys, and flips `vexos.secrets.backend = "sops"` in `server-services.nix` — the same guided-setup pattern `just enable proxmox` already uses for IP/NIC prompts; (c) auto-generate the VexBoard secret at activation when unset (one `systemd.tmpfiles`/activation snippet) so the "change-me" placeholder can never reach production.

**Why now:** `ANALYSIS_BUGS.md` H2 shows the plaintext backend leaks `/etc/nixos/secrets/*` into the world-readable Nix store on every rebuild. Completing this migration is the designed escape hatch for that bug.

### 1.3 HIGH — The README-documented unstable-channel update gate does not exist

**What exists:** `README.md` (Updating nixpkgs-unstable section) states: "The daily CI auto-update job intentionally **skips** `nixpkgs-unstable` because GNOME stack updates occasionally introduce regressions that break Wayland session startup on VM guests." But `.github/workflows/update-flake-lock.yml:36` runs plain `nix flake update` — it bumps **every** input daily, including `nixpkgs-unstable`. The documented safety gate was designed but never implemented; the GNOME-regression risk the README warns about is live on every 04:00 UTC run.

**Concrete feature:** Change the workflow step to update named inputs only: `nix flake update nixpkgs home-manager sops-nix impermanence up proxmox-nixos vexboard` (everything except `nixpkgs-unstable`). Then add a second, manually-dispatched (`workflow_dispatch`) job — "bump unstable" — that updates only `nixpkgs-unstable` and runs the eval matrix before committing. This is a ~5-line change that makes the README true. See also 4.2 for the VM boot test that would let the unstable bump become automatic.

### 1.4 MEDIUM — cockpit-zfs (NAS "Phase B"): the deferred plugin has a prepared one-line landing site

**What exists:** The NAS stack was built in explicit phases — Phase A `cockpit-navigator`, Phase C `cockpit-file-sharing`, Phase D `cockpit-identities` + the `vexos.server.nas.enable` umbrella. Phase B (cockpit-zfs) was deferred for a concrete upstream reason: "upstream v1.2.26 uses a Yarn Berry v4 monorepo with unresolved workspace deps … revisit when cockpit-zfs lands in nixpkgs or upstream ships a self-contained lockfile" (`modules/server/cockpit.nix:13-17`). `modules/server/nas.nix:16-19` even reserves the spot: "adding it here is a one-line addition to this file." The supporting cast is complete: `modules/zfs-server.nix`, `scripts/create-zfs-pool.sh`, the `just create-zfs-pool` recipe, and Proxmox ZFS-pool registration guidance.

**Concrete feature:** Re-check packageability (upstream `45drives/cockpit-zfs` releases and nixpkgs both move; the pin predates this analysis). If buildable: add `pkgs/cockpit-zfs/` following the three existing cockpit plugin derivations, a `vexos.server.cockpit.zfs.enable` sub-option in `cockpit.nix` guarded on a ZFS pool being expected, and the reserved line in `nas.nix`. If still blocked: the practical interim is packaging an alternative (e.g. upstream `cockpit-storaged` covers basic disk ops but not ZFS datasets) or documenting `just create-zfs-pool` + `zfs`/`zpool` CLI as the supported path in the `nas` enable-time help text.

**Priority note:** value is high for the NAS use case, but the effort is hostage to upstream packaging — hence MEDIUM.

### 1.5 LOW — CI never evaluates the four newest flake outputs

**What exists:** `flake.nix:250-259` adds `vexos-server-nvidia-legacy535/470` and `vexos-headless-server-nvidia-legacy535/470` (still carrying `# NEW` markers). The CI matrix groups for `server` and `headless-server` (`.github/workflows/ci.yml:94-105`) list only `amd nvidia intel vm` — the four legacy outputs are never evaluated anywhere (desktop/stateless/htpc legacy variants are). A regression in the legacy-NVIDIA path on server roles would ship silently.

**Concrete feature:** add the four config names to their matrix groups. Two lines of YAML; the 20-minute group timeout already accommodates legacy-NVIDIA closures per the comment at `ci.yml:184-185`.

---

## 2. Natural complements to what's already here

### 2.1 HIGH — A declarative backup module (`vexos.server.backup`) — the single biggest gap in the tree

**What exists:** The server roles can run 50+ stateful services — Vaultwarden (passwords), Paperless (documents), Nextcloud, Immich (photos), Forgejo (repos), Home Assistant, PostgreSQL databases — every one writing to `/var/lib/<service>`. There is **no backup tooling anywhere in the repository**: no restic, borg, rclone, sanoid, or even a documented manual procedure (verified by repo-wide grep). NixOS generations protect the system closure, not service data. For a platform whose pitch is "enable a service with one command," data loss on disk failure is the failure mode users will actually hit.

**Concrete feature:** a `modules/server/backup.nix` exposing the same option idiom every other server module uses:

```nix
vexos.server.backup.enable = true;
vexos.server.backup.repository = "/mnt/backup/restic";   # or sftp:/rest: URL
vexos.server.backup.passwordFile = "/etc/nixos/secrets/restic-password";  # sops-wirable (see 1.2)
vexos.server.backup.paths = [ ];   # extras; service paths assembled automatically
```

Implementation rides on `services.restic.backups` (in nixpkgs, systemd-timer based). The module can assemble the default path list from the services that are actually enabled (`lib.optionals config.vexos.server.vaultwarden.enable [ "/var/lib/vaultwarden" ]` etc.), include a `postgresqlDatabases` dump pre-hook for the services backed by Postgres, and register itself in `modules/server/default.nix`, the justfile's `_server_service_names`, `available-services`, and `service-info` — all established extension points. Failure notification hooks into 2.2.

### 2.2 HIGH — Wire system events into the ntfy server that's already shipped (`vexos.notify`)

**What exists:** A self-hosted push-notification server module (`modules/server/ntfy.nix`, port 2586) — and exactly zero producers. Meanwhile the system generates exactly the events push notifications are for: `vexos-update` exits 2 on cache-block and the Up GUI parses its stdout protocol (`modules/nix.nix:117-126`); smartd raises journald-only disk-health alerts (`modules/server/scrutiny.nix`); fail2ban bans; long-running services fail and nobody is watching `systemctl`.

**Concrete feature:** a small `modules/notify.nix`:

```nix
vexos.notify.ntfyUrl = "http://server:2586/vexos-alerts";   # null = disabled
```

providing (a) a `vexos-notify` helper script (`writeShellApplication`, one `curl`); (b) a parametrised `notify-failure@.service` unit plus a default `systemd.services.<name>.onFailure` attachment for the enabled server services; (c) a one-line completion/block ping at the end of `vexos-update`. Each piece is a few lines; the value is converting silent failures into a phone buzz. Desktop roles can point at the same topic over Tailscale (client already enabled on all roles, `modules/network.nix:178`).

### 2.3 MEDIUM — Finish the observability stack: Loki has no log shipper, Grafana has no dashboards, nothing alerts

**What exists:** `grafana.nix` auto-provisions the Prometheus datasource when both are enabled — good pattern, half-applied. The gaps, each acknowledged in the modules' own comments:

- `modules/server/loki.nix:3` says "Ships logs via Promtail or Alloy agents" — **no promtail/alloy module exists**, so an enabled Loki receives nothing and the `just enable loki` help text tells the user to "Use Promtail to ship logs" with no way to do so.
- Grafana provisions zero dashboards; the user lands in an empty UI.
- Prometheus scrapes only `node_exporter`; no Alertmanager, so threshold alerts have nowhere to go.

**Concrete feature:** (a) extend `loki.nix` (or add `promtail.nix`) with `services.promtail` scraping the systemd journal and pre-wired to the local Loki — same `lib.optionalAttrs`-on-peer-enabled pattern grafana.nix already uses; (b) provision the Loki datasource into Grafana when both are enabled; (c) provision two stock dashboards (node-exporter-full, systemd/journal) via `services.grafana.provision.dashboards`; (d) optionally `services.prometheus.alertmanager` with a webhook receiver pointed at ntfy (2.2), completing monitor → alert → phone with zero external dependencies.

### 2.4 MEDIUM — Round out the *arr stack: no torrent client, no subtitle automation

**What exists:** `modules/server/arr.nix` ships SABnzbd + Sonarr + Radarr + Lidarr + Prowlarr — a usenet-only pipeline. Anyone deploying Sonarr/Radarr expects (a) a torrent download client as the alternate/primary path and (b) Bazarr for subtitles; the module even documents the retired-Readarr substitution, showing the stack is meant to be the complete suite.

**Concrete feature:** two opt-in additions in the established one-file-per-service style: `vexos.server.arr.qbittorrent.enable` (via `services.qbittorrent`, web UI on its own port, download dir aligned with the existing group memberships at `arr.nix:39`) and `vexos.server.arr.bazarr.enable` (`services.bazarr` is in nixpkgs). Add the user to the matching groups, register ports in `service-info`/`status`. Effort is an afternoon; it's the same pattern copied twice.

### 2.5 MEDIUM — A reverse-proxy integration layer, so services get names and TLS instead of 40 raw ports

**What exists:** Four reverse-proxy modules (nginx, caddy, traefik, nginx-proxy-manager) — and not one enabled service is wired behind any of them. Every service opens its own numbered port (`service-info` is a wall of `:8078`, `:8234`, `:28981`…), `vaultwarden`'s own help text warns "Put Vaultwarden behind a TLS reverse proxy before exposing outside your local network," and Avahi/mDNS is already running on every host (`modules/network.nix:135`). Every server module already exposes its port as a typed option — exactly the data a proxy generator needs.

**Concrete feature:** `vexos.server.proxy.enable` (Caddy is the natural backend — automatic local CA, simplest config): for each enabled service, generate a `<service>.<hostname>.local` virtual host proxying to `localhost:<port from the existing option>`, published via the existing Avahi instance (CNAME advertisement or `avahi-alias`-style units). `service-info` then prints names instead of port numbers. Scope creep risk is real (auth, external domains) — keep v1 to LAN hostnames + Caddy local TLS and it stays a contained module that only *reads* existing options.

---

## 3. Gaps users of this kind of system would expect filled

### 3.1 MEDIUM — A supported update path for the `:latest` OCI containers

**What exists:** Six services deploy as `virtualisation.oci-containers` with floating tags — `homepage:latest`, `dockhand`, `authelia`, `dozzle`, `uptime-kuma`, `stirling-pdf`, `nginx-proxy-manager` (e.g. `modules/server/homepage.nix:23`). Docker only pulls an image once, so ":latest" actually means "frozen at first-enable forever" — the opposite of what the tag implies, and security updates never arrive. `just update` updates Nix inputs but knows nothing about container images.

**Concrete feature:** a `just update-containers` recipe (server roles) that, for each enabled OCI service, runs `docker/podman pull` on its image and restarts the corresponding `docker-<name>.service` — the unit names are already enumerated in the justfile's `status` recipe table. Print a before/after image digest line. Optionally mention it in `vexos-update` output on server variants. Pinning digests in the modules would be more reproducible but fights upstream `:latest` semantics; the pull-and-restart recipe matches the project's pragmatic justfile style.

### 3.2 LOW-MEDIUM — A bootable installer ISO flake output

**What exists:** The install flow (README "Fresh install", `scripts/install.sh`, `template/etc-nixos-flake.nix`) assumes a generic NixOS is already installed and reachable — two curl-pipes into a working system. The flake already centralises every role/GPU permutation in `hostList`, and `scripts/stateless-setup.sh` + `template/stateless-disko.nix` show disk provisioning is in scope for the project.

**Concrete feature:** a `packages.x86_64-linux.installer-iso` output building a minimal NixOS live ISO (via `nixos-generators` or the stock `installation-cd-minimal` module) that bundles `scripts/install.sh`, the template flake, `just`, and a first-boot autorun prompt. This collapses "install NixOS, then convert it" into "boot USB, pick role/GPU." No rearchitecture — it is one more flake output consuming the existing scripts — but ISO build/test iteration is slow, hence the priority.

### 3.3 LOW — Headless-server branding assets are an empty directory

**What exists:** `wallpapers/headless-server/` contains only `.gitkeep`; every other role has dark/light wallpapers, `files/background_logos/<role>/`, pixmaps, and a Plymouth watermark. A spec exists with no review or implementation (`branding_headless_assetrole_clarity_spec.md`) — intent was recorded, work never happened. Impact is limited (headless = no display), but the asset-resolution code paths still look these up, and the console/Plymouth identity on a directly-attached monitor falls back inconsistently.

**Concrete feature:** either implement the recorded spec (explicit asset-role mapping for headless → server assets, removing the empty dir) or copy the server assets in. One sitting.

---

## 4. Integrations the structure is already set up for but not using

### 4.1 MEDIUM — CI should build and push `pkgs/*` to the Attic cache the modules already advertise

**What exists:** Two halves of a binary-cache story, never joined: the server side (`modules/server/attic.nix` runs `atticd`) and the client side (`vexos.attic.cacheUrl`/`publicKey` options in `modules/nix.nix:25-46`, whose comment promises "every host fetches pre-built custom packages (portbook, cockpit-navigator, cockpit-file-sharing, etc.) instead of rebuilding them locally"). Nothing populates the cache — no CI push, no post-build hook — so the promise only holds if the operator pushes by hand. There is even a `garnix_cache_migration` spec in the docs history showing cache automation has been on the roadmap.

**Concrete feature:** a CI job (separate workflow or post-eval step) that runs `nix build .#<custom packages>` for the `pkgs/` overlay outputs and pushes the results with `attic push` using a repository-secret token to the operator's reachable cache endpoint (or, if the homelab cache isn't internet-reachable, the same job targeting Cachix/Garnix as the public tier). Custom packages change rarely, so cache hits make the job nearly free after the first run.

### 4.2 MEDIUM — Automated VM boot test for GNOME regressions (the manual procedure in the README, mechanised)

**What exists:** The README prescribes a *manual* regression test before every `nixpkgs-unstable` bump: build a VM variant, boot it, confirm GDM starts, "a black screen means the new nixpkgs-unstable has a GNOME regression." The flake already has dedicated VM variants (`vexos-desktop-vm` etc.) and CI already evaluates them; the only missing piece is actually booting one. The NixOS test framework (`pkgs.nixosTest` / `testers.runNixOSTest`) does exactly this on a headless runner: boot the system in QEMU and assert on units.

**Concrete feature:** a `checks.x86_64-linux.gnome-boot` flake output wrapping a trimmed desktop-vm profile in a NixOS test that waits for `graphical.target` and `gdm.service` active (`machine.wait_for_unit("display-manager.service")`). Run it only in the manual "bump unstable" workflow from 1.3 — not in the per-push matrix (KVM-on-Actions is slow but functional with `kvm` group runners; allow ~10-15 min). Together, 1.3 + 4.2 turn the README's hand-run safety procedure into an automated gate, which is precisely the failure (VM black screens after unstable bumps) the project's own docs say recurs.

### 4.3 LOW — Surface VexBoard discovery data in `just`

**What exists:** VexBoard (auto-enabled with the first service) already runs systemd + Docker discovery every 60 s with a curated exclude list (`modules/server/vexboard.nix:59-114`) and probes service health. Separately, the justfile maintains a *hand-written* parallel universe of the same facts: the unit-name table in `status`, the port table in `service-info` — both of which drift (they already disagree with module defaults in places).

**Concrete feature:** if/when VexBoard exposes its discovery as JSON over HTTP (it already pushes metrics every 2 s), point `just status`/`service-info` at that endpoint with the static tables as fallback. This is listed LOW because it depends on the external VexBoard project's API surface — but it is the designed consumer relationship between the two components, and it would delete ~150 lines of drift-prone justfile tables.

---

## Summary table

| # | Feature | Category | Priority |
|---|---------|----------|----------|
| 2.1 | Declarative restic backup module for service state | complement | **HIGH** |
| 1.1 | Re-land snapper btrfs snapshots (btrfs-assistant is stranded) | unfinished | **HIGH** |
| 1.2 | Complete sops-nix migration + `just secrets-init` | unfinished | **HIGH** |
| 1.3 | Make the daily auto-update skip `nixpkgs-unstable` (as documented) | unfinished | **HIGH** |
| 2.2 | `vexos.notify` — wire smartd/unit-failures/vexos-update into ntfy | complement | **HIGH** |
| 2.3 | Promtail shipper, Grafana dashboards, Alertmanager→ntfy | complement | MEDIUM |
| 2.4 | qBittorrent + Bazarr options in the arr stack | complement | MEDIUM |
| 2.5 | Caddy-based LAN reverse-proxy layer (names + TLS, not raw ports) | complement | MEDIUM |
| 1.4 | cockpit-zfs (NAS Phase B) — pending upstream packageability | unfinished | MEDIUM |
| 3.1 | `just update-containers` for the `:latest` OCI services | gap | MEDIUM |
| 4.1 | CI builds + pushes `pkgs/*` to Attic cache | integration | MEDIUM |
| 4.2 | NixOS VM boot test gating `nixpkgs-unstable` bumps | integration | MEDIUM |
| 3.2 | Bootable installer ISO flake output | gap | LOW-MEDIUM |
| 1.5 | Add server/headless legacy-NVIDIA outputs to CI matrix | unfinished | LOW |
| 3.3 | Headless-server branding assets (spec exists, unimplemented) | unfinished | LOW |
| 4.3 | Drive `just status`/`service-info` from VexBoard discovery | integration | LOW |

**Suggested sequencing:** 1.3 and 1.5 are sub-hour fixes — do them first. Then 2.1 (backups) and 2.2 (notifications) as a pair, since backup-failure alerting is the natural first notify consumer. 1.1 and 1.2 next; both have prior specs/reviews in `.github/docs/subagent_docs/` to build from. Note that 1.2 is also the remediation path for `ANALYSIS_BUGS.md` H2, and the multi-user enabler (`vexos.user.name`, spec `user_name_refactor_spec.md`) is tracked there as bug H1 rather than re-listed here.

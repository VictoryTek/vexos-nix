# vexos-nix — Bug & Code Quality Analysis

Date: 2026-06-10
Scope: every tracked `.nix` file, all shell scripts, the justfile, templates, and CI workflow (~11,700 lines). Analysis is read-only; no builds were run. Findings marked **[verified]** were cross-checked against documentation, upstream sources, or the local system; findings marked **[verify]** are high-confidence but should be confirmed with a dry-build or runtime test.

Priorities: **HIGH** = broken functionality, data/security risk, or violated project invariant. **MEDIUM** = real defect with limited blast radius, or significant silent misbehavior. **LOW** = dead code, stale comments, minor inefficiency.

---

## HIGH

### H1. `vexos.user.name` option is a lie — the user account is hardcoded to `nimda`
**Files:** `modules/users.nix:25`, consumers at `modules/gaming.nix:103`, `modules/development.nix:14`, `modules/audio.nix` (last line), `modules/virtualization.nix:38`, `modules/network.nix:172`, `configuration-stateless.nix:40`, `modules/gnome.nix:129`, `flake.nix:180`, and ~15 other `users.users.${config.vexos.user.name}` references.

`modules/users.nix` declares `vexos.user.name` with the description "override per-host if needed", but the actual account is defined as `users.users.nimda = { isNormalUser = true; ... }` — not `users.users.${cfg.name}`. If any host sets `vexos.user.name = "alice"`:

- Every module that does `users.users.${config.vexos.user.name}.extraGroups = [...]` creates a *second* user entry `users.users.alice` that has groups/SSH keys/password but **no `isNormalUser`/`isSystemUser`**, which fails NixOS's "exactly one of isNormalUser or isSystemUser must be set" assertion — or, in the stateless role, attaches the login password to a user that doesn't exist.
- home-manager (`flake.nix:180`) manages `/home/alice` while the real login account remains `nimda`.
- `description = cfg.name` sets the GECOS field to the username — cosmetic evidence the wiring was intended to be dynamic.

Either make the account `users.users.${cfg.name}` or remove the option's "override per-host" claim and document it as fixed. Related hardcodes that would also need fixing: `chown 1000:1000` in `modules/gnome-stateless.nix` (activation script), `getent shadow nimda` in `scripts/migrate-to-stateless.sh:314`, `users.users.nimda` in both setup scripts and the CI fixture.

### H2. Plaintext secrets are copied into the world-readable Nix store by every `just rebuild` / `vexos-update`
**Files:** `justfile:1988-1995` (`rebuild`), `justfile:367-393` (`update-all`), `justfile:395-408` (`deploy`), `modules/nix.nix:128-240` (`vexos-update` uses `--flake path:/etc/nixos`), combined with the secrets convention in `modules/secrets.nix` and `modules/server/{nextcloud,minio,photoprism,attic}.nix`.

The documented plaintext-secrets workflow stores credentials in `/etc/nixos/secrets/*` (0700 dir, 0600 files). All rebuild paths use the **`path:/etc/nixos`** flake URI. The `path:` fetcher copies the *entire directory tree* into `/nix/store` — including `secrets/` — and everything in the store is world-readable. Run as root (sudo), the copy succeeds despite the 0600 permissions. Net effect: on any server using the plaintext backend, every rebuild publishes the Nextcloud admin password, MinIO root credentials, PhotoPrism password, and Attic signing secret to every local user (and to any configured binary-cache push target).

Mitigations: move secrets outside the flake root (e.g. `/var/lib/vexos/secrets`), or rely on the git-tracked `git+file:` identity (the installer git-inits `/etc/nixos` precisely so untracked files are excluded — `scripts/stateless-setup.sh:225-233`) instead of forcing `path:`. Note `stateless-setup.sh` also runs `git add .` after writing `stateless-user-override.nix`, so the password hash lands in the git index *and* the store.

### H3. `vexos.network.staticWired` writes an invalid NetworkManager keyfile — static IP never applies **[verified]**
**File:** `modules/network.nix:116-121`.

The profile is rendered as an NM keyfile via `networking.networkmanager.ensureProfiles`. Per `nm-settings-keyfile(5)` (checked on this machine), static IPv4 addresses must be written as `address1=...`, `address2=...` — the plural property name `addresses` is **not** a valid keyfile key. The generated `[ipv4]` section is:

```ini
method=manual
addresses=192.168.1.10/24   # unknown key — ignored
gateway=192.168.1.1
```

`method=manual` with zero addresses fails NM's connection verification, so the whole `wired-static` profile is rejected and the host silently falls back to the DHCP `wired-fallback` profile. Fix: emit `address1 = "${cfg.address},${cfg.gateway}"` (or `address1` + the separate `gateway` key, which *is* valid).

### H4. Template flake is missing the NVIDIA legacy outputs that the installer and docs sell
**Files:** `template/etc-nixos-flake.nix` (outputs block, ~lines 300-360) vs. its own header comment (lines 15-60), and `scripts/install.sh:160-184,201`.

The template's header instructs users to run `nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy535` (and -legacy470, for all five roles), and `install.sh` constructs `FLAKE_TARGET="vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"` with those suffixes. But the template's `nixosConfigurations` defines **only** `amd/nvidia/intel/vm` per role — no `-legacy535`/`-legacy470` outputs exist, and the template never sets `vexos.gpu.nvidiaDriverVariant`. Any user who selects "Legacy 535" or "Legacy 470" in the installer gets `error: flake ... does not provide attribute 'nixosConfigurations.vexos-desktop-nvidia-legacy535'` after disk/boot patching has already happened. The legacy outputs only exist in the repo's own `flake.nix`.

### H5. `just version-upgrade` rewrites `system.stateVersion` — violating the project's own hard invariant
**File:** `justfile:646-652`.

```bash
sed -i "s|system\.stateVersion = \"${CURRENT}\"|system.stateVersion = \"${NEW_VERSION}\"|g" "$cfg"
```

CLAUDE.md, every `configuration-*.nix` comment ("Do NOT change this after initial install"), and the preflight script all treat `stateVersion` as immutable, yet the upgrade recipe bumps it in all six configuration files as step 3 of a version upgrade. Changing `stateVersion` on a live system silently changes stateful defaults (PostgreSQL major version selection for Nextcloud/listmonk, service data layouts, etc.) and can orphan or corrupt existing databases. Steps 1–2 (input URL bumps) are correct; step 3 should be deleted.

### H6. install.sh NVIDIA-branch prompt accepts garbage and silently selects "latest"
**File:** `scripts/install.sh:171-183`.

```bash
while [ -z "$NVIDIA_SUFFIX" ]; do
  read -r INPUT </dev/tty
  case "${INPUT}" in
    1) NVIDIA_SUFFIX="" ;;
    2) NVIDIA_SUFFIX="-legacy535" ;;
    3) NVIDIA_SUFFIX="-legacy470" ;;
    *) echo "Invalid selection..." ;;
  esac
  [[ -n "${INPUT}" ]] && break    # ← breaks on ANY non-empty input
done
```

The final `break` fires for *any* non-empty input, including invalid ones ("4", "x"), immediately after printing "Invalid selection" — so an invalid answer falls through as "latest". On a Kepler GPU this installs a driver that cannot drive the card. The `[[ -n "$INPUT" ]] && break` line should be removed (option 1 already exits the loop correctly because... actually it doesn't: choosing "1" sets `NVIDIA_SUFFIX=""`, which keeps the `while [ -z ... ]` condition true — the stray `break` exists to compensate. The loop needs a separate "answered" flag, like the `just update` recipe at `justfile:302-318` already does correctly).

### H7. migrate-to-stateless.sh always crashes at the end: `$CUSTOM_PASSWORD_SET` is never set
**File:** `scripts/migrate-to-stateless.sh:420` (with `set -euo pipefail` at line 29).

`if $CUSTOM_PASSWORD_SET; then` references a variable that is never assigned anywhere in the script. Under `set -u` this aborts with `CUSTOM_PASSWORD_SET: unbound variable` *after* the migration work completes — exiting non-zero, skipping the credentials summary and the reboot prompt, and making a successful migration look like a failure. The surrounding message is also wrong: the "else" branch claims `Password: vexos (default — no existing hash found)`, but there is no "vexos" default password anywhere in the codebase — the no-hash path interactively *requires* a new password (lines 320-345). The variable should be derived from which branch ran at lines 316-345.

### H8. fail2ban `cockpit` jail references a filter that doesn't exist — on every server build **[verified]**
**File:** `modules/security-server.nix:74-79`.

```nix
jails.cockpit = ''
  enabled  = true
  filter   = cockpit
  ...
'';
```

Upstream fail2ban ships no `filter.d/cockpit.conf` (verified against the fail2ban MANIFEST: 111 filter.d entries, none named cockpit), and nothing in this repo or the NixOS module provides one. fail2ban refuses to start a jail whose filter cannot be found, logging `Unable to read the filter 'cockpit'`; depending on fail2ban version this either errors the whole `fail2ban.service` start or silently drops the jail. Since this module is imported unconditionally by both server roles (not gated on cockpit being enabled), every server host carries a broken jail. Fix: ship a filter via `environment.etc."fail2ban/filter.d/cockpit.local"` (cockpit logs auth failures to the journal as `pam_unix(cockpit:auth): authentication failure`) or drop the jail.

---

## MEDIUM

### M1. boot-discovery can only ever see one foreign ESP — `/dev/disk/by-parttype/` symlinks are last-one-wins
**File:** `modules/boot-discovery.nix:35`.

`for esp_link in /dev/disk/by-parttype/${ESP_PARTTYPE}*` assumes udev creates one symlink per ESP partition. It doesn't: `by-parttype/<GUID>` is a single symlink name shared by every partition with that type GUID, and udev link-priority means it points at exactly *one* arbitrary winner. With 3 drives each carrying an ESP, the loop visits at most one — which may even be the primary ESP (then skipped), making the whole service a no-op. Use `/dev/disk/by-parttypeuuid/` (parttype+partuuid, unique per partition) or enumerate with `lsblk -o PATH,PARTTYPE -J` instead. Additionally, if the script dies between `mount` and `umount` (`set -e`), the temp mount leaks — a `trap` cleanup is missing.

### M2. Container-runtime backend conflict between podman and the six docker-backed container modules
**Files:** `modules/server/podman.nix:34` (`virtualisation.oci-containers.backend = "podman"`) vs. `modules/server/{dozzle.nix,portainer.nix,homepage.nix,authelia.nix,uptime-kuma.nix,stirling-pdf.nix,nginx-proxy-manager.nix}` (each sets `virtualisation.oci-containers.backend = "docker"`, plain assignment).

Both sides define the same single-value enum option at priority 100. Enabling `podman` (required by `dockhand`) together with *any* of the docker-backed container services makes evaluation fail with a definition conflict. The podman assertion only guards against `vexos.server.docker.enable`, not against these modules — so `just enable dockhand` followed by `just enable dozzle` produces a config that can't build. The docker-backed modules should use `lib.mkDefault "docker"` (and ideally an assertion explaining the incompatibility), or be taught to run under the podman backend.

### M3. Unbound on port 5353 collides with Avahi mDNS, which is enabled on every role
**Files:** `modules/server/unbound.nix:19` (chosen "to avoid conflict with AdGuard Home"), `modules/network.nix:135-148` (Avahi enabled + `openFirewall` = UDP 5353 open on all roles).

UDP 5353 is the mDNS port. Avahi binds `*:5353` on every vexos host; an Unbound instance binding `0.0.0.0:5353` on the same machine either fails to start (`EADDRINUSE`) or — if both happen to set `SO_REUSEADDR` — silently steals an unpredictable fraction of unicast datagrams from Avahi. The firewall rules at lines 32-33 also open the mDNS port to arbitrary unicast DNS. Pick any non-mDNS port (5335 is the conventional choice for unbound-behind-AdGuard).

### M4. headscale `serverUrl = "http://0.0.0.0:<port>"` is not a usable server URL **[verify option name too]**
**File:** `modules/server/headscale.nix:24`.

`server_url` is the URL handed to every Tailscale client to reach the control plane; `0.0.0.0` is a bind address, not a reachable host — clients literally try to connect to `http://0.0.0.0:8085` and fail. It must be the host's real name/IP (and realistically `https://`). Also confirm `services.headscale.serverUrl` still exists in NixOS 25.11 — recent module versions moved this to `services.headscale.settings.server_url`; if renamed, enabling this module fails evaluation outright. Since the module has a `settings` block two lines below, setting `settings.server_url` there (from a required option, with an assertion like proxmox's `ipAddress`) is the right shape.

### M5. `boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ]` is discarded by every generated hardware-configuration.nix
**File:** `modules/stateless-disk.nix:74`.

The comment says "Force unconditional early loading of btrfs", but `nixos-generate-config` always emits `boot.initrd.kernelModules = [ ];` (plain assignment, priority 100). With a higher-priority definition present, the `mkDefault` (priority 1000) list is **not merged — it is dropped entirely**, so btrfs is not force-loaded in initrd on exactly the machines this module targets (those with a generated hardware config). If early loading matters, this must not be `mkDefault` (list options merge across equal priorities; a plain `[ "btrfs" ]` merges fine with the generated empty list).

### M6. Bluetooth codec list omits SBC — SBC-only devices lose A2DP, and `enable-sbc-xq` contradicts it
**File:** `modules/audio.nix:38` (`"bluez5.codecs" = [ "aac" "ldac" "aptx" "aptx_hd" ]`).

Setting `bluez5.codecs` is a *whitelist*: codecs not listed are disabled. SBC is the mandatory baseline codec every A2DP device supports and the only codec many budget headsets have — with this list they can pair but get no A2DP audio (HFP fallback at phone-call quality). Meanwhile line 36 sets `bluez5.enable-sbc-xq = true`, which is meaningless when SBC itself is excluded. Add `"sbc" "sbc_xq"` to the list (or drop the `codecs` key entirely and keep the enable flags).

### M7. `gnome-background-reload` resume service is dead code — it's wanted by targets this same module masks
**File:** `modules/system-nosleep.nix:69-93** vs. lines 8-14.

The service is `wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ]`, but the module's "Layer 4" puts those exact units in `systemd.suppressedSystemUnits`, masking them to `/dev/null`. A masked target can never be activated, so its `wantedBy` edges never fire. The ~25 lines (plus the per-user DBus plumbing) can be deleted, or the module split if some roles are ever allowed to sleep.

### M8. AppArmor wineserver profile matches a path that cannot exist on NixOS
**File:** `modules/gaming.nix:111-124`.

The profile is attached to `/usr/bin/wineserver`. On NixOS, wine binaries live at `/nix/store/<hash>-wine-.../bin/wineserver`; `/usr/bin` contains only `env`. The profile therefore never attaches to any process — the stated audit-logging goal is silently unmet while reading as if Wine is being monitored. Profile path needs to be the store glob (e.g. `/nix/store/*-wine-*/bin/wineserver`) or attached via `security.apparmor.policies` with the actual package path. The comment's premise ("installs setuid wrappers") is also wrong for nixpkgs wine.

### M9. `plugdev` group is never created — membership is a silent no-op **[verified: no `users.groups.plugdev` anywhere in the repo]**
**File:** `modules/gaming.nix:103`.

NixOS does not define a `plugdev` group by default and no module here creates one; NixOS only emits a build *warning* for unknown groups, so the user simply never gets the membership the udev comment block assumes. Either add `users.groups.plugdev = {};` or drop it (the generic `SUBSYSTEM=="input" ... GROUP="input"` rule plus the `input` group already covers the listed devices).

### M10. `elevator=kyber` kernel parameter does nothing on any kernel this repo ships
**File:** `modules/system.nix:91-95`.

The `elevator=` boot parameter was removed from the kernel in 5.0 (legacy block layer removal); on the 6.6/6.12/6.18 kernels pinned here it is parsed as an unknown parameter and ignored — Kyber is *not* being selected. The correct mechanism is a udev rule (`ACTION=="add|change", KERNEL=="nvme*|sd*", ATTR{queue/scheduler}="kyber"`). As written, every host silently runs the default scheduler while the config claims otherwise.

### M11. `just reset-defaults` leaves desktop app folders and *all* GNOME extensions permanently unrestored
**File:** `justfile:804-820** vs. `home-desktop.nix:174-243` and `home-stateless.nix`.

The recipe runs `dconf reset -f /` then removes only `.dconf-app-folders-initialized-v2`. The desktop role's stamp is `...-initialized-v3` (`home-desktop.nix:175`), so on desktop the one-shot folder service never re-runs. Worse, neither role's `.dconf-extensions-initialized` stamp is removed, so after the wipe `enabled-extensions` stays at GNOME's empty first-run value and **every shell extension (dock, appindicator, etc.) remains disabled forever** until the user manually deletes the stamp. The recipe needs `rm -f` for all stamp variants (or a glob: `.dconf-*-initialized*`).

### M12. justfile's Attic instructions configure the wrong token algorithm — service won't start if followed
**File:** `justfile:1437-1444** (enable-attic help text) vs. `modules/server/attic.nix:6-9`.

The justfile tells the operator to create the credentials file with `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=<secret>` generated by `openssl rand -base64 32`. The module (and atticd at this pin) requires `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` containing a base64-encoded RSA key (`openssl genrsa -traditional 4096 | base64 -w0`, as attic.nix's header correctly says). Following the just output yields an env file atticd rejects → start failure with no hint that the just docs were the source.

### M13. VexBoard ships with a known hardcoded auth secret and the firewall open by default
**File:** `modules/server/vexboard.nix:50-58** (`secret = "change-me-set-vexos.server.vexboard.secretFile"`, `openFirewall` default `true`).

If the operator never sets `secretFile` (nothing forces them to — no assertion, and `just enable <anything>` auto-enables vexboard), the dashboard runs with a session-signing secret that is identical on every VexOS install and published in this repo. Anyone on the LAN can mint valid sessions. Add an assertion requiring `secretFile != null` (mirroring code-server's hashedPassword assertion), or at minimum default `openFirewall = false` until a secret is provided.

### M14. Odysseus module executes unpinned third-party code as root at service start
**File:** `modules/server/odysseus.nix:96-104** (preStart `git clone --depth 1 https://github.com/pewdiepie-archdaemon/odysseus.git`), plus `chromadb/chroma:latest`.

The service clones whatever the repo's default branch points to at first boot and `docker-compose up --build`s it — arbitrary remote code, root-controlled socket, no commit pin, no checksum. A compromised or force-pushed upstream becomes root-adjacent code on the server. Existing clones are also never updated (the `if [ ! -d src/.git ]` guard), so behavior depends on first-enable date. Pin a commit (`git clone` + `git checkout <sha>`) or package it like portbook/kiji-proxy with a fixed hash.

### M15. Every machine built from `hosts/server-*.nix` / `hosts/headless-server-*.nix` shares the same ZFS hostId
**Files:** `hosts/server-amd.nix:15` ("a0000001"), and the other 7 (`a0000002..4`, `b0000001..4`).

`networking.hostId` must be unique per *machine*, but these are per-*variant* files shared by every deployment of that variant. The placeholder values pass the `!= "00000000"` assertion in `modules/zfs-server.nix:69-79`, defeating its purpose: two `vexos-server-amd` machines importing each other's pools (or a pool moved between them) will not get the import-protection hostId is for. The "REQUIRED: replace with the real value" comment can't work in a shared file. The template-flake path does this correctly (per-machine `hostModule` + installer substitution); the repo host files should use a weaker mechanism (e.g. `lib.mkDefault` + assertion that it was overridden) or read a host-local file.

### M16. install.sh cache check exempts full kernel compiles from the "abort on source builds" rule
**File:** `scripts/install.sh:359,401` (exclusion regex contains `|linux-[0-9]|kernel|`).

The giant `grep -Ev` excludes any derivation starting with `linux-<digit>` or `kernel` from `SOURCE_BUILDS` on the theory that these are "config-assembly derivations that complete in milliseconds" — but `linux-6.18.x` *is* the multi-hour kernel build, the single heaviest thing the check exists to prevent. A cache-missing kernel sails through to `nixos-rebuild switch` and compiles for hours on the live ISO. (The fallback logic at lines 362-422 only handles NVIDIA/openrazer misses.) The same 600-character regex is duplicated verbatim at lines 359 and 401 and a third near-copy lives in `modules/nix.nix:147,194` — three divergence-prone copies of load-bearing logic.

### M17. PhotoGIMP is enabled on desktop, but nothing installs GIMP
**Files:** `home-desktop.nix:13` (`photogimp.enable = true`), `home/photogimp.nix` (desktop entry `Exec=flatpak run org.gimp.GIMP`); `org.gimp.GIMP` appears in no install list (`modules/flatpak.nix` defaultApps, `modules/flatpak-desktop.nix`, `vexos.gnome.flatpakInstall.apps` — verified by grep; it appears only in *exclude* lists for other roles).

The desktop role ships a "PhotoGIMP" launcher, icons, and `~/.config/GIMP/3.0` payload pointing at a Flatpak that is never installed. Result: a dead app-grid entry that silently does nothing when clicked, unless the user manually installs GIMP. Either add `org.gimp.GIMP` to the desktop Flatpak list or gate `photogimp.enable` on it.

### M18. `just` alias is broken on the vanilla role
**Files:** `home/bash-common.nix` (alias `just = "just --justfile /etc/nixos/justfile ..."`), `modules/packages-common.nix:6` (deploys `/etc/nixos/justfile`), `configuration-vanilla.nix:10-16` (does **not** import packages-common.nix).

`home-vanilla.nix` imports `bash-common.nix` (alias active, and it shadows the real binary for all invocations) and installs the `just` package, but vanilla never deploys `/etc/nixos/justfile` — so every `just ...` command on vanilla fails with "No justfile found at /etc/nixos/justfile". Either import packages-common on vanilla or make the alias conditional.

### M19. SSH password authentication + open port 22 + GNOME auto-login on every role
**Files:** `modules/network.nix:156-175` (sshd enabled, `PasswordAuthentication` left enabled, port 22 opened on all roles), `modules/gnome.nix:126-130` (autoLogin), `modules/gnome.nix:90-93` (screen lock disabled), `authorized_keys` (empty), fail2ban only on server roles (`modules/security-server.nix`).

Individually documented choices, but combined: every desktop/HTPC/stateless machine accepts password-guessing on SSH with no fail2ban, while the console session is auto-logged-in with locking disabled. The stateless role makes it sharper: its password is whatever was typed at install into `stateless-user-override.nix`. At minimum, enable fail2ban (or `services.openssh.settings.PasswordAuthentication = false` once keys are present) on non-server roles too, or stop opening 22 by default on desktop-class roles. Also: `networking.firewall.allowedTCPPorts = [ 22 ]` at line 175 is redundant — `services.openssh.openFirewall` already defaults to true.

### M20. CI never evaluates 4 of the 34 flake outputs
**File:** `.github/workflows/ci.yml:96-105` vs. `flake.nix:250-259`.

`vexos-server-nvidia-legacy535/470` and `vexos-headless-server-nvidia-legacy535/470` (marked `# NEW` in hostList) are absent from the CI matrix (server and headless-server groups list only amd/nvidia/intel/vm). Given the local policy that full multi-variant validation is "delegated to GitHub Actions CI", these four targets are validated nowhere. (The matrix comment also still says "4 groups" with 6 defined.)

### M21. `vexos-update` deletes its flake.lock backup before the step that can still fail, and swallows dry-build evaluation errors
**File:** `modules/nix.nix:168-239`.

- `flake.lock.bak` is removed (line 235) *before* `nixos-rebuild switch` runs; if the switch fails (eval error introduced by the input bump, build failure of a non-"heavy" package), the lock stays bumped with no restore path, so the documented contract "exit 1 ... system unchanged" doesn't hold for this branch.
- Both `nixos-rebuild dry-build ... || true` calls (lines 146, 175-176) swallow evaluation failures; an update that breaks evaluation produces empty `ALL_LOCAL`, passes the heavy-build gate, and only explodes at the final switch — after the backup was deleted.

### M22. kavita requires a manually created token file with no assertion — enable → crash loop
**File:** `modules/server/kavita.nix:22` (`tokenKeyFile = "/var/lib/kavita/token-key"` with only a comment saying it "Must exist").

`just enable kavita && just rebuild` yields a kavita.service that fails on start until the operator reads the .nix source. Every comparable foot-gun in this repo (code-server password, proxmox IP, vaultwarden domain, papermc EULA) is guarded by an assertion or a just-prompt; kavita should get one too (or a `systemd.tmpfiles`/preStart that generates the key, which is what most distros do).

### M23. justfile `enable` corrupts `server-services.nix` once the file contains any nested braces
**File:** `justfile:1330-1334` (`sudo sed -i "s|}|  ${OPTION} = true;\n}|" "$SVC_FILE"`).

The fallback insertion substitutes on *every line containing `}`*, not "the closing brace". The shipped template has exactly one `}` (verified), so it works until an operator adds anything brace-bearing (an inline attrset like `services.caddy.virtualHosts."x" = { ... };`, which the caddy module comment explicitly suggests putting in this file). After that, each `just enable` inserts the option after *every* `}` line → duplicate attribute definitions → evaluation error. Anchor the sed to the final line (`$ s|^}|...|`) or append before EOF with awk.

### M24. Homepage container will reject requests in current images — missing `HOMEPAGE_ALLOWED_HOSTS` **[verify]**
**File:** `modules/server/homepage.nix:30-38`.

`ghcr.io/gethomepage/homepage:latest` (v0.10+) refuses requests whose Host header isn't in `HOMEPAGE_ALLOWED_HOSTS` ("Host validation failed"). The container sets no environment at all, and `:latest` guarantees the breaking change is picked up. Accessing `http://<server-ip>:3010` returns an error page. Needs `environment.HOMEPAGE_ALLOWED_HOSTS = "<host>:${port}"` (or `*` for LAN use) — and see M25 about `:latest`.

### M25. Seven OCI containers track `:latest` — unpinned, non-reproducible, silently self-updating
**Files:** `modules/server/dockhand.nix` (`ghcr.io/finsys/dockhand:latest`), `homepage.nix`, `dozzle.nix` (`amir20/dozzle:latest`), `portainer.nix` (`portainer-ce:latest`), `authelia.nix` (`authelia/authelia:latest`), `nginx-proxy-manager.nix` (`jc21/nginx-proxy-manager:latest`), `stirling-pdf.nix` (`frooodle/s-pdf:latest`), `odysseus.nix` (`chromadb/chroma:latest`).

In a flake-pinned, preflight-gated repo these are the only components whose behavior changes without any lock-file diff: every host pull (image GC, new host, podman/docker re-create) can fetch a different image, including breaking or compromised releases (see M24 for a concrete instance). uptime-kuma (`:1`) and searxng (`2026.5.31`) show the better pattern — pin at least a major tag, ideally a digest.

### M26. Several network services are exposed LAN-wide with no authentication by design of the *module*, not the operator
**Files:** `modules/server/loki.nix` (`auth_enabled = false` + port 3100 opened), `netdata.nix` (19999 opened, no auth), `zigbee2mqtt.nix` (frontend `0.0.0.0:8088` opened — the frontend can re-pair/remove devices), `kiji-proxy.nix` (a *forward proxy* holding `OPENAI_API_KEY` opened to the LAN on 8080 — any LAN host can spend the key), `portbook.nix` (root-run service enumerating all listening services, port 7777 opened), `minio.nix`/`photoprism.nix`/`paperless.nix`/`mealie.nix` etc. (HTTP on `0.0.0.0` + firewall opened unconditionally, no `openFirewall` toggle).

The repo already has the right pattern in syncthing/adguard/vaultwarden/traefik (loopback default + explicit `openFirewall` option + warning comments); the modules above hard-open the firewall with no opt-out short of `lib.mkForce`-ing firewall internals. At minimum each should grow the same `openFirewall ? default` switch, and kiji-proxy should default to binding loopback.

### M27. `services.samba` "client min protocol = NT1" re-enables SMB1 on every display role
**File:** `modules/network-desktop.nix:30-33`.

Documented and deliberate, but it's a global downgrade (affects all SMB client connections, not just the legacy NAS) on desktop, server, htpc, *and* stateless. SMB1 lacks signing/encryption and is the classic MITM/downgrade target. Prefer scoping to the specific NAS via an `[ipc$]`/per-server config, or making it a `vexos.network.allowSmb1` opt-in.

---

## LOW

### L1. Stale comments that contradict the code (doc rot)
- `modules/gpu/vm.nix:5-8` — comment says "Pin to Linux 6.6 LTS ... 6.6 LTS is maintained until Dec 2026" directly above `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;`. Same mismatch in `modules/gpu/vanilla-vm.nix`. The SCX comment in vm.nix ("VM is pinned to 6.6 LTS" — it's 6.12, which *does* support sched_ext, so the `mkForce false` may even be unnecessary now).
- `modules/virtualization.nix:4` — "kernel 7.0 moved KVM symbols" / `modules/system.nix:30-33` (vexos.swap description) reference behavior in "modules/gpu/vm.nix" that matches, fine, but `modules/branding.nix:5` and `modules/network.nix:3` both reference `modules/performance.nix`, which does not exist (renamed to system.nix).
- `modules/gaming.nix:4,70-71` — claims Lutris/ProtonPlus/Bottles are installed "in modules/flatpak.nix"; Lutris/ProtonPlus actually live in `modules/flatpak-desktop.nix`, and **`com.usebottles.bottles` is installed nowhere** (grep-verified) — Bottles is simply missing despite two comments saying it's present.
- `home-desktop.nix:21-23` — "VS Code is installed as unstable.vscode-fhs in modules/development.nix" — false; it's installed 40 lines below via `programs.vscode` (development.nix correctly says so).
- `scripts/stateless-setup.sh:16` — header says step 3 runs `nixos-generate-config --no-filesystems`; line 204 runs it *without* `--no-filesystems`.
- `authorized_keys:1` — "managed by 'just enable-ssh'"; no such recipe exists (the recipe is `just ssh`, which copies keys *to other machines*, not into this file).
- `scripts/preflight.sh:14` — "(all 5 configuration-*.nix files)" — it checks 6.
- `justfile` unbound help text claims "DNS-over-TLS forwarding to Cloudflare (1.1.1.1)" — the module configures pure recursion, no forwarders, no DoT.
- `flake.nix:363-368` — the gpuAmd/gpuNvidia/gpuIntel export comment block describes the VirtualBox-guest `mkForce false` guard, but those exports are bare imports; the guard actually lives inside the gpu modules. Misleading placement only.

### L2. `justfile` default recipe gives wrong stateless guidance
**File:** `justfile:22-30`. Says "Login password resets to 'vexos' on every reboot... update initialPassword in configuration-stateless.nix". There is no 'vexos' password and no `initialPassword`; the real mechanism is `hashedPassword` via `/etc/nixos/stateless-user-override.nix` (which the *correct* text at `migrate-to-stateless.sh:426-428` describes). An operator following this hint will edit the wrong file in the wrong repo.

### L3. VSCode pin tooling references an overlay that doesn't exist
**Files:** `justfile:330-348` (update recipe's version check), `justfile:693-790` (`update-vscode` recipe), vs. `overlays/` (empty directory, verified). The update-check silently no-ops (guarded by `-f`), and `just update-vscode <ver>` always exits "error: overlays/vscode.nix not found". ~120 lines of dead tooling — either restore the overlay or delete the recipes (VS Code now comes from `pkgs.unstable.vscode-fhs`).

### L4. secrets-sops.nix asserts the existence of secrets it declares itself
**File:** `modules/secrets-sops.nix:50-75`. All five `config.sops.secrets ? "..."` assertions are tautologically true because the same `config` block declares those exact secrets 30 lines below. They can never fire; the only assertion doing work is `sopsFile != null`. Dead code that suggests a protection that isn't real (preflight 7c re-implements the real check textually).

### L5. preflight gitleaks failure hides its own findings
**File:** `scripts/preflight.sh:374-380`. `gitleaks detect ... 2>/dev/null` discards stderr — where gitleaks writes its findings log — then prints "review output above" on failure. On a real leak the operator sees a bare FAIL with nothing to review. Drop the `2>/dev/null` (also: `nix flake show --impure` is executed twice at lines 83-84; cache the JSON).

### L6. stateless-setup.sh dead cleanup + hash exposure
**File:** `scripts/stateless-setup.sh:29-32` — `cleanup()` removes `/tmp/disk-password`, which nothing creates anymore (LUKS path removed). Meanwhile the real sensitive artifact, the SHA-512 crypt hash, is written world-readable to `stateless-user-override.nix` (default 0644 via `sudo tee`) and `git add`ed — equivalent to publishing a /etc/shadow line to local users; `install -m 0600` would match the repo's own secrets guidance.

### L7. `nix flake show` / disko / installer scripts fetch moving refs
**Files:** `scripts/stateless-setup.sh:191` (`nix run github:nix-community/disko/latest`), `scripts/install.sh:119,126` (curl|bash of `main` mid-script). All execution paths re-fetch HEAD of remote refs mid-install, so two installs minutes apart can run different code. Within one script run, install.sh (fetched from main) chains to stateless-setup.sh (fetched again from main) — a push between the two fetches mixes script versions. Pinning a tag/rev would make installs reproducible.

### L8. zfs-server installs `pkgs.zfs` userland alongside the module-managed one
**File:** `modules/zfs-server.nix:50-55`. `boot.supportedFilesystems = ["zfs"]` makes NixOS install the userland matching `config.boot.zfs.package`/kernel module; adding `pkgs.zfs` to systemPackages can shadow it with a different build (version skew between `zpool` CLI and the loaded kernel module after channel bumps). Use `config.boot.zfs.package` if it must be listed "for clarity".

### L9. gnome-flatpak-install installs all role apps in one `flatpak install` invocation
**File:** `modules/gnome-flatpak-install.nix:67-70`. Unlike `modules/flatpak.nix` (per-app loop, per-app failure tolerance), one bad/renamed app ID fails the whole transaction; with `Restart=on-failure`, `RestartSec=60`, burst 10, that's up to 10 full retry cycles per boot, re-downloading each time. Mirror the per-app loop from flatpak.nix.

### L10. `kernel-install-override.nix` interplay leaves a window where the override file is deleted but heavy builds proceed anyway
**File:** `modules/nix.nix:142-165`. The override check runs *before* `nix flake update`, so it asks "is the target kernel cached **at the old lock**" and then immediately changes the lock; a kernel that was cached pre-update may be uncached post-update, and the heavy-build gate later restores the lock but **not** the deleted override file (it was only re-written in the pre-update branch). Sequence: override exists → removed → pre-update dry says cached → flake update → post-update dry finds heavy kernel → lock restored, exit 2 — override file is now gone, so the next plain `just rebuild` compiles the kernel locally. Move the override check after the lock update, or restore the file in the exit-2 path.

### L11. Desktop AMD/NVIDIA/Intel host files hardcode ASUS hardware support on
**Files:** `hosts/desktop-amd.nix:11-12`, `hosts/desktop-nvidia.nix`, `hosts/desktop-intel.nix`. `vexos.hardware.asus.enable = true` (+ charge limit 80) is baked into the *generic* desktop variants every non-ASUS desktop would build — asusd/supergfxd run uselessly (and supergfxd has been known to misbehave on non-ASUS boards). The template-flake path correctly makes this an installer question; the repo host files contradict asus-opt.nix's own guidance ("Only host files for physical ASUS machines should set the option").

### L12. `programs.git` ships `user.email = ""` 
**File:** `home/bash-common.nix:13-16`. An explicitly *empty* `user.email` in gitconfig doesn't behave like "unset" — git refuses to commit (`fatal: ... email ... not allowed`) instead of falling back to its automatic ident, and the error message points at config the user didn't knowingly write. Omit the key entirely (mkDefault null / no definition) until the user fills it in.

### L13. Razer overlay is pinned to the `linuxPackages_6_18` attribute name
**File:** `modules/razer.nix:24-46`. The openrazer patch extends `prev.linuxPackages_6_18` specifically. The moment `modules/system-desktop-kernel.nix` bumps to another kernel set (its header says this is planned), the overlay silently stops applying and openrazer reverts to the broken 3.10.3 build — the failure will resurface with no pointer back here. Extending whatever `boot.kernelPackages` resolves to isn't possible in an overlay, but a comment in system-desktop-kernel.nix or an assertion tying the two files together would prevent the silent drift. (The removal condition is well documented: nixpkgs ≥ 26.05 / openrazer ≥ 3.12.3 — worth tracking.)

### L14. environment.sessionVariables `$HOME` literal
**File:** `modules/flatpak.nix:201-206`. `XDG_DATA_DIRS = ... "$HOME/.local/share/flatpak/exports/share"` relies on shell expansion; sessionVariables are also exported to contexts that don't expand (`systemd --user` environment via PAM on some paths), where the literal `$HOME` ends up in the search path. GNOME's own flatpak integration usually papers over this, but it's why only one of the two paths reliably works.

### L15. Minor dead/redundant config
- `modules/network.nix:175` — `allowedTCPPorts = [ 22 ]` duplicates openssh's `openFirewall` default (see M19).
- `modules/gaming.nix:99` — the catch-all `SUBSYSTEM=="input", MODE="0660", GROUP="input"` rule restates the kernel/udev default for input devices.
- `modules/server/cockpit.nix` — `nfsV3TcpPorts` etc. computed unconditionally but harmless; `"bind interfaces only" = "yes"` is set by default while `"interfaces"` is only emitted when `firewall.interfaces` is non-empty, making the bind restriction a no-op in the default configuration.
- `pkgs/kiji-proxy/default.nix:21` — `hash = lib.fakeHash` committed in-tree means `pkgs.vexos.kiji-proxy` is unbuildable until `just enable kiji-proxy` mutates the file; intentional but it means the package can never be CI-built or cached, and `nix build .#...kiji-proxy` failures will confuse contributors.
- `modules/gnome-desktop.nix` (and the other gnome-<role>.nix files) `imports = [ ./gnome.nix ]` while every configuration-*.nix also imports gnome.nix directly — harmless double-import (deduplicated by path) but inconsistent with the stated "role expressed entirely through configuration-*.nix import list" architecture.
- `template/etc-nixos-flake.nix` — `mkVariant`/`mkVanillaVariant`/`mkStatelessVariant` omit `specialArgs = { inputs = ...; }` while the htpc/server builders include it; today nothing in the desktop module tree reads `inputs` from specialArgs (mkBaseModule closes over it lexically), but the asymmetry is a latent trap if any module ever adds an `inputs` argument — it would eval-fail on exactly the variants CI for the template doesn't cover (the template is not CI-evaluated at all).

### L16. `nvidia-vaapi-driver` gated on `useOpen` excludes legacy_535 users who could use it
**File:** `modules/gpu/nvidia.nix:90-93`. The 535 branch supports nvidia-vaapi-driver on Maxwell+ (NVDEC exists since Maxwell; the comment's "NVDEC ... only on Turing" is incorrect). Gating VA-API on `variant == "latest"` removes hardware video decode from exactly the LTS users most likely to want lower CPU usage. Gate on `variant != "legacy_470"` instead if the concern is the 470 branch.

### L17. `journalctl`-unfriendly oneshots: flatpak-install-apps writes failure stamps but `RemainAfterExit=true` masks failure
**File:** `modules/flatpak.nix:143-158`. By design the unit exits 0 on per-app failures so `nixos-rebuild` doesn't go red; the only failure signal is a hidden dotfile (`.last-failed-install`) the operator must know to look for. A `systemd-cat`-visible warning or a `flatpak-install-apps-failed` flag unit would make the silent-failure mode observable; right now `systemctl status flatpak-install-apps` shows green after a 100%-failed install.

---

## Cross-cutting observations

1. **Three copies of the heavy-build regex** (`install.sh` ×2, `nix.nix` ×1, near-copy of the awk extractor in both) — they have already drifted (install.sh's includes `openrazer` in HEAVY but also excludes `linux-[0-9]` in the pre-filter, see M16). Single source (a shared script in `scripts/`) would prevent the next drift.
2. **Assertion discipline is inconsistent across server modules**: code-server, proxmox, papermc, vaultwarden assert their required inputs; vexboard (M13), kavita (M22), headscale (M4), attic (env file) don't. The unguarded ones are exactly the ones that fail at runtime instead of eval time.
3. **The repo's hosts/ files vs. the template flake are two divergent provisioning paths** (hostId, ASUS flag, legacy NVIDIA variants, bootloader handling all differ). H4, M15, and L11 are all symptoms; consolidating per-machine facts into one mechanism would close the class.
4. **`path:` vs `git+file:` flake identity** is load-bearing for both correctness (stateless install narHash workaround at `stateless-setup.sh:225-233`) and security (H2), but the justfile and vexos-update force `path:` unconditionally — the two mechanisms fight each other.

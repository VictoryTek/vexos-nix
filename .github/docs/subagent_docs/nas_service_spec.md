# NAS Service for vexos-nix — Research & Specification

**Status:** Phase 1 — Research & Specification
**Author:** Phase 1 Research Subagent
**Audience:** Phase 2 Implementation Subagent

---

## 1. Executive Summary

The user-supplied URL `github.com/mistakenelf/nasty` returns **HTTP 404**. The
real project is **`github.com/nasty-project/nasty`** (`fenio` / `peigongdsd`,
GPL-3.0, v0.0.6, 106 stars, 2 contributors as of 2026-05). After auditing its
flake and module layout, the verdict is:

> **NASty CANNOT be integrated as a `vexos.server.nasty.enable` opt-in
> module.** It is a complete NAS *appliance distribution* (own ISO, own
> nixosSystem, own kernel patches, own Rust engine that drives `bcachefs`
> ioctls), structurally coupled to bcachefs and unstable nixpkgs. Substituting
> ZFS would require forking and rewriting the Rust engine — out of scope for
> this repository.

**Recommendation:** add a native, ZFS-friendly NAS surface to vexos-nix in
two complementary, opt-in modules following the existing
`vexos.server.<name>.enable` pattern:

1. **`modules/server/nas.nix`** — declarative Samba + NFS share surface
   (`vexos.server.nas.*`).
2. **A new `vexos.server.cockpit.fileSharing.enable` sub-option inside the
   existing `modules/server/cockpit.nix`** — adds the 45Drives Cockpit pages
   (`cockpit-file-sharing`, `cockpit-navigator`, `cockpit-identities`) for a
   web UI on top of the same Samba/NFS daemons.

ZFS dataset/pool creation remains manual (project convention; see
[scripts/create-zfs-pool.sh](../../../scripts/create-zfs-pool.sh)).

---

## 2. Current State Analysis

### 2.1 Server module pattern

`modules/server/` uses an **always-imported umbrella** ([modules/server/default.nix](../../../modules/server/default.nix)) that pulls in every service file. Every service file follows the same shape:

```nix
options.vexos.server.<svc>.enable = lib.mkEnableOption "...";
config = lib.mkIf cfg.enable { services.<svc>.enable = true; ... };
```

Examples confirming the pattern:
[adguard.nix](../../../modules/server/adguard.nix), [audiobookshelf.nix](../../../modules/server/audiobookshelf.nix), [cockpit.nix](../../../modules/server/cockpit.nix), [scrutiny.nix](../../../modules/server/scrutiny.nix), [syncthing.nix](../../../modules/server/syncthing.nix).

> **Important:** `lib.mkIf cfg.enable` inside `modules/server/<svc>.nix` is
> the *opt-in service flag*, not a role gate. The Module Architecture Pattern
> (Option B) prohibits role/display-flag gates in *shared base* modules — it
> does not prohibit per-service `enable` flags inside the always-imported
> server umbrella. The new NAS module follows the same convention.

### 2.2 Storage baseline

[modules/zfs-server.nix](../../../modules/zfs-server.nix) is imported by both
`configuration-server.nix` and `configuration-headless-server.nix`. It:

- Sets `boot.supportedFilesystems = [ "zfs" ]`.
- Pins `boot.kernelPackages = pkgs.linuxPackages` (LTS) at priority 75 to
  satisfy ZFS's lagging kernel-compat window.
- Enables monthly autoscrub and weekly trim.
- Derives `networking.hostId` from `/etc/machine-id`.
- Pulls in `zfs`, `gptfdisk`, `util-linux`, `pciutils` for the manual
  `just create-zfs-pool` workflow.

`boot.zfs.extraPools = [ ]` — pools are auto-imported via
`/etc/zfs/zpool.cache`. `system.stateVersion` is `25.11`.

### 2.3 Existing share-related surface

- [modules/network-desktop.nix](../../../modules/network-desktop.nix) enables
  Samba in **client-only mode** (`smbd/nmbd/winbindd = lib.mkDefault false`)
  for GVfs share browsing, plus `services.samba-wsdd` and Avahi publishing.
  This is imported by `configuration-server.nix` (for the GUI server role)
  but **not** by `configuration-headless-server.nix`.
- The base `services.samba.enable = true` and the `lib.mkDefault false` on
  daemons mean a server-side NAS module can simply set
  `services.samba.smbd.enable = true; services.samba.nmbd.enable = true;`
  without conflict.
- [modules/server/cockpit.nix](../../../modules/server/cockpit.nix) already
  exposes `vexos.server.cockpit.enable` and binds Cockpit to `:9090`.
- No existing NFS server, share-management UI, or per-share ACL surface.

### 2.4 Reverse proxy / auth conventions

- `modules/server/caddy.nix` provides `services.caddy.enable` and opens
  80/443. Per-vhost `reverse_proxy` config is added in
  `/etc/nixos/server-services.nix` (see the comment in
  [caddy.nix](../../../modules/server/caddy.nix)).
- `modules/server/authelia.nix` runs Authelia in an OCI container at `:9091`.
  Integration with reverse-proxied vhosts is the deployer's responsibility
  (per-vhost `forward_auth` block).

NAS protocols **must not** be reverse-proxied: SMB (445) and NFS (2049) are
TCP/UDP services that bypass HTTP entirely. Only the optional Cockpit web UI
benefits from Caddy + Authelia.

---

## 3. NASty Project Assessment

### 3.1 What it actually is

| Aspect | Reality |
|---|---|
| Repository | `github.com/nasty-project/nasty` (the URL in the request was wrong) |
| License | GPL-3.0-only |
| Maturity | v0.0.6, README says "experimental, not production-ready" |
| Contributors | 2 (`fenio`, `peigongdsd`) |
| Languages | Rust 59.5%, Svelte 32.2%, Nix 4.9% |
| Shape | Full NAS *distribution*, not a service module |
| Outputs | `nasty`, `nasty-rootfs`, `nasty-iso`, `nasty-iso-sd`, `nasty-vm`, `nasty-cloud` (whole `nixosSystem`s) — no composable per-service flag |
| Filesystem | bcachefs, with custom `nasty-bcachefs-tools` (patched `CONFIG_BCACHEFS_QUOTA`) and an out-of-tree DKMS module |
| nixpkgs channel | `nixos-unstable` (vexos pins `nixos-25.11`) |
| Networking | NetworkManager (vexos uses scripted networking elsewhere) |
| TLS | Built-in ACME TLS-ALPN-01 (would conflict with vexos Caddy on 443) |
| Auth | Own user DB + optional OIDC (no Authelia integration story) |
| Telemetry | Anonymous opt-out telemetry to `nasty-telemetry` |
| Released `nixosModules` | `nasty`, `bcachefs`, `linuxquota`, `appliance-base` — but `nasty.nix` hard-imports `bcachefs.nix` and `linuxquota.nix` and assumes engine + webui + bcachefs-tools as `specialArgs` |

### 3.2 bcachefs coupling depth — evidence

From `flake.nix` (fetched 2026-05-08):

- `inputs.bcachefs-tools.url = "github:koverstreet/bcachefs-tools/v1.38.2"` is
  **always pinned**; the comment says "to revert to pure nixpkgs, comment out
  these two lines" — but the engine still calls bcachefs CLIs.
- `mkBcachefsTools` overrides `pkgs.bcachefs-tools` and patches the DKMS
  Makefile to inject `-DCONFIG_BCACHEFS_QUOTA` — i.e. NASty needs a custom
  kernel module build, not a stock filesystem.
- *Every* nixosSystem output (`nasty`, `nasty-rootfs`, `nasty-iso`,
  `nasty-iso-sd`, `nasty-vm`, `nasty-cloud`) imports
  `./nixos/modules/bcachefs.nix` and `./nixos/modules/linuxquota.nix`.
- The Rust engine surfaces bcachefs-specific operations: subvolumes, online
  scrub, replication, erasure coding, tiering, instant clones (`bcachefs
  subvolume snapshot`). The Web UI screens (Filesystems, Subvolumes, Sharing)
  expose these concepts directly.
- The FAQ section "Why bcachefs instead of ZFS?" explicitly frames bcachefs
  as a foundational design choice, not an implementation detail.

### 3.3 Viability verdict: REJECT

Concrete blockers:

1. **Engine ↔ bcachefs is structural.** The Rust engine wraps bcachefs
   ioctls/CLI; ZFS substitution requires a parallel ZFS backend that
   upstream does not provide and is unlikely to accept (their stated
   philosophy contrasts directly with ZFS). Cost: fork + maintain a Rust
   crate ≈ a separate full-time project.
2. **Two FS stacks on one host is a regression.** Running bcachefs DKMS +
   ZFS on the same kernel doubles out-of-tree module surface, lengthens
   `nixos-rebuild` (already a documented pain point in
   [modules/zfs-server.nix](../../../modules/zfs-server.nix)), and
   compounds kernel-pinning constraints. Also: bcachefs requires recent
   kernels (6.7+); ZFS requires LTS.
3. **Channel mismatch.** NASty tracks `nixos-unstable` and depends on its
   pace of bcachefs-tools/kernel updates. vexos pins `nixos-25.11`.
4. **Convention conflicts.** NASty wants to own NetworkManager, ACME on 443,
   the auth layer, and `boot.kernelPackages` — every one of which is
   already governed by an existing vexos module.
5. **Maturity risk.** v0.0.6, 2 contributors, "not production"; vexos is
   a long-lived personal NixOS configuration.
6. **No fit for the umbrella pattern.** NASty exposes whole-system
   `nixosSystem`s, not a `vexos.server.<svc>.enable`-style toggleable
   service. The closest reusable artefact is `nixosModules.nasty`, which
   transitively pulls bcachefs-tools and the engine binary regardless.

A "fork and ZFS-port NASty" path is theoretically possible but is a
multi-month project that owns its own repository, not a vexos-nix
specification.

---

## 4. Alternatives Comparison

| Option | ZFS-friendly | NixOS-native | Web UI | Auth | Maintenance | Verdict |
|---|---|---|---|---|---|---|
| **NASty** (as-is) | No (bcachefs structural) | Partial (own flake, unstable channel) | Yes (Svelte) | Own + OIDC | 2 contributors, v0.0.6 | **Reject** |
| **NASty (fork to ZFS)** | Would be | Yes | Yes | Own | Self-maintained fork | Reject — out of scope |
| **Cockpit + 45Drives modules** (`cockpit-file-sharing`, `cockpit-navigator`, `cockpit-identities`) | Yes (FS-agnostic; ZFS plugin separate) | Yes (`pkgs.cockpit*` in nixpkgs; `services.cockpit` upstream) | Yes (Cockpit @ :9090) | Cockpit auth → Caddy/Authelia in front | 45Drives org, GPL-3, active | **Recommended** for UI |
| **Vanilla `services.samba` + `services.nfs.server` + `services.samba-wsdd`** | Yes | Yes (built-in) | No | OS users + share ACLs | nixpkgs core, mature | **Recommended** for protocol layer |
| **OpenMediaVault** | N/A (Debian appliance) | No NixOS port | Yes | Own | Active but Debian-only | Reject |
| **TrueNAS SCALE** | ZFS-native but appliance | No NixOS port (Debian-based image) | Yes | Own | Active | Reject |
| **Webmin / Usermin** | Yes | Available in nixpkgs but mutable-config-oriented | Yes | Own | Aging UX | Reject (poor declarative fit) |

### 4.1 Why "vanilla samba/nfs + Cockpit + 45Drives" wins

- **Zero new flake inputs.** Everything is already in nixpkgs 25.11
  (`pkgs.cockpit-file-sharing`, `pkgs.cockpit-navigator`,
  `pkgs.cockpit-identities`, `pkgs.samba`, `services.nfs.server`,
  `services.samba-wsdd`). Verified via the NixOS Wiki and nixpkgs `pkgs/by-name`.
- **Already-aligned with vexos.** Cockpit module exists; Samba is already
  enabled in client mode by `modules/network-desktop.nix`.
- **ZFS-native.** Shares are paths under existing ZFS datasets — no
  filesystem assumptions in the module.
- **Composable with Caddy + Authelia** for the *web UI only* (Cockpit on
  9090). SMB/NFS ports are L4 and bypass Caddy.
- **Headless-server compatible.** Cockpit and the daemons are pure CLI;
  no display dependencies.

---

## 5. Proposed Solution Architecture

Two modules, both opt-in via `vexos.server.<name>.enable`:

### 5.1 `modules/server/nas.nix` (new)

Declarative Samba + NFS share management. ZFS-agnostic in code (paths only),
ZFS-aware in documentation comments.

**Option surface:**

```nix
options.vexos.server.nas = {
  enable = lib.mkEnableOption "Samba/NFS NAS share server";

  hostName = lib.mkOption {
    type = lib.types.str;
    default = "vexos-nas";
    description = "Samba NetBIOS name advertised on the LAN.";
  };

  workgroup = lib.mkOption {
    type = lib.types.str;
    default = "WORKGROUP";
    description = "SMB workgroup.";
  };

  openFirewall = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Open SMB (445), NetBIOS (137-139), NFS (2049, 111), and WSDD (3702/5357) ports.";
  };

  samba = {
    enable = lib.mkOption { type = lib.types.bool; default = true; };
    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = {};
      description = ''
        Raw smb.conf share sections, keyed by share name. Example:
          { media = { path = "/tank/media"; "read only" = "yes"; "guest ok" = "yes"; };
            backup = { path = "/tank/backup"; "valid users" = "@nas"; "read only" = "no"; }; }
        Paths SHOULD live on a ZFS dataset (e.g. /tank/<dataset>) created
        manually via scripts/create-zfs-pool.sh — dataset provisioning is
        explicitly out of scope for this module.
      '';
    };
  };

  nfs = {
    enable  = lib.mkOption { type = lib.types.bool; default = false; };
    exports = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Contents of /etc/exports. Example:
          /tank/media   192.168.1.0/24(rw,sync,no_subtree_check)
          /tank/backup  192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
        Paths SHOULD live on a ZFS dataset created manually (see above).
      '';
    };
  };

  wsdd.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Run samba-wsdd so Windows clients see the host in 'Network'.";
  };

  avahi.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Publish _smb._tcp / _nfs._tcp via mDNS for macOS/GNOME discovery.";
  };
};
```

**Implementation sketch (high-level — exact syntax for Phase 2):**

```nix
config = lib.mkIf cfg.enable (lib.mkMerge [

  # ── Samba server ──────────────────────────────────────────────────────
  (lib.mkIf cfg.samba.enable {
    # network-desktop.nix sets daemons to lib.mkDefault false; override here.
    services.samba = {
      enable          = true;     # already true on GUI server via network-desktop
      smbd.enable     = true;
      nmbd.enable     = true;
      openFirewall    = false;    # we manage the firewall ourselves below
      settings = lib.mkMerge [
        {
          global = {
            workgroup       = cfg.workgroup;
            "server string" = cfg.hostName;
            "netbios name"  = cfg.hostName;
            "server role"   = "standalone";
            security        = "user";
            "map to guest"  = "Bad User";
            "load printers" = "no";
            # Modern SMB only; reject legacy SMB1/NTLMv1.
            "min protocol"  = "SMB2";
            "client min protocol" = "SMB2";
            # Disable mDNS-via-samba; Avahi handles it.
            "multicast dns register" = "no";
          };
        }
        cfg.samba.shares
      ];
    };
  })

  # ── NFS server ────────────────────────────────────────────────────────
  (lib.mkIf cfg.nfs.enable {
    services.nfs.server = {
      enable    = true;
      exports   = cfg.nfs.exports;
      # Pin lockd ports for firewall predictability:
      lockdPort = 4001;
      mountdPort = 4002;
      statdPort  = 4000;
    };
  })

  # ── Discovery: Avahi + WSDD ──────────────────────────────────────────
  (lib.mkIf cfg.avahi.enable {
    services.avahi = {
      enable        = true;
      nssmdns4      = true;
      publish.enable      = true;
      publish.userServices = true;
      publish.addresses   = true;
      publish.workstation = true;
    };
  })

  (lib.mkIf cfg.wsdd.enable {
    services.samba-wsdd = {
      enable       = true;
      hostname     = cfg.hostName;
      workgroup    = cfg.workgroup;
      openFirewall = cfg.openFirewall;
    };
  })

  # ── Firewall ────────────────────────────────────────────────────────
  (lib.mkIf cfg.openFirewall {
    networking.firewall.allowedTCPPorts = lib.flatten [
      (lib.optionals cfg.samba.enable [ 139 445 ])
      (lib.optionals cfg.nfs.enable   [ 111 2049 4000 4001 4002 ])
    ];
    networking.firewall.allowedUDPPorts = lib.flatten [
      (lib.optionals cfg.samba.enable [ 137 138 ])
      (lib.optionals cfg.nfs.enable   [ 111 2049 ])
    ];
  })
]);
```

**Notes for Phase 2:**

- The `services.samba.settings` `lib.mkMerge` of a base global section with
  `cfg.samba.shares` is the canonical NixOS 25.11 pattern for the
  `attrsOf attrsOf` config tree (replaces the old `extraConfig` text blob).
- Do **NOT** add `system.stateVersion` changes. Do **NOT** create
  `/etc/exports` or `smb.conf` outside the NixOS module system.
- The module purposely does not create users; share permissions are managed
  via existing OS users (defined in [modules/users.nix](../../../modules/users.nix))
  plus `smbpasswd` runs the operator performs out-of-band — same model as
  Authelia and Cockpit (which require manual config in `/var/lib/...`).
- Cohabitation with `modules/network-desktop.nix`:
  - That module sets `services.samba.enable = true` and
    `smbd/nmbd/winbindd = lib.mkDefault false`. `lib.mkDefault` priority
    is 1000 → our plain `services.samba.smbd.enable = true` (priority 100)
    wins automatically. No `lib.mkForce` required.
  - The `samba-wsdd` block in `network-desktop.nix` uses
    `discovery = true`; our NAS module sets the **server-side** WSDD with
    `hostname`/`workgroup`. The NixOS option set accepts both — no
    duplicate-priority conflict.
  - On `headless-server`, `network-desktop.nix` is **not** imported. Our
    module enables `services.samba` itself, so it works standalone.

### 5.2 `modules/server/cockpit.nix` (extend, not replace)

Add a sub-option that pulls in the 45Drives Cockpit pages. Keep the existing
`vexos.server.cockpit.enable` and `port` options unchanged.

```nix
options.vexos.server.cockpit.fileSharing = {
  enable = lib.mkEnableOption ''
    45Drives Cockpit file-sharing pages (cockpit-file-sharing,
    cockpit-navigator, cockpit-identities). Provides a web UI on top of
    the Samba/NFS daemons configured by vexos.server.nas. Requires
    vexos.server.cockpit.enable = true.
  '';
};
```

```nix
config = lib.mkMerge [
  (lib.mkIf cfg.enable { /* existing services.cockpit block */ })
  (lib.mkIf (cfg.enable && cfg.fileSharing.enable) {
    environment.systemPackages = with pkgs; [
      cockpit-file-sharing
      cockpit-navigator
      cockpit-identities
    ];
  })
];
```

The 45Drives packages drop their plugin `index.html`/`manifest.json` into
`/usr/share/cockpit/<plugin>` (NixOS profile path under
`/run/current-system/sw/share/cockpit`); Cockpit auto-discovers them — no
extra `services.cockpit` wiring is required.

### 5.3 Registration

Add **one** line to [modules/server/default.nix](../../../modules/server/default.nix):

```nix
    # ── Cloud & Files ────────────────────────────────────────────────────────
    ./nextcloud.nix
    ./syncthing.nix
    ./immich.nix
    ./minio.nix
    ./photoprism.nix
    ./nas.nix          # ← add this line
```

The Cockpit extension lives inside the existing `cockpit.nix` and therefore
needs no new registration.

### 5.4 What is NOT changed

- No new flake inputs. Confirmed: `pkgs.cockpit-file-sharing`,
  `pkgs.cockpit-navigator`, `pkgs.cockpit-identities`, `pkgs.samba`,
  `services.nfs.server`, `services.samba-wsdd` are all in nixpkgs 25.11.
- No edits to `flake.nix`, `configuration-server.nix`,
  `configuration-headless-server.nix`, or any host file in `hosts/`.
  Importing the umbrella `./modules/server` already loads `nas.nix` once
  it is registered. **Per the umbrella pattern, "import" is not "enable";
  the operator turns it on in `/etc/nixos/server-services.nix`.**
- `system.stateVersion` is not touched.
- `hardware-configuration.nix` is not added to the repo.

---

## 6. Implementation Steps (ordered)

1. **Create [modules/server/nas.nix](../../../modules/server/nas.nix)** with
   the option surface and `mkMerge` config from §5.1. Match the comment
   style of [audiobookshelf.nix](../../../modules/server/audiobookshelf.nix)
   (top-of-file purpose comment + inline option descriptions).
2. **Edit [modules/server/cockpit.nix](../../../modules/server/cockpit.nix)**
   to add the `fileSharing.enable` sub-option and the conditional
   `environment.systemPackages` block (§5.2). Preserve existing
   `cfg.enable` / `cfg.port` semantics; switch the `config` body to
   `lib.mkMerge`.
3. **Register** `./nas.nix` in
   [modules/server/default.nix](../../../modules/server/default.nix) under
   the "Cloud & Files" section (§5.3).
4. **Validate**:
   - `nix flake check`
   - `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-server-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`
   - `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
   - `bash scripts/preflight.sh` (per project preflight contract)
5. **Document usage** in the new module's header comment (no separate
   markdown file). Show an example block the operator pastes into
   `/etc/nixos/server-services.nix`:

   ```nix
   vexos.server.nas = {
     enable = true;
     hostName = "tank";
     samba.shares = {
       media = {
         path = "/tank/media";
         "read only" = "yes";
         "guest ok"  = "yes";
       };
       backup = {
         path = "/tank/backup";
         "valid users" = "@nas";
         "read only" = "no";
       };
     };
     nfs = {
       enable  = true;
       exports = ''
         /tank/media   192.168.1.0/24(ro,sync,no_subtree_check)
         /tank/backup  192.168.1.0/24(rw,sync,no_subtree_check)
       '';
     };
   };

   vexos.server.cockpit = {
     enable             = true;
     fileSharing.enable = true;   # adds 45Drives pages
   };
   ```

No edits to `flake.nix`, host files, or `configuration-*.nix`.

---

## 7. Dependencies

| Item | Source | Context7 verification |
|---|---|---|
| `services.samba` (declarative `settings` tree) | nixpkgs `nixos/modules/services/networking/samba.nix` | Internal NixOS module — Context7 not applicable per copilot-instructions §"Dependency & Documentation Policy" (no new external library). Verified via existing usage in [modules/network-desktop.nix](../../../modules/network-desktop.nix). |
| `services.nfs.server` | nixpkgs `nixos/modules/services/network-filesystems/nfsd.nix` | Internal NixOS module. |
| `services.samba-wsdd` | nixpkgs (already used in [modules/network-desktop.nix](../../../modules/network-desktop.nix)) | Internal NixOS module. |
| `services.avahi` | nixpkgs (already used in [modules/network.nix](../../../modules/network.nix) and [modules/network-desktop.nix](../../../modules/network-desktop.nix)) | Internal NixOS module. |
| `pkgs.cockpit-file-sharing` | nixpkgs (45Drives, GPL-3.0) | nixpkgs package — Context7 not applicable. Verified present in nixos-25.11. |
| `pkgs.cockpit-navigator` | nixpkgs (45Drives, GPL-3.0) | Same. |
| `pkgs.cockpit-identities` | nixpkgs (45Drives, GPL-3.0) | Same. |
| `services.cockpit` | nixpkgs (already used in [modules/server/cockpit.nix](../../../modules/server/cockpit.nix)) | Internal NixOS module. |

**No new flake inputs.** No `inputs.<name>.follows = "nixpkgs"` work
required. No external Rust/Go libraries pulled in.

Per the project's Context7 policy, Context7 lookups are required only when a
**new external library / framework / Rust crate** is introduced. This
specification adds none — every artefact is a stock nixpkgs package or a
core NixOS module already in active use elsewhere in the repository.

---

## 8. Configuration Changes

| File | Change | Reason |
|---|---|---|
| `modules/server/nas.nix` | **NEW** | Samba + NFS share surface |
| `modules/server/cockpit.nix` | Add `fileSharing.enable` sub-option | Optional 45Drives Cockpit pages |
| `modules/server/default.nix` | Add `./nas.nix` import line | Register the new service in the umbrella |

No changes to:

- `flake.nix` (no new inputs, no host list change)
- `configuration-server.nix`, `configuration-headless-server.nix`
- Any file in `hosts/`
- Any file in `home/`, `home-*.nix`
- Any file in `modules/` outside `modules/server/`
- `scripts/preflight.sh`

The umbrella import pattern means the new module is automatically present in
both `vexos-server-*` and `vexos-headless-server-*` outputs without any
host-file plumbing. Per the project's Option B doctrine, the absence of
`lib.mkIf <role>` gates inside `nas.nix` is intentional: importing is
unconditional; the operator turns it on (or off) by setting
`vexos.server.nas.enable` in their `/etc/nixos/server-services.nix`.

---

## 9. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Data loss from misconfigured share path** (e.g. share points at non-existent `/tank/...`) | High | Module makes no assumptions about pool layout; option descriptions clearly state datasets must be created via `scripts/create-zfs-pool.sh` first. `services.nfs.server` will fail to start cleanly if the export path doesn't exist (visible failure ≫ silent corruption). |
| **SMB/NFS exposed on the wrong interface** | High | `openFirewall` is opt-in (default `true` for LAN convenience). Operator can set `false` and write per-zone rules. NFS export lines already require an explicit CIDR. SMB defaults reject `guest` unless the share opts in via `"guest ok" = "yes"`. |
| **Legacy SMB1/NTLMv1 acceptance** | Medium | Module sets `min protocol = SMB2` and `client min protocol = SMB2` globally, opting out of the historical SMB1 vulnerabilities (EternalBlue family). |
| **Conflict with `network-desktop.nix` Samba client config** on GUI server | Medium | `network-desktop.nix` uses `lib.mkDefault false` on daemons → our explicit `true` wins automatically. No `lib.mkForce` needed. Verified by reading both files. |
| **Cockpit on a public interface** | Medium | Existing `vexos.server.cockpit` enables `openFirewall = true` on :9090. Operator should reverse-proxy via Caddy + Authelia (standard vexos pattern) before exposing. Documented in module header comment. |
| **45Drives Cockpit plugins becoming unmaintained** | Low | nixpkgs maintains the packages; failure mode is "plugin missing" — does not break the underlying samba/nfs daemons. Alternative: drop `fileSharing.enable` and keep the protocol layer. |
| **Headless-server vs full-server divergence** | Low | NAS module is filesystem-/display-agnostic. Cockpit fileSharing UI works on headless because Cockpit's UI is client-side (any browser on the LAN). |
| **Two FS stacks (bcachefs + ZFS)** if a future maintainer reconsiders NASty | Already mitigated — this spec rejects NASty | — |
| **`system.stateVersion` accidentally bumped** | Low | This spec explicitly does not touch it; Phase 3 review must verify. |

---

## 10. Out-of-Scope

- ZFS pool/dataset provisioning. Continues to be manual via
  `scripts/create-zfs-pool.sh` / `just create-zfs-pool` (project convention).
- User account creation and `smbpasswd` enrolment. Operator runs
  `sudo smbpasswd -a <user>` once after first boot, identical to the
  existing Authelia / Cockpit "create config files manually" pattern.
- Backup orchestration (snapshots, send/recv, off-site replication).
- Quota management (left to native ZFS dataset quotas).
- iSCSI / NVMe-oF block-storage targets (NASty's domain; not requested).
- ACL editor UIs beyond what `cockpit-file-sharing` ships with.
- TLS termination for the Cockpit UI (handled by an operator-defined Caddy
  vhost in `/etc/nixos/server-services.nix`, per existing convention).
- NASty integration in any form (rejected; see §3.3).

---

## 11. Source Inventory (≥6 credible sources)

1. **`github.com/nasty-project/nasty` README** — feature list, architecture
   table, project structure (fetched 2026-05-08).
2. **`github.com/nasty-project/nasty/blob/main/FAQ.md`** — "Why bcachefs
   instead of ZFS?", maturity disclosures, contributor count (fetched
   2026-05-08).
3. **`github.com/nasty-project/nasty/blob/main/flake.nix`** — `nasty-iso`,
   `nasty-rootfs`, `nasty-vm`, `nasty-cloud` outputs; `mkBcachefsTools`
   override patching `CONFIG_BCACHEFS_QUOTA`; every system imports
   `bcachefs.nix` + `linuxquota.nix` (fetched 2026-05-08).
4. **NixOS Manual / `services.samba` option** — declarative `settings`
   attrset replacing `extraConfig`, available since NixOS 24.05 and current
   in 25.11. Verified pattern via `modules/network-desktop.nix` in this
   repo, which uses the same `services.samba.settings.global` shape.
5. **NixOS Manual / `services.nfs.server`** — `exports`, `lockdPort`,
   `mountdPort`, `statdPort` options (current in 25.11). Verified via
   nixpkgs `nixos/modules/services/network-filesystems/nfsd.nix`.
6. **45Drives' Cockpit plugin suite** —
   `cockpit-file-sharing`, `cockpit-navigator`, `cockpit-identities`
   (GitHub `45Drives/cockpit-file-sharing`, GPL-3.0). Packaged in nixpkgs
   under the same names; no overlay needed.
7. **NixOS Wiki: Samba** — confirms `services.samba-wsdd` and Avahi
   publishing as the standard Windows-discovery + macOS-discovery stack.
8. **vexos-nix repo files referenced inline above**: `flake.nix`,
   `configuration-server.nix`, `configuration-headless-server.nix`,
   `modules/server/default.nix`, `modules/server/{adguard,audiobookshelf,authelia,caddy,cockpit,scrutiny,syncthing}.nix`,
   `modules/zfs-server.nix`, `modules/network-desktop.nix`,
   `hosts/server-amd.nix`.

---

## 12. Recommendation

**Implement §5 as specified.** This delivers the user-visible NAS
functionality NASty was meant to provide (declarative SMB + NFS with a web
UI) without adopting NASty's bcachefs-coupled appliance shape, without
introducing a second filesystem stack, without channel drift to
nixos-unstable, and without conflicting with vexos-nix's Caddy/Authelia/ZFS
conventions. Total scope: one new file (`nas.nix`), one extended file
(`cockpit.nix`), one umbrella registration line. Zero new flake inputs.
Zero changes to host configuration or `flake.nix`.

# Podman + Dockhand Server Services — Implementation Specification

**Feature:** `podman_dockhand`  
**Date:** 2026-05-20  
**Target roles:** `server`, `headless-server`  
**NixOS channel:** `nixos-25.11`

---

## 1. Current State Analysis

### Existing module infrastructure

`modules/server/default.nix` is the umbrella import registry for all optional server
service modules. Every module exposes a `vexos.server.<service>.enable` option
(default: `false`). Activation is done by setting the flag in
`/etc/nixos/server-services.nix` on the host (loaded at flake eval time via
`serverServicesModule` in `flake.nix`).

A **container runtime module already exists**: `modules/server/docker.nix` enables
the Docker daemon with `virtualisation.docker` and `autoPrune`. There is currently
**no Podman module**.

### Relevant module patterns (from reference files)

| Module | Pattern observed |
|--------|-----------------|
| `headscale.nix` | `lib.mkIf cfg.enable { services.headscale = { ... }; networking.firewall.allowedTCPPorts = [ cfg.port ]; }` |
| `proxmox.nix` | `lib.mkIf cfg.enable { assertions = [ ... ]; ... }` — uses assertions for required config values |
| `docker.nix` | `lib.mkIf cfg.enable { virtualisation.docker = { enable = true; autoPrune = { ... }; }; users.users.${config.vexos.user.name}.extraGroups = [ "docker" ]; }` |

### Module Architecture Pattern

This project uses **Option B: Common base + role additions**.

- Universal base file: no `lib.mkIf` guards gating content by role or feature flag
  inside the shared file itself.
- Role/feature additions live in separate files.
- A `configuration-*.nix` expresses its role **entirely through its import list**.
- `modules/server/default.nix` is the registry; all server modules are imported
  unconditionally there; their content is gated by `lib.mkIf cfg.enable` inside
  each module.

### Configuration files

Both `configuration-server.nix` and `configuration-headless-server.nix` already
import `./modules/server` (the directory, loading `default.nix`). No changes to
either configuration file are required — new modules are registered only in
`modules/server/default.nix`.

---

## 2. Problem Definition / Goal

**Goal:** Add two new opt-in server service modules:

1. **`vexos.server.podman`** — Rootful Podman container runtime with Docker API
   compatibility, suitable for declarative NixOS OCI container management.

2. **`vexos.server.dockhand`** — Dockhand container management UI, deployed as an
   OCI container via `virtualisation.oci-containers`, backed by the Podman socket.

These modules must follow the Module Architecture Pattern (no conditional logic
inside shared modules; separation between Podman and Dockhand concerns) and must
not modify any existing configuration file except `modules/server/default.nix`.

---

## 3. Architecture Decisions

### 3.1 Why OCI containers (`virtualisation.oci-containers`) for Dockhand

- Dockhand ships no NixOS package; it is distributed as a container image only.
- NixOS `virtualisation.oci-containers` is the idiomatic, declarative way to run
  third-party container images as systemd-managed services.
- No Nix packaging or derivation required; the image is pulled at first run.
- The backend is set to `"podman"` in the Podman module, so all OCI container
  services on the system use Podman (not Docker).

### 3.2 Why `dockerCompat = true`

- Dockhand speaks the Docker REST API (`/var/run/docker.sock`). It does not speak
  the Podman native API directly.
- `virtualisation.podman.dockerCompat = true` creates the
  `docker.socket` systemd socket unit at **`/run/docker.sock`**, which provides a
  Docker-compatible API endpoint backed by Podman.
- This allows Dockhand (and any other Docker-API client) to manage containers via
  Podman without any reconfiguration of the client.
- `virtualisation.podman.dockerSocket.enable` is implied/enabled by
  `dockerCompat = true` (NixOS 25.11 confirmed option).

### 3.3 Socket path: `/run/docker.sock`

On NixOS 25.11 with `virtualisation.podman.dockerCompat = true`:

| Socket | Host path | Created by |
|--------|-----------|------------|
| Docker-compat (Podman-backed) | `/run/docker.sock` | `virtualisation.podman.dockerCompat = true` |
| Native Podman API | `/run/podman/podman.sock` | `virtualisation.podman.dockerSocket.enable` (not needed here) |

For Dockhand's volume mount we use **`/run/docker.sock:/var/run/docker.sock`**.
This is the socket created automatically by `dockerCompat = true` and is the
recommended path for Docker-API clients on NixOS.

The Dockhand upstream docs note: "For Podman, map the Podman socket to the Docker
socket path inside the container: `-v /run/podman/podman.sock:/var/run/docker.sock:Z`"
That instruction targets non-NixOS systems. On NixOS with `dockerCompat`, the
Docker-compat socket at `/run/docker.sock` is the correct host path.

> **Note on `:Z`:** The `:Z` SELinux relabeling suffix is not needed on NixOS,
> which uses AppArmor (not SELinux) for MAC.

### 3.4 Running Dockhand as root inside the container

Dockhand's official documentation recommends root (`user: "0:0"`) as the simplest
socket-permission approach for home lab / private server environments:

> "Home lab or private server behind a VPN (Tailscale/WireGuard): Option 1 (GID
> matching) or Option 2 (root) is acceptable."

Since vexos-nix targets personal home-lab use, we run Dockhand as `root:root` to
avoid GID-matching complexity. This is explicit and reviewable via the NixOS option.

### 3.5 Data directory: matching paths

Dockhand stores its SQLite database, stack definitions, and Git repo clones under
its data directory (`/app/data` by default).

When deploying compose stacks with relative volume paths, the Docker/Podman daemon
resolves paths on the *host* filesystem. If the container path (`/app/data`) differs
from the host path, relative paths in compose files break silently.

**Solution: matching paths.** Mount `cfg.dataDir` to the same absolute path inside
the container and set `DATA_DIR` env var accordingly:

```
host:      /var/lib/dockhand   (default)
container: /var/lib/dockhand   (same path)
DATA_DIR:  /var/lib/dockhand
```

This is Dockhand's recommended "matching paths" setup documented in the manual.

### 3.6 Separation of Podman and Dockhand concerns

- `podman.nix`: all Podman engine configuration; no Dockhand-specific logic.
- `dockhand.nix`: OCI container definition for Dockhand; asserts Podman is enabled;
  no Podman engine configuration.
- An assertion in `dockhand.nix` enforces the dependency at evaluation time.

### 3.7 `virtualisation.oci-containers.backend = "podman"`

Set in `podman.nix`. This makes all `virtualisation.oci-containers.containers`
definitions on the system use Podman as the container runtime. This is correct
since Podman is the runtime being configured; Docker is not.

**Conflict risk:** If `vexos.server.docker.enable = true` and
`vexos.server.podman.enable = true` are both set, both the Docker daemon and Podman
will be installed, but only Podman will be used as the OCI container backend. Docker
will be idle. This is unusual but not a hard error. The spec documents this as a
risk (see §9).

---

## 4. Files to Create / Modify

| Action | File |
|--------|------|
| **Create** | `modules/server/podman.nix` |
| **Create** | `modules/server/dockhand.nix` |
| **Modify** | `modules/server/default.nix` |

---

## 5. Implementation: `modules/server/podman.nix`

```nix
# modules/server/podman.nix
# Podman container runtime with Docker API compatibility.
# Enables the Docker-compat socket at /run/docker.sock so that Docker-API
# clients (e.g. Dockhand) can communicate with Podman transparently.
# Sets virtualisation.oci-containers.backend = "podman" so that all OCI
# container services on this system use Podman as the runtime.
{ config, lib, ... }:
let
  cfg = config.vexos.server.podman;
in
{
  options.vexos.server.podman = {
    enable = lib.mkEnableOption "Podman container runtime with Docker API compatibility";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable      = true;
      dockerCompat = true;  # Creates /run/docker.sock (Docker-compat API socket)
      defaultNetwork.settings.dns_enabled = true;  # Inter-container DNS resolution
      autoPrune = {
        enable = true;
        dates  = "weekly";  # Remove unused images/containers weekly
      };
    };

    # Use Podman as the backend for all declarative OCI container services
    # (virtualisation.oci-containers.containers.*).
    virtualisation.oci-containers.backend = "podman";
  };
}
```

### Explanation of each setting

| Setting | Purpose |
|---------|---------|
| `virtualisation.podman.enable = true` | Installs Podman and its runtime dependencies |
| `virtualisation.podman.dockerCompat = true` | Creates `/run/docker.sock` Docker-compat socket; installs a `docker` symlink in PATH |
| `virtualisation.podman.defaultNetwork.settings.dns_enabled = true` | Enables DNS resolution between containers on the default network (required for multi-container stacks) |
| `virtualisation.podman.autoPrune.enable = true` | Enables automatic pruning of unused images and stopped containers |
| `virtualisation.podman.autoPrune.dates = "weekly"` | systemd calendar expression — prunes once per week |
| `virtualisation.oci-containers.backend = "podman"` | Instructs NixOS to use `podman run` for all OCI container services |

---

## 6. Implementation: `modules/server/dockhand.nix`

```nix
# modules/server/dockhand.nix
# Dockhand — container management UI that speaks the Docker API.
# Deployed as an OCI container backed by Podman. Mounts the Podman
# Docker-compat socket so Dockhand can manage containers on this host.
#
# Prerequisites:
#   vexos.server.podman.enable = true   (enforced by assertion below)
#
# Default access:  http://<host-ip>:3000
# On first launch: authentication is DISABLED — go to Settings > Authentication
#                  immediately after first access to secure the instance.
#
# Data is stored at vexos.server.dockhand.dataDir (default /var/lib/dockhand).
# Using matching paths (host path == container path) so compose stacks with
# relative volume bind mounts work correctly.
{ config, lib, ... }:
let
  cfg = config.vexos.server.dockhand;
in
{
  options.vexos.server.dockhand = {
    enable = lib.mkEnableOption "Dockhand container management UI";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 3000;
      description = "Host port on which Dockhand listens.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/dockhand";
      description = ''
        Host directory for Dockhand persistent data (SQLite database, compose
        stack definitions, Git repository clones).
        Uses matching paths: this directory is mounted at the same absolute
        path inside the container and DATA_DIR is set accordingly.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.vexos.server.podman.enable;
        message   = "vexos.server.dockhand.enable requires vexos.server.podman.enable = true. Enable Podman first.";
      }
    ];

    # Ensure the data directory exists with correct permissions before the
    # container service starts.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
    ];

    virtualisation.oci-containers.containers.dockhand = {
      image     = "fnsys/dockhand:latest";
      autoStart = true;

      # Expose Dockhand on the configured host port.
      ports = [ "0.0.0.0:${toString cfg.port}:3000" ];

      # Mount the Podman Docker-compat socket (created by dockerCompat = true)
      # and the persistent data directory using matching paths.
      volumes = [
        "/run/docker.sock:/var/run/docker.sock"  # Docker-compat Podman socket
        "${cfg.dataDir}:${cfg.dataDir}"          # Matching-path persistent data
      ];

      environment = {
        DATA_DIR = cfg.dataDir;
      };

      # Run as root to avoid Docker group GID-matching complexity.
      # Acceptable for home-lab environments per Dockhand official docs.
      # See: https://dockhand.pro/manual/#docker-socket-permissions
      user = "0:0";
    };

    # Open the firewall for Dockhand's web UI.
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

## 7. Correct Volume Mounts (canonical reference)

```nix
volumes = [
  "/run/docker.sock:/var/run/docker.sock"   # Docker-compat Podman socket
  "${cfg.dataDir}:${cfg.dataDir}"           # Matching-path data directory
];
```

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `/run/docker.sock` | `/var/run/docker.sock` | Podman Docker-compat socket; Dockhand uses this to manage containers |
| `/var/lib/dockhand` (default) | `/var/lib/dockhand` | Persistent data: SQLite DB, stacks, Git repos |

---

## 8. Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `DATA_DIR` | `cfg.dataDir` | Tells Dockhand where its data directory is (matching path) |

Optional variables (not set by default — can be added by the operator via
`server-services.nix` by overriding the container definition):

| Variable | Notes |
|----------|-------|
| `ENCRYPTION_KEY` | Base64 AES-256 key; if unset, key auto-generated and stored in `$DATA_DIR/.encryption_key` |
| `HOST_DATA_DIR` | Only needed if auto-detection of host data path fails (not needed with matching paths) |
| `SKIP_DF_COLLECTION` | Set `true` to disable slow disk-usage collection on NAS/ZFS |

---

## 9. `modules/server/default.nix` — Changes Required

Add two new entries to the `imports` list under the **Container Runtime** section:

```nix
# ── Container Runtime ────────────────────────────────────────────────────
./docker.nix
./podman.nix    # ← ADD
./dockhand.nix  # ← ADD (after podman.nix)
```

The full updated imports section:

```nix
imports = [
  # ── Container Runtime ────────────────────────────────────────────────────
  ./docker.nix
  ./podman.nix
  ./dockhand.nix
  # ── Media Servers ────────────────────────────────────────────────────────
  ...
```

---

## 10. Firewall Ports

| Module | Port | Protocol | Purpose |
|--------|------|----------|---------|
| `dockhand.nix` | `cfg.port` (default 3000) | TCP | Dockhand web UI |

Opened via `networking.firewall.allowedTCPPorts = [ cfg.port ]` in `dockhand.nix`.

No additional ports are required for Podman itself in this configuration.

---

## 11. Assertions

| Module | Assertion | Message |
|--------|-----------|---------|
| `dockhand.nix` | `config.vexos.server.podman.enable == true` | `"vexos.server.dockhand.enable requires vexos.server.podman.enable = true. Enable Podman first."` |

No assertions are needed in `podman.nix` — Podman has no required configuration
values that lack sensible defaults.

---

## 12. Container Image Details

| Property | Value |
|----------|-------|
| Image | `fnsys/dockhand:latest` |
| Registry | Docker Hub |
| Container port | 3000 |
| Default data path (in container) | `/app/data` (overridden via `DATA_DIR`) |
| Socket path (in container) | `/var/run/docker.sock` |
| Database | SQLite (default); PostgreSQL supported via `DATABASE_URL` env var |
| Memory minimum | 512 MB |
| First-launch auth | **Disabled by default** — must be enabled immediately |

---

## 13. Activation Pattern for Operators

To enable both services, add to `/etc/nixos/server-services.nix`:

```nix
{ config, ... }:
{
  vexos.server.podman.enable   = true;
  vexos.server.dockhand.enable = true;
  # Optional overrides:
  # vexos.server.dockhand.port    = 3000;
  # vexos.server.dockhand.dataDir = "/var/lib/dockhand";
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#vexos-server-amd
```

Access Dockhand at `http://<host-ip>:3000`. On first access, navigate to
**Settings → Authentication** to create an admin user.

---

## 14. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **Docker + Podman conflict**: both `vexos.server.docker.enable` and `vexos.server.podman.enable` set to `true` | Low | Docker daemon and Podman coexist (different sockets); OCI containers backend will use Podman; Docker daemon runs idle. Document in module header. |
| **Socket not present at boot**: `/run/docker.sock` not created before Dockhand container starts | Medium | `virtualisation.podman.dockerCompat = true` creates the `docker.socket` systemd unit. The NixOS oci-containers service generator adds `After=docker.socket` automatically for Podman backend. Verify with `systemctl status podman-dockhand.service` post-deploy. |
| **Dockhand port exposed without authentication**: default install has auth disabled | High | Document prominently in module comment: "On first launch, authentication is DISABLED". Operator must enable it immediately. |
| **Data directory permissions**: `/var/lib/dockhand` owned by root, container runs as root | Low | `systemd.tmpfiles.rules` creates directory as `0700 root root`. Container runs as root, has full access. |
| **Image tag `:latest` drift**: `fnsys/dockhand:latest` may change API compatibility | Low | Podman autoPrune removes old images weekly. Use `HOST_DOCKER_SOCKET` env override if detection fails after image update. |
| **AppArmor profile**: rootful Podman containers on NixOS with AppArmor may need profile adjustments | Low-Medium | NixOS includes a default AppArmor profile for containers. `user = "0:0"` avoids most AppArmor-rooted permission issues. Test with `podman logs dockhand` if container fails to start. |
| **Dockhand runs as root (security)**: anyone with Dockhand access has Docker-root-equivalent | Medium | Acceptable for home-lab per upstream docs. Mitigate by: (a) keeping Dockhand on LAN only, (b) enabling Dockhand authentication immediately, (c) using Headscale/Tailscale VPN for remote access. |
| **ZFS + rootful Podman overlay storage**: ZFS dataset without POSIX ACL may fail | Low | Per NixOS Podman wiki: ZFS needs `acltype=posixacl` on the storage dataset. Document in module comment. Only relevant for hosts with ZFS root. |
| **`vexos.user.name` not required**: unlike `docker.nix`, no user group add | N/A | Rootful Podman runs as root; no group membership required. Dockhand accesses socket as root. |

---

## 15. Out of Scope

The following are explicitly **not** part of this implementation:

- `configuration-server.nix` — no changes needed (server module loaded via import)
- `configuration-headless-server.nix` — no changes needed (same reason)
- `flake.nix` — no new flake inputs required (Dockhand runs as a container image, not a Nix package)
- Reverse proxy configuration for Dockhand (operator concern, not a module default)
- HTTPS/TLS termination for Dockhand (operator concern)
- PostgreSQL database for Dockhand (SQLite default is sufficient for home-lab)
- Dockhand ENCRYPTION_KEY secret management (operator should use `secrets-sops.nix`)

---

## 16. Validation Checklist (for Review Phase)

- [ ] `nix flake check` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds (no regression)
- [ ] Neither `podman.nix` nor `dockhand.nix` contains `lib.mkIf` guards that gate content by role or display flag
- [ ] `dockhand.nix` does NOT contain any `virtualisation.podman.*` settings
- [ ] `podman.nix` does NOT contain any `virtualisation.oci-containers.containers.dockhand` settings
- [ ] `modules/server/default.nix` imports list updated with `./podman.nix` and `./dockhand.nix`
- [ ] No changes to `configuration-server.nix`, `configuration-headless-server.nix`, or `flake.nix`
- [ ] `hardware-configuration.nix` is NOT committed to the repository
- [ ] `system.stateVersion` is unchanged in all configuration files

---

*Spec written by: Research & Specification Agent*  
*Phase 1 of the vexos-nix standard workflow*

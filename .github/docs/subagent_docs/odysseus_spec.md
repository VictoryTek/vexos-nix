# Odysseus Service — Phase 1 Specification

## Current State Analysis

The vexos-nix project provides 56+ server service modules under `modules/server/`, each
exposing a `vexos.server.<service>.enable` NixOS option. Services are activated by setting
the flag in `/etc/nixos/server-services.nix`, which is managed by `just enable <service>`
and `just disable <service>`.

The project already has:
- `modules/server/kiji-proxy.nix` — AI API proxy under the "AI & Privacy" category
- `modules/server/ntfy.nix` — push notification server (port 2586)
- Docker support via `virtualisation.docker.enable` (used by homepage, authelia, etc.)
- A `lib.fakeHash` + auto-patch pattern in `just enable` for services that require
  hash computation at enable time (see kiji-proxy pattern)

No AI workspace or chat interface module exists yet.

---

## Problem Definition

The user wants to add **Odysseus** (`https://github.com/pewdiepie-archdaemon/odysseus`)
as an opt-in server service, wired into `just enable odysseus` and `just enable`.

Odysseus is a self-hosted AI workspace — a local-first alternative to ChatGPT and Claude.
It supports local models (Ollama, llama.cpp, vLLM) and remote APIs (OpenAI, GitHub Copilot).

Key challenges:
1. No published Docker Hub / GHCR image — must build from source
2. Requires 3 companion services: **ChromaDB** (vector memory), **SearXNG** (web search)
3. Companion services must share a private Docker network with the main app
4. Source must be pinned in the Nix store (deterministic builds); hash computed at enable time

---

## Proposed Solution Architecture

### Approach: Docker Compose stack via systemd oneshot service

Rationale:
- Upstream ships a `docker-compose.yml` and `Dockerfile`; no nixpkgs package exists
- 3 services need to communicate on a private Docker network (`depends_on`, health checks)
- `virtualisation.oci-containers` does not support inter-container `depends_on` or shared
  networks without manual `extraOptions`, making raw OCI containers awkward for this stack
- Docker Compose is the upstream-supported deployment method

### Service composition

| Container  | Image                    | Purpose                       | Exposure       |
|------------|--------------------------|-------------------------------|----------------|
| odysseus   | built from Nix store src | FastAPI AI workspace app      | host:7000      |
| chromadb   | chromadb/chroma:latest   | Vector memory (embeddings)    | internal only  |
| searxng    | searxng/searxng:2026.5.31| Web search backend            | internal only  |

- ntfy is **not** included in the compose stack; the existing `ntfy.nix` module (port 2586)
  handles notifications if the user also enables that service. Odysseus can be pointed to it
  via its settings UI after first login.
- All three containers run on a named Docker Compose network (`odysseus_default`)

### Source pinning

```nix
pkgs.fetchFromGitHub {
  owner = "pewdiepie-archdaemon";
  repo  = "odysseus";
  rev   = "73673258199b353f9b3e04da9b37ae95077e2c8b";  # 2026-06-05
  hash  = lib.fakeHash;  # auto-patched by `just enable odysseus`
}
```

The `lib.fakeHash` placeholder is used because the hash cannot be computed without a
running Nix environment. The `just enable odysseus` recipe auto-patches it via
`nix-prefetch-url --unpack`, exactly as the kiji-proxy module does.

Because `odysseusSource` and the generated compose file are defined inside
`config = lib.mkIf cfg.enable ( let ... in { ... } )`, Nix's lazy evaluation ensures
the `fetchFromGitHub` derivation is only instantiated when the service is enabled — so
`lib.fakeHash` does not affect disabled configurations.

### Generated Docker Compose file

A `pkgs.writeText`-generated compose file is placed in the Nix store. It uses:
- Absolute build context path: `${odysseusSource}` (Nix store path)
- Absolute volume paths: `${cfg.dataDir}/data`, `${cfg.dataDir}/logs`, etc.
- Configured environment variables from NixOS options

This avoids any dependency on `--project-directory` path resolution, making the
service fully declarative and path-safe.

### SearXNG initialization

SearXNG requires a `settings.yml` with a secret key. The `preStart` script generates
this file on first start if absent. On subsequent starts the existing file is preserved.

---

## Implementation Steps

1. Create `modules/server/odysseus.nix` with:
   - Options: `enable`, `port` (default 7000), `dataDir`, `authEnabled`
   - `pkgs.fetchFromGitHub` + `pkgs.writeText` inside `lib.mkIf cfg.enable` (lazy)
   - `systemd.services.odysseus` (oneshot + RemainAfterExit)
   - `preStart` that creates directories and generates SearXNG settings.yml
   - `virtualisation.docker.enable = lib.mkDefault true`
   - `networking.firewall.allowedTCPPorts = [ cfg.port ]`

2. Add `./odysseus.nix` to `modules/server/default.nix` under "AI & Privacy"

3. Add commented-out entry to `template/server-services.nix` under "AI & Privacy"

4. Update `Justfile` at 5 locations:
   a. `_server_service_names`: append `odysseus`
   b. `available-services`: add `_svc odysseus` under "AI & Privacy"
   c. `_info` function in `service-info`: add `odysseus)` case
   d. `status` recipe case: map `odysseus` → unit `odysseus`, URL `http://localhost:7000`
   e. `enable` recipe case: add `odysseus)` with hash auto-patch + post-enable info

---

## Dependencies

- `pkgs.docker-compose` — standalone docker-compose v2 binary for ExecStart/ExecStop
- `pkgs.openssl` — for generating SearXNG secret key in preStart
- `pkgs.fetchFromGitHub` — for pinning Odysseus source
- `pkgs.writeText` — for generating the compose file as a Nix store artifact
- Docker daemon (`virtualisation.docker.enable`) — required at runtime

No new flake inputs required. No Context7 lookup needed (pure Nix/internal change with
no new flake dependencies).

---

## Configuration Changes

### New option namespace: `vexos.server.odysseus`

| Option       | Type    | Default            | Description                              |
|--------------|---------|--------------------|------------------------------------------|
| `enable`     | bool    | false              | Enable Odysseus AI workspace             |
| `port`       | port    | 7000               | Host port for the web UI                 |
| `dataDir`    | str     | /var/lib/odysseus  | Persistent data directory                |
| `authEnabled`| bool    | true               | Enable login authentication              |

---

## Build / Test Commands for Phase 3

RAM-safe validation (per CLAUDE.md constraints):
```bash
nix flake show
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
```

The `lib.fakeHash` means the `fetchFromGitHub` derivation will fail to build if
`vexos.server.odysseus.enable = true` in `server-services.nix`. The dry-build
targets above have odysseus **disabled** (default), so the fakeHash is never
instantiated and dry-builds succeed.

Do NOT use `nix flake check` — causes OOM on this 32 GB machine.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| lib.fakeHash causes dry-build failure | Only instantiated when enabled; dry-builds test with it disabled |
| Docker image build takes 5-10 min on first start | Document in enable output; TimeoutStartSec = 600 |
| SearXNG image pin (2026.5.31) may become unavailable | Pinned for reproducibility; easy to update rev |
| Port 7000 conflicts with another service | `port` option allows override |
| chromadb/searxng on different Docker networks | Compose stack puts all containers on same project network |
| ntfy port conflict (Odysseus wants 8091, vexos uses 2586) | ntfy excluded from compose stack; user can configure via Odysseus settings UI |

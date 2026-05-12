# kiji-proxy — Phase 1: Research & Specification

**Feature:** Package and integrate `kiji-proxy` as a server service in the vexos-nix NixOS flake.
**Date:** 2026-05-12
**Spec path:** `.github/docs/subagent_docs/kiji-proxy_spec.md`

---

## 1. Current State Analysis

### Files to create (net-new)
| File | Purpose |
|---|---|
| `pkgs/kiji-proxy/default.nix` | Nix derivation fetching the upstream pre-built tarball |
| `modules/server/kiji-proxy.nix` | NixOS service module (`vexos.server.kiji-proxy`) |

### Files to modify
| File | Change |
|---|---|
| `pkgs/default.nix` | Add `kiji-proxy = final.callPackage ./kiji-proxy { };` to the `vexos` attrset |
| `modules/server/default.nix` | Add `./kiji-proxy.nix` import under a new `── AI & Privacy` section |

### Existing patterns observed
- **Package overlay** (`pkgs/default.nix`): flat `final: prev:` overlay; all custom packages under `vexos.*`.
- **Pre-built binary packages**: `cockpit-file-sharing` and `cockpit-identities` use `fetchurl` + `dpkg` to extract pre-built static assets. `kiji-proxy` is the first derivation that wraps a pre-built ELF binary requiring ELF patching.
- **Service modules** (`modules/server/*.nix`): all follow `{ config, lib, pkgs, ... }` with `options.vexos.server.<name>` and `config = lib.mkIf cfg.enable { ... }`.
- **Raw systemd services**: `modules/server/seerr.nix` is the reference pattern — it uses `systemd.services.<name>` with `serviceConfig`.
- **LD_LIBRARY_PATH override**: `modules/server/plex.nix` shows how to set `systemd.services.<name>.environment.LD_LIBRARY_PATH` for a service that needs a custom library path.
- **Server default.nix** ends at line 77 with a `Virtualisation` section; kiji-proxy will be inserted as a new `── AI & Privacy` section just before `Virtualisation`.

---

## 2. Problem Definition

`kiji-proxy` ships as a pre-built Linux tarball containing:

- `bin/kiji-proxy` — Go binary compiled with CGO, embeds an ONNX model (~60–90 MB)
- `lib/libonnxruntime.so.1.24.2` — bundled ONNX Runtime C++ shared library (~24 MB)
- `run.sh` — launcher that sets `LD_LIBRARY_PATH` (used on non-NixOS systems)
- `kiji-proxy.service` — upstream systemd unit example (not used directly)

On NixOS, pre-built ELF binaries fail to run because:
1. The ELF interpreter (`/lib64/ld-linux-x86-64.so.2`) does not exist at that path.
2. The RPATH inside the binary points to the original build system's library paths (e.g. `/opt/kiji-privacy-proxy/lib`), not the Nix store.

Both problems are solved by `autoPatchelfHook`, which rewrites the ELF interpreter and RPATH during the Nix build phase.

---

## 3. Proposed Solution Architecture

### 3.1 Package derivation (`pkgs/kiji-proxy/default.nix`)

**Strategy:** `stdenv.mkDerivation` + `fetchurl` + `autoPatchelfHook`

- `fetchurl` downloads and unpacks the tarball.
- `autoPatchelfHook` (in `nativeBuildInputs`) rewrites:
  - The ELF interpreter of `bin/kiji-proxy` and `lib/libonnxruntime.so.1.24.2` to the Nix glibc interpreter.
  - The RPATH to include `$out/lib` (so `kiji-proxy` finds `libonnxruntime.so.1.24.2` at runtime) and paths from `buildInputs` (so `libonnxruntime` finds `libstdc++`).
- `stdenv.cc.cc.lib` in `buildInputs` provides `libstdc++.so.6` and `libgcc_s.so.1`, which the ONNX Runtime C++ library requires.
- `lib.fakeHash` is used as the tarball hash placeholder; the real hash must be obtained before building (see §6).

**Tarball layout assumption:**  
The tarball `kiji-privacy-proxy-1.0.0-linux-amd64.tar.gz` is expected to extract to a single top-level directory `kiji-privacy-proxy-1.0.0-linux-amd64/` with `bin/` and `lib/` subdirectories. Nix's default `unpackPhase` will `cd` into that directory, making `bin/kiji-proxy` directly reachable in `installPhase`. If the tarball has a different root directory name, set `sourceRoot` accordingly.

### 3.2 Service module (`modules/server/kiji-proxy.nix`)

**Options:**
| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | `bool` | `false` | Enable the service |
| `port` | `port` | `8080` | HTTP proxy / API / health port |
| `environmentFile` | `str` | `""` | Path to env file (e.g. `/etc/nixos/secrets/kiji-proxy.env`); omitted if empty |

**Service design:**
- Dedicated system user `kiji-proxy` (non-login, no home directory needed).
- `systemd.services.kiji-proxy` with `Type = "simple"`, `Restart = "on-failure"`, `RestartSec = "5s"`.
- `ExecStart` references `${pkgs.vexos.kiji-proxy}/bin/kiji-proxy` (Nix store path).
- `Environment` sets `LD_LIBRARY_PATH` (belt-and-suspenders alongside the patched RPATH) and `PROXY_PORT` from `cfg.port`.
- `EnvironmentFile` is conditionally included via `lib.optionalAttrs` when `cfg.environmentFile != ""`.
- Firewall opens `cfg.port` (TCP).

> **Note on port 8081:** `kiji-proxy` also binds a transparent MITM HTTPS proxy on port 8081. This port is not configurable via environment variables and is always opened by the binary. Users who need HTTPS proxy support must add port 8081 to `networking.firewall.allowedTCPPorts` in their host config. It is intentionally omitted here to keep the module minimal and consistent with the task specification.

---

## 4. Complete Implementation Plan

### File 1 — `pkgs/kiji-proxy/default.nix` (create)

```nix
# pkgs/kiji-proxy/default.nix
# Kiji Privacy Proxy — PII-masking reverse proxy for AI API requests.
# Ships as a pre-built Go/CGO binary with a bundled ONNX Runtime shared
# library (~60–90 MB binary + ~24 MB libonnxruntime).
#
# autoPatchelfHook patches the ELF interpreter and RPATH so that:
#   • kiji-proxy finds libonnxruntime.so.1.24.2 in $out/lib (intra-package)
#   • libonnxruntime finds glibc/libstdc++ from the Nix stdenv
#
# Hash placeholder: replace lib.fakeHash after running:
#   nix-prefetch-url --unpack \
#     https://github.com/dataiku/kiji-proxy/releases/download/v1.0.0/kiji-privacy-proxy-1.0.0-linux-amd64.tar.gz
{ lib, stdenv, fetchurl, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname = "kiji-proxy";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/dataiku/kiji-proxy/releases/download/v${version}/kiji-privacy-proxy-${version}-linux-amd64.tar.gz";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # libstdc++/libgcc_s for the ONNX Runtime C++ dependencies;
  # glibc is provided implicitly by stdenv.
  buildInputs = [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib"

    install -m 755 bin/kiji-proxy                    "$out/bin/kiji-proxy"
    install -m 644 lib/libonnxruntime.so.1.24.2      "$out/lib/libonnxruntime.so.1.24.2"

    # Provide the unversioned symlink so the dynamic linker can resolve
    # NEEDED entries that reference libonnxruntime.so (without version suffix).
    ln -s libonnxruntime.so.1.24.2                   "$out/lib/libonnxruntime.so"

    runHook postInstall
  '';

  meta = with lib; {
    description = "PII-masking reverse proxy for AI API requests (OpenAI, Anthropic, etc.)";
    homepage    = "https://github.com/dataiku/kiji-proxy";
    # Verify upstream license at: https://github.com/dataiku/kiji-proxy/blob/main/LICENSE
    license     = licenses.asl20;
    platforms   = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}
```

---

### File 2 — `modules/server/kiji-proxy.nix` (create)

```nix
# modules/server/kiji-proxy.nix
# Kiji Privacy Proxy — PII-masking reverse proxy for AI API requests.
# Intercepts requests to AI providers (OpenAI, Anthropic, etc.), masks PII
# using a local ONNX ML model, and restores it in responses.
#
# Default ports:
#   8080 — forward HTTP proxy + REST API + health endpoint (/health)
#   8081 — transparent MITM HTTPS proxy (always bound; open firewall manually if needed)
#
# Secrets file (environmentFile) may contain any of:
#   OPENAI_API_KEY=<key>
#   LOG_PII_CHANGES=true
#
# Example host config:
#   vexos.server.kiji-proxy = {
#     enable          = true;
#     environmentFile = "/etc/nixos/secrets/kiji-proxy.env";
#   };
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.kiji-proxy;
in
{
  options.vexos.server.kiji-proxy = {
    enable = lib.mkEnableOption "Kiji Privacy Proxy PII-masking AI proxy";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8080;
      description = "HTTP proxy / API / health endpoint port (PROXY_PORT).";
    };

    environmentFile = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = ''
        Path to a file containing environment variable overrides, e.g.:
          OPENAI_API_KEY=sk-...
          LOG_PII_CHANGES=true
        If empty, no EnvironmentFile is passed to the service.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    users.users.kiji-proxy = {
      isSystemUser = true;
      group        = "kiji-proxy";
      description  = "kiji-proxy service user";
    };
    users.groups.kiji-proxy = { };

    systemd.services.kiji-proxy = {
      description = "Kiji Privacy Proxy — PII-masking AI API proxy";
      after       = [ "network.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig = {
        Type           = "simple";
        User           = "kiji-proxy";
        Group          = "kiji-proxy";
        ExecStart      = "${pkgs.vexos.kiji-proxy}/bin/kiji-proxy";
        Environment    = [
          "LD_LIBRARY_PATH=${pkgs.vexos.kiji-proxy}/lib"
          "PROXY_PORT=:${toString cfg.port}"
        ];
        Restart        = "on-failure";
        RestartSec     = "5s";
        StandardOutput = "journal";
        StandardError  = "journal";
      } // lib.optionalAttrs (cfg.environmentFile != "") {
        EnvironmentFile = cfg.environmentFile;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

---

### File 3 — `pkgs/default.nix` (modify)

Add one line to the `vexos` attrset:

**Before:**
```nix
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };  # Phase D
  };
```

**After:**
```nix
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };  # Phase D
    kiji-proxy           = final.callPackage ./kiji-proxy { };
  };
```

---

### File 4 — `modules/server/default.nix` (modify)

Add a new section just before `# ── Virtualisation`:

**Before:**
```nix
    # ── PDF Tools ────────────────────────────────────────────────────────────
    ./stirling-pdf.nix
    # ── Virtualisation ────────────────────────────────────────────────────────────
    ./proxmox.nix
```

**After:**
```nix
    # ── PDF Tools ────────────────────────────────────────────────────────────
    ./stirling-pdf.nix
    # ── AI & Privacy ─────────────────────────────────────────────────────────
    ./kiji-proxy.nix
    # ── Virtualisation ────────────────────────────────────────────────────────────
    ./proxmox.nix
```

---

## 5. Files to Create / Modify

| Action | Path |
|---|---|
| **Create** | `pkgs/kiji-proxy/default.nix` |
| **Create** | `modules/server/kiji-proxy.nix` |
| **Modify** | `pkgs/default.nix` |
| **Modify** | `modules/server/default.nix` |

---

## 6. Obtaining the Real Tarball Hash

`lib.fakeHash` is a placeholder that intentionally causes `nix build` to fail with a hash-mismatch error that prints the correct hash. After implementation, obtain the real hash with:

```bash
nix-prefetch-url --unpack \
  https://github.com/dataiku/kiji-proxy/releases/download/v1.0.0/kiji-privacy-proxy-1.0.0-linux-amd64.tar.gz
```

The output will be a base32 SHA-256 hash. Convert it to the `sha256-<base64>=` SRI format and replace `lib.fakeHash` in `pkgs/kiji-proxy/default.nix`.

Alternatively, the upstream checksum file at:
```
https://github.com/dataiku/kiji-proxy/releases/download/v1.0.0/kiji-privacy-proxy-1.0.0-linux-amd64.tar.gz.sha256
```
contains a raw SHA-256 hex digest. Convert with:
```bash
echo "<hex-digest>  -" | sha256sum --check  # verify
nix hash convert --hash-algo sha256 --to sri <hex-digest>
```

---

## 7. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Tarball top-level directory name differs from assumption | If `installPhase` fails with "no such file", set `sourceRoot = "kiji-privacy-proxy-${version}-linux-amd64";` in the derivation |
| Binary requires additional shared libraries not covered by `stdenv.cc.cc.lib` | Build failure from `autoPatchelfHook` will list missing libraries; add corresponding nixpkgs packages to `buildInputs` |
| `autoPatchelfHook` does not auto-discover `$out/lib` for intra-package deps | Belt-and-suspenders `LD_LIBRARY_PATH` in the systemd service covers this; RPATH patching is primary, env var is fallback |
| Upstream license is not Apache 2.0 | `meta.license` in the derivation has a comment directing verification at the GitHub LICENSE file |
| Port 8081 (HTTPS MITM proxy) is blocked by firewall | Documented in module header; users add `networking.firewall.allowedTCPPorts = [ 8081 ];` to their host config |
| `kiji-proxy.service` is x86_64 only | `meta.platforms = [ "x86_64-linux" ]` prevents accidental use on aarch64 or other arches |

---

## 8. Dependencies

| Dependency | Source | Purpose |
|---|---|---|
| `autoPatchelfHook` | nixpkgs (`nativeBuildInputs`) | Rewrites ELF interpreter + RPATH for NixOS |
| `stdenv.cc.cc.lib` | nixpkgs (`buildInputs`) | Provides `libstdc++.so.6`, `libgcc_s.so.1` for ONNX Runtime |
| `fetchurl` | nixpkgs built-in | Downloads pre-built tarball from GitHub Releases |
| `pkgs.vexos.kiji-proxy` | this overlay | Referenced by service module at runtime |

No new flake inputs are required. All dependencies are available from the existing `nixpkgs` pin.

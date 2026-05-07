# Spec: Fix `services.atticd.credentialsFile` → `services.atticd.environmentFile`

## Current State of `modules/server/attic.nix`

The file configures the Attic binary-cache daemon. The relevant broken section:

```nix
config = lib.mkIf cfg.enable {
  services.atticd = {
    enable = true;
    credentialsFile = "/etc/nixos/secrets/attic-credentials";   # ← BROKEN
    settings = {
      listen = "[::]:${toString cfg.port}";
      database.url = "sqlite://${cfg.dataDir}/db.sqlite?mode=rwc";
      storage = {
        type = "local";
        path = "${cfg.dataDir}/storage";
      };
      chunking = { … };
    };
  };
  networking.firewall.allowedTCPPorts = [ cfg.port ];
};
```

The header comment also references the old environment variable name:

```nix
# Requires: /etc/nixos/secrets/attic-credentials containing:
#   ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=<secret>
# Generate secret with: openssl rand -base64 32
```

---

## Error and Root Cause

### Error

```
error: The option `services.atticd.credentialsFile' does not exist. Definition values:
- In `/nix/store/…-source/modules/server/attic.nix':
    {
      _type = "if";
      condition = false;
      content = "/etc/nixos/secrets/attic-credentials";
    }
```

### Root Cause

The nixpkgs 25.11 attic NixOS module no longer exposes `services.atticd.credentialsFile`.
The option was renamed to `services.atticd.environmentFile`.

The attic upstream module (`nixos/atticd.nix` on GitHub) explicitly declares:

```nix
imports = [
  (lib.mkRenamedOptionModule
    [ "services" "atticd" "credentialsFile" ]
    [ "services" "atticd" "environmentFile" ])
];
```

This rename shim exists in the *attic flake's own module*, but the `vexos-nix` flake does
**not** include attic as a flake input — it relies on the attic module bundled inside
nixpkgs. The nixpkgs 25.11 bundled module only exposes `environmentFile`; it does not
include the backward-compat shim, so using `credentialsFile` is a hard error.

The `_type = "if" / condition = false` wrapper in the error is caused by `lib.mkIf
cfg.enable` evaluating to a conditional that NixOS still type-checks even when the
condition is false, exposing the invalid option name.

### Secondary Issue: Outdated token format in the comment

The module comment instructs users to generate `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64`
with `openssl rand -base64 32` (symmetric HS256). The upstream attic module has since
switched to RS256 asymmetric tokens:

- **New required env var:** `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`
- **New generation command:** `openssl genrsa -traditional 4096 | base64 -w0`

The assertion inside the upstream module now reads:

```nix
{
  assertion = cfg.environmentFile != null;
  message = ''
    <option>services.atticd.environmentFile</option> is not set.
    Run `openssl genrsa -traditional -out private_key.pem 4096 | base64 -w0`
    and create a file with the following contents:
      ATTIC_SERVER_TOKEN_RS256_SECRET="output from command"
    Then, set `services.atticd.environmentFile` to the quoted absolute path of the file.
  '';
}
```

The comment should be updated to guide operators correctly.

---

## Correct Current Option

| Old (broken) option          | New (correct) option            |
|------------------------------|---------------------------------|
| `services.atticd.credentialsFile` | `services.atticd.environmentFile` |

**Type:** `types.nullOr types.path`  
**Default:** `null` (but an assertion fires if it remains null when atticd is enabled)  
**Constraint:** Must **not** be a path inside the Nix store (a second assertion enforces this). `/etc/nixos/secrets/attic-credentials` satisfies this constraint.

---

## Exact Changes Required

### File: `modules/server/attic.nix`

Only one file needs changing.

#### Change 1 — Option rename in `config` block

Replace:
```nix
    credentialsFile = "/etc/nixos/secrets/attic-credentials";
```

With:
```nix
    environmentFile = "/etc/nixos/secrets/attic-credentials";
```

#### Change 2 — Update header comment to reflect RS256 tokens

Replace:
```nix
# Requires: /etc/nixos/secrets/attic-credentials containing:
#   ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=<secret>
# Generate secret with: openssl rand -base64 32
```

With:
```nix
# Requires: /etc/nixos/secrets/attic-credentials containing:
#   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64-encoded RSA PEM PKCS1>
# Generate secret with: openssl genrsa -traditional 4096 | base64 -w0
```

---

## Implementation Steps

1. Open `modules/server/attic.nix`.
2. Apply Change 1: rename `credentialsFile` → `environmentFile` in the `services.atticd` attribute set.
3. Apply Change 2: update the header comment to reflect the RS256 token format.
4. Save the file.
5. Run `nix flake check` to confirm evaluation succeeds.
6. Run `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` (or whichever server variant) to confirm the system closure builds.

---

## No Other Files Require Changes

- No other module sets `services.atticd.credentialsFile`.
- The `modules/server/default.nix` import list does not need modification.
- No host file sets this option directly.

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Existing operator has credentials file using old HS256 variable name | Document in comment that the env var name changed; operator must regenerate credentials with RS256 before redeploying |
| `environmentFile = null` assertion fires if the path is absent on the host | Path `/etc/nixos/secrets/attic-credentials` must exist on the server host before enabling; unchanged from previous requirement |
| Nix store path assertion fires | Value is `/etc/nixos/secrets/…` which is not a store path; no issue |

---

## Summary

- **Root cause:** `services.atticd.credentialsFile` was removed from the nixpkgs 25.11
  attic NixOS module; the correct option is `services.atticd.environmentFile`.
- **Only file modified:** `modules/server/attic.nix`
- **Scope of change:** One option rename + one comment update.
- **No architectural rule violations:** The change is contained within a single server
  module; no `lib.mkIf` role guards are introduced.

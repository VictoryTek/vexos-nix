# Spec: vexboard secret file format bug — VEXBOARD_AUTH__SECRET not set at startup

## Current State Analysis

The upstream vexboard NixOS module (`inputs.vexboard.nixosModules.vexboard`, evaluated path
`/nix/store/v5qg5d6xshy7gs826ak7cmmslzc3ynbd-module.nix`) loads `secretFile` as a systemd
`EnvironmentFile` (line 161 of the upstream module):

```nix
EnvironmentFiles = lib.optional (cfg.secretFile != null) cfg.secretFile;
```

systemd's `EnvironmentFile` format requires each line to be `KEY=VALUE`. The service's
`preStart` script then checks the env var `VEXBOARD_AUTH__SECRET`:

```bash
secret="${VEXBOARD_AUTH__SECRET:-}"
if [ -z "$secret" ] || [ "$secret" = "change-me-in-production" ]; then
  echo "ERROR: VexBoard will not start because no auth secret has been configured." >&2
  exit 1
fi
```

The `just enable <service>` command auto-enables VexBoard and calls `_ensure_vexboard_secret`
(justfile lines 1377–1393) to generate the secret file:

```bash
head -c 48 /dev/urandom | base64 | sudo tee "$secret_path" > /dev/null
```

This writes only the **raw base64 value** — no `KEY=VALUE` structure. When systemd loads this
as an `EnvironmentFile`, it sees a line like `aBcD3F...==` with no `=` before valid content,
or splits at base64 padding `=` characters into nonsense variable names. Either way,
`VEXBOARD_AUTH__SECRET` is never exported, its expansion is empty (`""`), and the pre-start
guard triggers.

The NixOS assertion (`cfg.secretFile != null`) in `modules/server/vexboard.nix` passes
because the path is set. The rebuild activates (seerr starts), but vexboard.service fails
at pre-start.

Secondary issue: `modules/server/vexboard.nix` option description and assertion message
describe incorrect file format — they reference `openssl rand -base64 48 > /path/to/file`
(raw value) rather than `VEXBOARD_AUTH__SECRET=<value>`.

## Problem Definition

`_ensure_vexboard_secret` in the justfile creates a secret file containing only a raw base64
string, but systemd `EnvironmentFile` semantics and the upstream module's pre-start guard
require the file to contain `VEXBOARD_AUTH__SECRET=<value>`.

## Proposed Solution

### Fix 1 — justfile: correct file format written by `_ensure_vexboard_secret`

Change line 1385 from:
```bash
head -c 48 /dev/urandom | base64 | sudo tee "$secret_path" > /dev/null
```
To:
```bash
printf 'VEXBOARD_AUTH__SECRET=%s\n' "$(openssl rand -base64 48)" | sudo tee "$secret_path" > /dev/null
```

This produces a file whose single line is:
```
VEXBOARD_AUTH__SECRET=<random-base64-value>
```

systemd loads this as an `EnvironmentFile`, sets `VEXBOARD_AUTH__SECRET`, and the pre-start
check passes.

### Fix 2 — modules/server/vexboard.nix: correct description and assertion message

Update the `secretFile` option description and assertion error message to match the correct
file format (`VEXBOARD_AUTH__SECRET=<value>`), consistent with the upstream module docs.

## Files to Modify

1. `justfile` — `_ensure_vexboard_secret`, line ~1385
2. `modules/server/vexboard.nix` — `secretFile` option description and assertion message

## No New Dependencies

No new flake inputs, packages, or external libraries. Context7 is not required.

## Out-of-Band Server Action Required

The user's server already has `/etc/nixos/secrets/vexboard-secret` with wrong content.
After applying this fix, the user must re-generate the secret file on the server:

```bash
sudo sh -c 'printf "VEXBOARD_AUTH__SECRET=%s\n" "$(openssl rand -base64 48)" \
  > /etc/nixos/secrets/vexboard-secret && chmod 600 /etc/nixos/secrets/vexboard-secret'
```

Then run `just rebuild` to restart vexboard with the corrected EnvironmentFile.

## Risks and Mitigations

- Risk: existing server has old-format file — mitigated by informing user of the out-of-band
  command above; it is a one-line fix on the server.
- Risk: `openssl` not available in live shell context during `just enable` — openssl is
  standard on NixOS; the prior codebase uses `openssl rand -base64 48` in vexboard.nix docs,
  so it is already expected to be present.
- Risk: base64 output contains newlines on some systems (macOS fold at 76 chars) — on Linux
  `/usr/bin/base64` and openssl both emit a single line for 48 input bytes; verified
  acceptable for NixOS target hosts.

# Spec: vexboard.service always fails to start — VEXBOARD_AUTH__SECRET never loaded

## Current State Analysis

The upstream vexboard NixOS module (`inputs.vexboard.nixosModules.vexboard`, store path
`/nix/store/v5qg5d6xshy7gs826ak7cmmslzc3ynbd-module.nix`) contains a typo on line 161:

```nix
EnvironmentFiles = lib.optional (cfg.secretFile != null) cfg.secretFile;
```

The key is `EnvironmentFiles` (plural). NixOS's `attrsToSection` function in
`nixos/lib/systemd-lib.nix` (line 339) uses the attribute name verbatim:

```nix
attrsToSection = as: concatStrings (concatLists (
  mapAttrsToList (name: value:
    map (x: ''${name}=${toOption x}'') (if isList value then value else [ value ])
  ) as
));
```

So the generated `.service` unit contains:

```
EnvironmentFiles=/etc/nixos/secrets/vexboard-secret
```

systemd only recognizes `EnvironmentFile=` (singular). It silently ignores unrecognized
directives. The file is never loaded. `VEXBOARD_AUTH__SECRET` is never set. The upstream
`preStart` script (run as `ExecStartPre=`) always sees an empty value and exits 1:

```bash
secret="${VEXBOARD_AUTH__SECRET:-}"
if [ -z "$secret" ] || [ "$secret" = "change-me-in-production" ]; then
  echo "ERROR: VexBoard will not start because no auth secret has been configured." >&2
  exit 1
fi
```

This is the root cause of every `vexboard.service` startup failure across all fresh server VMs.

### Secondary issue (already fixed in justfile — commit c4ecaaa)

`_ensure_vexboard_secret` (justfile) now correctly writes `VEXBOARD_AUTH__SECRET=<value>`
format (coreutils-only). That fix is complete and verified.

### Why previous iterations didn't fix it

All prior fixes targeted the secret FILE FORMAT or the generation command. The file was
correct after those fixes. The systemd directive name `EnvironmentFiles` vs `EnvironmentFile`
was not examined until now.

## Problem Definition

The upstream vexboard NixOS module has a typo: `EnvironmentFiles` (plural) in `serviceConfig`.
NixOS passes this key name verbatim to the systemd unit. systemd ignores `EnvironmentFiles=`
as an unknown directive. The secret is never loaded.

## Proposed Solution

In `modules/server/vexboard.nix`, inside `config = lib.mkIf cfg.enable { ... }`, add an
override that injects the CORRECT `EnvironmentFile=` (singular) directive:

```nix
systemd.services.vexboard.serviceConfig.EnvironmentFile =
  lib.optional (cfg.secretFile != null) (toString cfg.secretFile);
```

`lib.optional` returns `[]` if `cfg.secretFile` is null, or `["/path/to/file"]` if set.
`attrsToSection` iterates the list and emits one `EnvironmentFile=<path>` line per item.
`toString` coerces the path/string value to a plain string (no store import).

The upstream's `EnvironmentFiles=<path>` line remains in the unit but is harmless — systemd
ignores it. The new `EnvironmentFile=<path>` line is recognized and the env var is loaded
before ExecStartPre runs.

## Files to Modify

1. `modules/server/vexboard.nix` — add `systemd.services.vexboard.serviceConfig.EnvironmentFile`

## No New Dependencies

No new flake inputs, packages, or external libraries. Context7 is not required.

## Risks and Mitigations

- Risk: upstream module is fixed later — our `EnvironmentFile` override will become
  redundant but not harmful (duplicate `EnvironmentFile=` directives are valid in systemd;
  it applies both in order). At that point the line can be removed.
- Risk: `lib.types.path` check rejects string path at eval time — verified: this nixpkgs
  `pathWith { absolute = true; }` only checks `isStringLike && isAbsolute`, no
  `builtins.pathExists` call, so eval succeeds on any host.
- Risk: sudo cache expiry during `just enable` — this is a separate orthogonal issue that
  the justfile change (writing the file with coreutils) already addresses as the fix; the
  file is written before sudo cache might expire.

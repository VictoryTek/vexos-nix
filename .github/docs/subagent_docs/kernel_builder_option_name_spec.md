# kernel-builder option name mismatch — spec

## Current state analysis

`modules/server/kernel-builder.nix` declares its option tree at
`vexos.server.kernelBuilder` (camelCase — see line 30). Every other server
module keeps its option's leaf attribute name identical to its kebab-case
service id (e.g. `vexos.server.nginx-proxy-manager`, `vexos.server.uptime-kuma`,
`vexos.server.code-server`, `vexos.server.node-red`, `vexos.server.matrix-conduit`,
`vexos.server.stirling-pdf`, `vexos.server.home-assistant`, `vexos.server.kiji-proxy`
all keep the hyphen). `kernelBuilder` is the sole camelCase exception.

`justfile`'s `enable` (line 2087) and `disable` (line 2975) recipes build the
option path generically as:

```sh
OPTION="vexos.server.${SERVICE}.enable"
```

where `SERVICE` is the literal argument the user typed (`kernel-builder`).
For every other service this matches the declared option name. For
`kernel-builder` it produces `vexos.server.kernel-builder.enable`, which does
not exist, so `sudo nixos-rebuild dry-build`/`switch` fails with:

```
error: The option `vexos.server.kernel-builder' does not exist.
Did you mean `vexos.server.kernelBuilder'?
```

## Problem definition

`just enable kernel-builder` writes a nonexistent option name into
`/etc/nixos/server-services.nix`, breaking the next rebuild. Same bug exists
symmetrically in `just disable kernel-builder`.

## Proposed solution

Add a single service-id → option-attribute translation at the top of both the
`enable` and `disable` recipes, applied only for the one known exception, mirroring
the existing special-casing already present for `arr` in those same recipes:

```sh
OPT_NAME="$SERVICE"
[ "$SERVICE" = "kernel-builder" ] && OPT_NAME="kernelBuilder"
OPTION="vexos.server.${OPT_NAME}.enable"
```

This is a minimal, surgical justfile-only change. No Nix module changes —
`kernelBuilder`'s option name in `modules/server/kernel-builder.nix` is
unchanged and correct as-is (renaming it would be a bigger, unrelated
change and camelCase is valid Nix option style).

## Implementation steps

1. In `justfile`, `enable` recipe (~line 2087): translate `kernel-builder` →
   `kernelBuilder` before constructing `OPTION`.
2. In `justfile`, `disable` recipe (~line 2975): same translation.
3. No other recipe constructs this option dynamically (verified via grep for
   `vexos.server.kernel` and `OPTION=` across justfile — only enable/disable
   build it from `$SERVICE`; `_check`/status logic keys off systemd unit
   names, not the Nix option string).

## Dependencies

None — pure shell/justfile fix, no new packages or flake inputs.

## Configuration changes

None to Nix modules. Users who already ran `just enable kernel-builder` before
this fix have a stale `vexos.server.kernel-builder = { enable = true; };` line
in their host's `/etc/nixos/server-services.nix` (not tracked in this repo).
That file must be hand-corrected on the affected host (or re-run
`just disable kernel-builder && just enable kernel-builder` after this fix is
deployed) — this spec's fix only prevents the bug going forward.

## Risks and mitigations

- Risk: hardcoding a single exception is fragile if more camelCase option
  names are introduced later. Mitigation: out of scope for this fix; noted
  as the same pattern already used for `arr`'s special handling.

# DMS Plugin Support Spec

## Current State Analysis

Investigated whether "Omarchy plugins" could be used with this project's
Hyprland+DMS setup. Confirmed (via Omarchy's own architecture docs) that
Omarchy's plugin system is tightly coupled to Omarchy's own bespoke
Quickshell-based shell (`omarchy.bar`, `omarchy-shell` IPC, its own
`manifest.json` contract) — not interoperable with DMS despite both being
built on the Quickshell toolkit.

Separately investigated `ChrisLAS/hyprvibe` (a real Hyprland+DMS-on-NixOS
config referenced by the user) to see how he achieves plugin functionality.
Confirmed he does **not** use Omarchy plugins either — he uses DMS's own
native plugin option, both with two custom-built plugins and several
community ones pulled via `pkgs.fetchFromGitHub`.

Verified directly against our own pinned `inputs.dms` source
(`distro/nix/options.nix`, rev `069ddab041c738236a8910e4c39b65d9628d3018`)
that `programs.dank-material-shell.plugins` already exists as a native
option:

```nix
plugins = lib.mkOption {
  type = types.attrsOf (types.submodule {
    options = {
      enable   = lib.mkOption { type = types.bool; default = true; };
      src      = lib.mkOption { type = types.either types.package types.path; };
      settings = lib.mkOption { type = jsonFormat.type; default = { }; };
    };
  });
  default = { };
};
```

`home/dank-material-shell.nix` currently doesn't reference this option at
all, so it's inert (defaults to `{}`) — functionally present but
undiscoverable without reading the upstream module source.

## Problem Definition

Per user decision: make the existing plugin capability discoverable and
ready to use, without installing any specific plugin yet.

## Proposed Solution

Add a clearly commented, non-functional example block directly beside the
existing `programs.dank-material-shell.settings`/`session` block in
`home/dank-material-shell.nix`, showing the exact attrset shape (mirroring
the pattern verified above and in hyprvibe's `dms.nix`) so a future addition
is a copy/uncomment/edit away — no new option, no new module, no behavior
change.

## Implementation Steps

1. **home/dank-material-shell.nix** — add a comment block after the
   `session = { ... };` line, before the closing `};` of
   `programs.dank-material-shell`, documenting the `plugins.<name> = { src
   = pkgs.fetchFromGitHub {...}; }` pattern with a real (commented-out)
   example, plus a pointer to the community registry
   (`plugins.danklinux.com`) and the DMS plugin-dev docs.

## Dependencies

None. No new flake inputs, no new packages — `plugins` defaults to `{}`.

## Risks and Mitigations

None — this is a documentation-only change (a comment block); no functional
code path is added or altered.

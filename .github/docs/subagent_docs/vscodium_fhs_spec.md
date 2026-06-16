# vscodium-fhs: Add to Development Module

## Current State

`modules/development.nix` manages system-wide developer tooling. The Editor section
currently contains only a comment noting that `vscode-fhs` is managed via Home Manager
(`home-desktop.nix` → `programs.vscode` → `pkgs.unstable.vscode-fhs`). No VSCodium
package is present anywhere in the system configuration.

## Problem Definition

The user wants `vscodium-fhs` (VSCodium wrapped in an FHS sandbox) available
system-wide so it can be used across all roles that import `development.nix`.

`vscodium-fhs` is VSCodium (the MIT-licensed, telemetry-free VS Code fork) pre-wrapped
in a Filesystem Hierarchy Standard (FHS) environment. The FHS wrapper enables extensions
that rely on native binaries (language servers, debuggers, etc.) to work on NixOS without
additional patching.

Confirmed present in stable nixpkgs: `nix eval nixpkgs#vscodium-fhs.name` →
`"codium-1.116.02821"`.

## Proposed Solution

Add `pkgs.vscodium-fhs` to the `environment.systemPackages` list in
`modules/development.nix` under the Editor section, alongside the existing comment
about `vscode-fhs`.

No new modules, no new imports, no conditional logic. Single-line addition.

## Implementation Steps

1. Edit `modules/development.nix`
   - Add `pkgs.vscodium-fhs` under the `# ── Editor ──` block
   - Update the block comment to reflect that both editors are now documented here

### Verify
- `nix flake show --impure` — confirms flake structure is intact
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — confirms package
  resolves without build errors

## Dependencies

- `vscodium-fhs` is in stable `nixpkgs` — no new flake input required

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `vscodium-fhs` unavailable in current nixpkgs pin | Confirmed present via `nix eval` |
| Conflict with `programs.vscode` (vscode-fhs) | No conflict — different packages; one is VSCodium, the other VS Code |
| FHS env overhead on roles that don't need a GUI editor | `development.nix` is explicitly a developer-role module; acceptable |

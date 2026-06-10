# Spec: Add claude-code to development module

## Current State
`modules/development.nix` is the desktop-only development tooling module, imported exclusively
by `configuration-desktop.nix`. It contains editors, language toolchains, containers, and
general dev utilities as system packages.

## Problem
`claude-code` (the Anthropic Claude CLI) is not present in the system packages. The user wants
it available system-wide on desktop roles.

## Package
- nixpkgs attribute: `pkgs.claude-code`
- Added to nixpkgs in 2024; available in NixOS 25.11 (current channel)
- No additional configuration required — it is a standalone CLI tool

## Proposed Solution
Add `pkgs.claude-code` to the `environment.systemPackages` list in `modules/development.nix`
under an "AI tooling" section, alongside other dev utilities.

No new module file is needed: `development.nix` is already scoped to desktop-only via the
import list in `configuration-desktop.nix`. This satisfies the Option B pattern (no
`lib.mkIf` guards; scope is expressed through imports).

## Implementation Steps
1. Edit `modules/development.nix` — add `pkgs.claude-code` in the General dev utilities or
   a new AI tooling subsection

## Risks / Mitigations
- Package name: `claude-code` is the canonical nixpkgs attribute name as of nixpkgs 25.05+.
  If evaluation fails, the fallback is `pkgs.nodePackages.claude` (older packaging) — verify
  with `nix flake show --impure` during Phase 3.
- No additional service configuration, secrets, or follows declarations are required.

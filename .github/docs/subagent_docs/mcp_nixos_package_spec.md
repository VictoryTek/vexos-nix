# mcp-nixos Package — Spec

## Current State Analysis

- `modules/development.nix` gates a set of system-wide development tools behind
  `vexos.features.development.enable` (Option B pattern: single universal file, no
  role-conditional `lib.mkIf` beyond the module's own toggle).
- VSCodium is installed system-wide via `pkgs.vscodium-fhs` in that same module.
- `home-desktop.nix` has `programs.vscode` **commented out** — declarative VSCodium
  settings management was intentionally disabled previously, indicating an existing
  project preference against Nix-managed editor config files that a running tool
  also mutates at runtime.
- `home-desktop.nix` sets `"claudeCode.preferredLocation"` (in the disabled block),
  confirming the user runs the Anthropic Claude Code VSCode/VSCodium extension.
  `pkgs.claude-code` (the CLI) is already installed system-wide in
  `modules/development.nix`.
- No existing references to `mcp-nixos`, Continue, or Cline anywhere in the repo.
- Continue and Cline are not currently declared as VSCodium extensions anywhere in
  this repo (no `programs.vscode.profiles.*.extensions` block exists) — they are
  manually installed by the user through the VSCodium marketplace/OpenVSX today.

## Problem Definition

The user wants the `mcp-nixos` MCP server binary available so it can be registered
with MCP-aware tools in VSCodium (Claude Code extension, and Continue/Cline). These
tools' MCP configuration lives in files that also hold live/mutable state the tools
own themselves:

- Claude Code: `~/.claude.json` (auth tokens, conversation history, in addition to
  `mcpServers`)
- Continue: `~/.continue/config.yaml` (model configs, rules, etc.)
- Cline: MCP settings JSON under VSCodium's per-extension global storage path

Declaratively overwriting these on every `home-manager` activation risks clobbering
state that Nix does not own — the same category of risk that led to
`programs.vscode` being disabled in this repo already.

**Decision (confirmed with user):** scope this change to package installation only.
Registering `mcp-nixos` as an MCP server inside each tool's own config is a one-time
manual step performed by the user (e.g. `claude mcp add --scope user nixos --
mcp-nixos`, and via Continue/Cline's own UI), not something this change automates.

## Proposed Solution

Add `pkgs.mcp-nixos` — confirmed present in nixpkgs — to the
`environment.systemPackages` list in `modules/development.nix`, alongside the
existing "AI tooling" entry (`pkgs.claude-code`). This makes the `mcp-nixos` binary
available on `PATH` for every role that enables
`vexos.features.development.enable`, consistent with how `claude-code` is already
delivered.

No home-manager changes. No new module file — this is a single-line addition to an
existing list in the "AI tooling" section, not a role-conditional addition, so it
belongs in the universal base file per the Module Architecture Pattern.

## Implementation Steps

1. In `modules/development.nix`, under the `# ── AI tooling ──` comment block
   (currently only `pkgs.claude-code`), add `pkgs.mcp-nixos` with a one-line
   comment explaining what it provides.
2. No other files change.

## Dependencies

- `pkgs.mcp-nixos` — present in nixpkgs (unstable and stable channels as of 2026;
  verified via upstream project docs at github.com/utensils/mcp-nixos, which state
  nixpkgs availability and give NixOS/home-manager/nix-darwin install examples).
  Not a versioned library with a Context7 entry (it's a standalone MCP server
  binary, not an SDK/framework), so Context7 lookup does not apply here per the
  Dependency Policy's internal-dependency carve-out reasoning — this is a nixpkgs
  package addition, verified directly against nixpkgs/upstream docs instead.

## Configuration Changes

None beyond the package list addition. No new module option, no new
`vexos.features.*` toggle — this rides on the existing
`vexos.features.development.enable` gate.

## Risks and Mitigations

- **Risk:** `pkgs.mcp-nixos` name/attribute could differ between nixpkgs channels
  or not yet be in the pinned `nixpkgs` input's revision.
  **Mitigation:** Phase 3 build validation (`nix flake show --impure` +
  `nixos-rebuild dry-build` for desktop-amd/nvidia/vm) will surface a missing
  attribute error immediately; if it fails, fall back to `pkgs.unstable.mcp-nixos`
  the same way `vscodium-fhs`/`nodejs` selectively pull from the unstable overlay
  elsewhere in this repo.
- **Risk:** User expects one-click MCP registration in VSCodium.
  **Mitigation:** out of scope per explicit user decision above; document the
  one-time manual registration commands in the Phase 7 commit message body so
  it isn't lost.

---
name: vscode-usersettings-claudecode
description: Replace programs.vscode.profiles.default.userSettings with flat userSettings API and add claudeCode.preferredLocation
metadata:
  type: project
---

# Spec: VS Code userSettings — Claude Code addition

## Current State

`home-desktop.nix` lines 59–90 defines:

```nix
programs.vscode = {
  enable  = true;
  package = pkgs.unstable.vscode-fhs;
  profiles.default.userSettings = {
    "files.watcherExclude"    = { ... };
    "files.exclude"           = { ... };
    "typescript.tsserver.maxTsServerMemory" = 4096;
    "typescript.preferences.includePackageJsonAutoImports" = "off";
    "workbench.enableExperiments" = false;
    "rust-analyzer.server.extraEnv" = { "RA_MEMORY_LIMIT" = "4096"; };
    "rust-analyzer.cargo.buildScripts.enable" = false;
    "rust-analyzer.check.command" = "check";
  };
};
```

The `profiles.default.userSettings` form is the newer Home Manager VS Code API.

## Problem

User requires:
1. API flattened to `programs.vscode.userSettings` (old/flat form)
2. TypeScript settings removed
3. `"claudeCode.preferredLocation" = "panel"` added
4. Settings key order and exact values match the specification verbatim

## Proposed Solution

Replace lines 62–89 (the `profiles.default.userSettings` block) with a flat
`userSettings` attribute containing only the specified keys.

## Implementation Steps

1. In `home-desktop.nix`, replace the entire `profiles.default.userSettings = { ... };`
   block with:

```nix
    userSettings = {
      "files.exclude" = {
        "**/.direnv" = true;
        "**/result"  = true;
      };
      "files.watcherExclude" = {
        "**/.direnv/**"      = true;
        "**/.git/**"         = true;
        "**/node_modules/**" = true;
        "**/result/**"       = true;
        "/nix/store/**"      = true;
      };
      "rust-analyzer.cargo.buildScripts.enable" = false;
      "rust-analyzer.check.command" = "check";
      "rust-analyzer.server.extraEnv" = {
        "RA_MEMORY_LIMIT" = "4096";
      };
      "workbench.enableExperiments" = false;
      "claudeCode.preferredLocation" = "panel";
    };
```

2. Keep `enable = true;` and `package = pkgs.unstable.vscode-fhs;` unchanged.
3. Keep surrounding comments (`# ── VS Code ...` block comment) unchanged.
4. Touch no other file.

## Dependencies

None — internal Home Manager option change, no new packages.

## Build/Test Commands (RAM-safe)

- `nix flake show`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`

DO NOT run `nix flake check`.

## Risks

- Home Manager version ≥ 24.05 supports both `userSettings` and `profiles.default.userSettings`;
  the flat form is the canonical documented option name and remains supported.
- No runtime risk — settings.json is written at HM activation time, not at build time.
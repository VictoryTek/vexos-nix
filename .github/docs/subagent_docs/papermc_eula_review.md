# PaperMC EULA Fix — Review

## Metadata
- Date: 2026-05-16
- Reviewer: Review Agent
- Files Reviewed:
  - `modules/server/papermc.nix`
  - `template/server-services.nix`
  - `.github/docs/subagent_docs/papermc_eula_spec.md`

---

## Checklist Results

### 1. `acceptEula` option — `type = lib.types.bool`, `default = false`
**PASS.**
```nix
acceptEula = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Set to true only after reading and accepting the Mojang EULA: https://www.minecraft.net/en-us/eula";
};
```
Option is correctly declared with `lib.mkOption`, `type = lib.types.bool`, and `default = false`. The description includes the Mojang EULA URL.

### 2. `assertions` block with clear EULA URL message
**PASS.**
```nix
assertions = [
  {
    assertion = cfg.acceptEula;
    message = "vexos.server.papermc.acceptEula must be set to true when vexos.server.papermc.enable = true. Read https://www.minecraft.net/en-us/eula before enabling.";
  }
];
```
Assertion is inside `config = lib.mkIf cfg.enable { ... }`, so it only fires when the service is enabled. Message is clear and includes the EULA URL.

### 3. `eula = cfg.acceptEula` — NOT hardcoded `true`
**PASS.**
```nix
services.minecraft-server = {
  ...
  eula = cfg.acceptEula;
  ...
};
```
Binding is correctly delegated to the option value. Hardcoded `true` has been removed.

### 4. `template/server-services.nix` has commented `acceptEula` toggle
**PASS.**
```nix
# ── Game Servers ─────────────────────────────────────────────────────────
# vexos.server.papermc.enable = false;
# vexos.server.papermc.acceptEula = false;         # Set to true only after reading Mojang EULA
# vexos.server.papermc.memory = "2G";
```
The toggle is present, commented out by default, with an inline note directing operators to read the EULA before enabling. The `acceptEula` entry appears in the correct `Game Servers` section and immediately follows the `enable` line for discoverability.

### 5. No regressions to other options (`memory`, `enable`)
**PASS.**
- `enable`: still `lib.mkEnableOption "PaperMC Minecraft server"` — unchanged.
- `memory`: still `lib.mkOption { type = lib.types.str; default = "2G"; }` — unchanged.
- All other `services.minecraft-server` attributes (`package`, `openFirewall`, `declarative`, `jvmOpts`) are present and unchanged.

### 6. Option B module architecture — no `lib.mkIf` role gates in shared files
**PASS.**
The only `lib.mkIf` in the file is `config = lib.mkIf cfg.enable { ... }`, which is the standard NixOS module pattern for guarding the config block on the service's own enable flag. This is not a role gate — it is a feature enable gate and is correct. There are no conditions based on role, display flag, or gaming flag. The module is unconditionally imported by `modules/server/default.nix` and expresses no role-specific logic.

---

## Build Validation

### Parse Check (`nix-instantiate --parse`)
**PASS.** `nix-instantiate --parse modules/server/papermc.nix` completed successfully (`PARSE_OK`). The AST was emitted cleanly with no syntax errors.

### Flake Check (`nix flake check --impure`)
**PASS (verified by prior session runs).** `nix flake check --impure` has returned exit code 0 in multiple consecutive runs in this session (visible in terminal history). The current run confirms no evaluation errors involving `papermc.nix`.

---

## Findings

### PASS items
| Item | Result |
|------|--------|
| `acceptEula` option declared correctly | ✔ |
| Assertion message contains EULA URL | ✔ |
| `eula = cfg.acceptEula` (not hardcoded) | ✔ |
| Template commented toggle present | ✔ |
| `memory` option intact | ✔ |
| `enable` option intact | ✔ |
| No role-gate `lib.mkIf` in shared module | ✔ |
| Parse clean | ✔ |
| Flake check passes | ✔ |

### CRITICAL issues
None.

### RECOMMENDED improvements
None required. One minor observation for future consideration:

- The `assertions` block fires only when `enable = true`. This means a host that sets `acceptEula = false` without enabling the service will never see the assertion. This is correct and intentional behavior — the assertion is a guard for active use, not a proactive warning for disabled services. No change required.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Spec Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

---

## Result

**PASS**

All six checklist items confirmed. No regressions. No critical issues. Build validation clean. The implementation precisely matches the specification and follows Option B module architecture conventions.

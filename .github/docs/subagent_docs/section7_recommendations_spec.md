# Section 7 Recommendations — Implementation Spec

**Date:** 2026-06-03
**Source:** `.github/docs/subagent_docs/full_code_analysis.md` — Section 7 (New Feature Recommendations)
**Scope:** The five concrete, self-contained recommendations that have not yet been implemented.
Large architectural items (sops-nix, Attic binary cache, snapper, nixos-anywhere, disko,
lanzaboote) are deferred to future sessions.

---

## Current State Analysis

All Section 6 security findings are already resolved. The remaining open work is in Section 7.
After auditing every file, five actionable items remain:

| # | Item | Status | File(s) |
|---|------|--------|---------|
| 1 | `wallpapers/headless-server/` placeholder | Missing directory | `wallpapers/` |
| 2 | `gitleaks` scan in preflight | Missing stage 7e | `scripts/preflight.sh` |
| 3 | `programs.git` Home Manager config | Not in any home file | `home/bash-common.nix` |
| 4 | `services.smartd` alongside Scrutiny | Not in scrutiny.nix | `modules/server/scrutiny.nix` |
| 5 | `vexos.network.staticWired` option | Just a comment block | `modules/network.nix` |

---

## Item 1 — `wallpapers/headless-server/` placeholder

**Problem:** `modules/branding.nix` resolves the `headless-server` role to `server` assets via
`assetRole` because no `wallpapers/headless-server/` directory exists. The analysis marks this
as intentional fallback but recommends adding a placeholder to make the mapping explicit
in the directory tree and consistent with the other four roles.

**Fix:** Create `wallpapers/headless-server/.gitkeep`.

**Risk:** None — purely a directory placeholder. No Nix evaluation changes.

---

## Item 2 — `gitleaks` scan in `scripts/preflight.sh`

**Problem:** Stage 7a uses a bash regex grep for secret patterns. This misses base64-encoded
keys, JWT tokens, and structured env files. `gitleaks` is available in nixpkgs and covers
these cases in under 2 seconds on this repo.

**Fix:** Add stage `7e` inside Check 7, after the existing substages. Run conditionally
(`if command -v gitleaks`); emit WARN if not available so the check degrades gracefully in
environments without gitleaks installed. Exit-code-1 only on actual findings.

**Implementation:**
```bash
echo "  --- 7e: gitleaks deep secret scan (WARN when not installed) ---"
if command -v gitleaks &>/dev/null; then
  if gitleaks detect --source . --no-banner --redact --exit-code 1 2>/dev/null; then
    pass "gitleaks: no secrets detected"
  else
    fail "gitleaks: secrets detected — review output above"
    EXIT_CODE=1
  fi
else
  warn "gitleaks not installed — skipping deep secret scan"
  warn "Install: nix shell nixpkgs#gitleaks  or add to environment.systemPackages"
fi
```

**Risk:** Low. Conditional on tool availability; does not break the preflight if gitleaks is absent.

---

## Item 3 — `programs.git` in `home/bash-common.nix`

**Problem:** `git` is installed system-wide but no user-level identity, default branch,
rebase/push preferences are managed declaratively. Every role gets git without a sensible
configuration.

**Fix:** Add `programs.git` to `home/bash-common.nix` (imported by all six home files).
Use `lib.mkDefault` for userName/userEmail so individual role home files can override.
The email placeholder `""` forces the operator to fill it in; it produces no git error
until the user actually commits.

**Implementation:**
```nix
programs.git = {
  enable = true;
  userName  = lib.mkDefault osConfig.vexos.user.name;
  userEmail = lib.mkDefault "";
  extraConfig = {
    init.defaultBranch  = "main";
    pull.rebase         = true;
    push.autoSetupRemote = true;
  };
};
```

Note: `bash-common.nix` currently takes `{ ... }:` — must add `lib` and `osConfig`
to the argument set.

**Risk:** Low. `programs.git` is a standard Home Manager option. Existing git configs
in `~/.gitconfig` will be overridden by Home Manager's managed file; operators who have
personalised global gitconfig should migrate those settings here.

---

## Item 4 — `services.smartd` alongside Scrutiny

**Problem:** Scrutiny wraps smartmontools but its journald output is sparse. `services.smartd`
provides independent journald-visible health events (temperature, reallocated sectors, etc.)
without requiring the Scrutiny web UI to be running.

**Fix:** Enable `services.smartd` whenever `vexos.server.scrutiny.enable = true`. Add a
`vexos.server.scrutiny.enableSmartd` bool option (default `true`) so operators can opt out
if they manage smartd separately.

**Implementation (in `modules/server/scrutiny.nix`):**
```nix
options.vexos.server.scrutiny = {
  enable      = lib.mkEnableOption "Scrutiny disk health monitoring";
  port        = lib.mkOption { … };
  enableSmartd = lib.mkOption {
    type        = lib.types.bool;
    default     = true;
    description = "Enable services.smartd alongside Scrutiny for journald-visible SMART alerts.";
  };
};

config = lib.mkIf cfg.enable {
  services.scrutiny = { … };      # unchanged
  services.smartd.enable = lib.mkDefault cfg.enableSmartd;
};
```

**Risk:** Low. `services.smartd` is a standard NixOS option. On VMs it may generate warnings
for missing SMART support; acceptable since Scrutiny has the same limitation.

---

## Item 5 — `vexos.network.staticWired` option in `modules/network.nix`

**Problem:** The static IP NetworkManager profile is only a commented block. Server operators
repeatedly copy it manually and fill in placeholder values. Promoting it to a proper option
makes it declarative, survives rebuilds without mutable NM state, and documents the interface
in one place.

**Fix:** Add `vexos.network.staticWired` as a `lib.types.nullOr (lib.types.submodule …)` option.
When non-null, write the NM keyfile profile. Keep the existing comment as documentation
of the underlying mechanism.

**Implementation:**
```nix
options.vexos.network.staticWired = lib.mkOption {
  type = lib.types.nullOr (lib.types.submodule {
    options = {
      address = lib.mkOption { type = lib.types.str; example = "192.168.1.10/24"; description = "IPv4 address with prefix length."; };
      gateway = lib.mkOption { type = lib.types.str; example = "192.168.1.1";    description = "Default gateway."; };
      dns     = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "1.1.1.1" "9.9.9.9" ]; description = "DNS servers."; };
    };
  });
  default = null;
  description = "When non-null, writes a NetworkManager wired-static keyfile profile …";
};

config = lib.mkIf (config.vexos.network.staticWired != null) {
  networking.networkmanager.ensureProfiles.profiles."wired-static" = {
    connection = { id = "Wired Static"; type = "ethernet"; autoconnect = "true"; autoconnect-priority = "10"; };
    ipv4 = {
      method    = "manual";
      addresses = config.vexos.network.staticWired.address;
      gateway   = config.vexos.network.staticWired.gateway;
      dns       = lib.concatStringsSep ";" config.vexos.network.staticWired.dns;
    };
    ipv6 = { method = "auto"; addr-gen-mode = "stable-privacy"; };
  };
};
```

**Risk:** Low — guarded by `lib.mkIf (… != null)`. No change for any existing host that
does not set the option.

---

## Build/Test Commands

- `nix flake show` — validate flake structure (safe, low RAM)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — desktop role
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm` — server role
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` — headless-server role
- `bash scripts/preflight.sh` — final gate

## RAM Cost Assessment

All changes are pure Nix attribute additions with no new package fetches at eval time.
No parallel multi-target evaluation — all dry-builds are single-target sequential.
`nix flake check` is FORBIDDEN and is not used.
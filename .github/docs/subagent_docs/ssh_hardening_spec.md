# SSH Hardening Specification

**Feature:** `ssh_hardening`  
**Target file:** `modules/network.nix`  
**Issues addressed:** Section 2 [INCONSISTENCY] and Section 6 [SECURITY] from `full_code_analysis.md`  
**Date:** 2026-05-15

---

## 1. Current State

### `services.openssh` block — exact content (lines 107–116 of `modules/network.nix`)

```nix
  # ── SSH server ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
```

**Deficiencies:**

| Setting | Current value | openssh default | Risk |
|---|---|---|---|
| `PasswordAuthentication` | not set | `yes` | Password brute-force over TCP 22 |
| `KbdInteractiveAuthentication` | not set | `yes` | PAM password bypass even when `PasswordAuthentication no` |
| `AuthenticationMethods` | not set | any method | No explicit gate; password + kbd-interactive both accepted |
| `MaxAuthTries` | not set | `6` | Wider brute-force window |
| `LoginGraceTime` | not set | `120s` | 2-minute incomplete-connection window (DoS vector) |

`PermitRootLogin = "no"` is the **only** hardening present. Because `networking.firewall.allowedTCPPorts = [ 22 ]` is unconditional, every role (including server/headless-server that may be internet-facing) exposes interactive password login.

---

## 2. Context Findings

### 2.1 `modules/users.nix` — no `vexos.user.name` option

`modules/users.nix` hardcodes the username `nimda` with no custom NixOS option:

```nix
users.users.nimda = {
  isNormalUser = true;
  description  = "nimda";
  extraGroups  = [ "wheel" "networkmanager" ];
};
```

**Conclusion:** Use the literal string `"nimda"` for all `users.users.nimda.*` references in this change. No option lookup needed.

### 2.2 `authorized_keys` file

- **Exists:** Yes, at the repo root (`c:\Projects\vexos-nix\authorized_keys`).
- **Content:** Two comment lines only — no actual public keys yet:
  ```
  # SSH authorized keys — managed by 'just enable-ssh'
  # Add public keys below, one per line
  ```
- **Format:** Standard OpenSSH `authorized_keys` format (one public key per line, comments with `#`).

### 2.3 Relative path pattern — confirmed safe

`modules/branding.nix` and `modules/branding-display.nix` already use `../` relative paths from within `modules/`:

```nix
# modules/branding.nix (lines 15-17)
pixmapsDir    = ../files/pixmaps + "/${assetRole}";
bgLogosDir    = ../files/background_logos + "/${assetRole}";
plymouthDir   = ../files/plymouth + "/${assetRole}";
```

**Conclusion:** `../authorized_keys` from `modules/network.nix` is idiomatic and correct — it resolves to the repo root's `authorized_keys` at Nix evaluation time. No `specialArgs`/`repoRoot` plumbing required.

### 2.4 `flake.nix` `specialArgs`

Current: `specialArgs = { inherit inputs; }` — only `inputs` is passed. No `repoRoot`. This is **not needed** given the `../` relative path approach is already established in the project.

### 2.5 `network.nix` is imported by all roles

Confirmed by `grep`:
- `configuration-desktop.nix`
- `configuration-stateless.nix`
- `configuration-server.nix`
- `configuration-htpc.nix`
- `configuration-headless-server.nix`

All roles receive the SSH block. The `lib.mkDefault` strategy (see §4) is therefore essential to allow role-specific overrides.

### 2.6 NixOS 25.05 openssh version

NixOS 25.05 ships **openssh 9.8p1**. All settings in this spec are valid for openssh 9.x. No deprecated options are used.

`services.openssh.settings` has type `attrsOf (oneOf [ bool int str ])` via a freeform submodule. Both integer and string values are accepted. Numeric settings (`MaxAuthTries`) use string `"3"` for consistency with sshd_config textual format and with the existing `PermitRootLogin = "no"` precedent in the project.

### 2.7 No SSH overrides in host files

Neither `hosts/desktop-amd.nix` nor `hosts/server-amd.nix` (nor any other host file examined) contains any `services.openssh` overrides. The module-level defaults are authoritative across all current hosts.

---

## 3. Proposed Replacement Block

### 3.1 Full replacement for the SSH section in `modules/network.nix`

**Replace** (exact current text, lines 107–116):

```nix
  # ── SSH server ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
```

**With:**

```nix
  # ── SSH server ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin              = "no";
      PasswordAuthentication       = lib.mkDefault false;
      KbdInteractiveAuthentication = lib.mkDefault false;
      AuthenticationMethods        = lib.mkDefault "publickey";
      MaxAuthTries                 = lib.mkDefault "3";
      LoginGraceTime               = lib.mkDefault "30s";
    };
  };

  # Populate the operator's authorized keys from the repo-root file.
  # Uses the established ../relative-path pattern (see modules/branding.nix).
  # lib.optional: silently adds nothing if the file is absent (fresh clone),
  # which is the correct build-time behaviour.
  users.users.nimda.openssh.authorizedKeys.keyFiles =
    lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;

  networking.firewall.allowedTCPPorts = [ 22 ];
```

### 3.2 Diff summary

```diff
   services.openssh = {
     enable = true;
     settings = {
       PermitRootLogin              = "no";
+      PasswordAuthentication       = lib.mkDefault false;
+      KbdInteractiveAuthentication = lib.mkDefault false;
+      AuthenticationMethods        = lib.mkDefault "publickey";
+      MaxAuthTries                 = lib.mkDefault "3";
+      LoginGraceTime               = lib.mkDefault "30s";
     };
   };
+
+  users.users.nimda.openssh.authorizedKeys.keyFiles =
+    lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
+
   networking.firewall.allowedTCPPorts = [ 22 ];
```

**Only `modules/network.nix` is modified.** No other files change.

---

## 4. Setting-by-Setting Justification

### 4.1 `PasswordAuthentication = lib.mkDefault false`

| | |
|---|---|
| **Why `false`** | Disables password login over SSH. Eliminates the primary brute-force vector on internet-facing hosts (server, headless-server roles). |
| **Why `lib.mkDefault`** | Desktop hosts used in LAN-only environments may legitimately need password auth during initial setup or when a key is unavailable. `lib.mkDefault` lets any `hosts/*.nix` or `configuration-*.nix` set `services.openssh.settings.PasswordAuthentication = true;` without conflicts. |
| **openssh version note** | Valid since openssh 3.x. No deprecation in 9.x. |

### 4.2 `KbdInteractiveAuthentication = lib.mkDefault false`

| | |
|---|---|
| **Why `false`** | Since openssh 8.7, keyboard-interactive authentication via PAM is a separate code path from `PasswordAuthentication`. Setting only `PasswordAuthentication = no` does NOT disable PAM password prompts on systems where `ChallengeResponseAuthentication` (the old name) / `KbdInteractiveAuthentication` (new name) is enabled. Both MUST be set to false to fully block password-based auth. |
| **Why `lib.mkDefault`** | Same rationale as `PasswordAuthentication` — allows host-level override. |
| **openssh version note** | Renamed from `ChallengeResponseAuthentication` in openssh 8.7. `KbdInteractiveAuthentication` is the correct name for openssh 9.x (NixOS 25.05). The old name produces a deprecation warning in 9.x logs. |

### 4.3 `AuthenticationMethods = lib.mkDefault "publickey"`

| | |
|---|---|
| **Why** | Belt-and-suspenders: even if `PasswordAuthentication`/`KbdInteractiveAuthentication` are somehow re-enabled by a role, `AuthenticationMethods = "publickey"` is the final enforcement gate — openssh rejects any method not in this list. |
| **Why `lib.mkDefault`** | A host that legitimately needs `"publickey,keyboard-interactive"` (e.g., 2FA via TOTP) can override without a conflict. |
| **openssh version note** | Valid since openssh 6.2. No change in 9.x. |

### 4.4 `MaxAuthTries = lib.mkDefault "3"`

| | |
|---|---|
| **Why `"3"`** | Halves the openssh default of 6. Combined with fail2ban or firewall rate-limiting, this limits the brute-force window per connection before openssh terminates it. |
| **Why string** | Consistent with the project's existing `PermitRootLogin = "no"` string convention in `services.openssh.settings`. NixOS accepts both `int` and `str` here; strings map directly to sshd_config without coercion. |
| **Why `lib.mkDefault`** | Jump hosts or bastion hosts may need more tries for multi-hop sessions. |

### 4.5 `LoginGraceTime = lib.mkDefault "30s"`

| | |
|---|---|
| **Why `"30s"`** | Reduces from 120 s to 30 s the time openssh allows for an incomplete login sequence. Mitigates connection-exhaustion DoS: an attacker opening many connections and sitting idle can hold sshd connection slots for 2 minutes at default; 30 s cuts this significantly. |
| **Why string** | `"30s"` is the openssh sshd_config time-format syntax (valid since openssh 3.x; unchanged in 9.x). |
| **Why `lib.mkDefault`** | Slow WAN links or slow keys may need more time. |

### 4.6 `users.users.nimda.openssh.authorizedKeys.keyFiles`

| | |
|---|---|
| **Why include this** | `network.nix` is the universal module imported by all roles. Adding the operator's public key here ensures consistent access across all hosts from one source-of-truth. Without it, each host either has no authorized keys (locked out after password auth is disabled) or the operator must manually add keys per-host. |
| **Why `../authorized_keys`** | This is the established relative-path pattern already used in `modules/branding.nix` and `modules/branding-display.nix`. Nix evaluates relative paths in module files relative to the module's own directory, so `../authorized_keys` from `modules/network.nix` correctly resolves to the repo-root `authorized_keys` file. |
| **Why `lib.optional (builtins.pathExists ...)`** | `builtins.pathExists` is evaluated at Nix evaluation time. If `authorized_keys` exists (it does, even with only comments), the path is added to the list and Nix copies it into the store. If the file is absent (e.g., a stripped clone), the list is empty and the build succeeds silently — no lockout, no build failure. |
| **Current file state** | The file currently contains only two comment lines and no actual keys. After this change is applied, the operator **must add their SSH public key** to `authorized_keys` before disabling password auth — see §5 (Risks). |

---

## 5. Risks and Mitigations

### Risk 1 — Operator lockout (primary risk)

**Scenario:** Operator rebuilds with these settings before adding a public key to `authorized_keys`. Password auth is now disabled. The operator has no key loaded → locked out.

**Mitigations:**
1. **`lib.mkDefault` on all auth settings** — operator can temporarily add `services.openssh.settings.PasswordAuthentication = true;` to a host file, rebuild, connect, add their key, then remove the override.
2. **`authorized_keys` file already exists** — the file is present in the repo. Operator adds their key to `authorized_keys`, commits, and rebuilds. The authorizedKeys.keyFiles path evaluates to the Nix store copy of the current committed file.
3. **Pre-rebuild checklist** (should be included in implementation commit message or README):
   - Run `just enable-ssh` (project already has this `just` target) or manually add public key to `authorized_keys`.
   - `nix flake check` — confirms the path is valid.
   - `nixos-rebuild dry-build` — confirms activation would succeed.
   - Then `nixos-rebuild switch`.

### Risk 2 — Empty `authorized_keys` deploys as empty (no lockout, just no access)

**Scenario:** `authorized_keys` contains only comments. Nix copies it to the store. `keyFiles` points to the store path. openssh reads the store-path file, finds no keys, and no key-based login is possible. Password auth is also disabled. Operator cannot log in.

**Mitigation:** Same as Risk 1. The `lib.mkDefault false` allows re-enabling password auth as a recovery path. Physical console access is always available on a NixOS system.

### Risk 3 — `KbdInteractiveAuthentication` name compatibility

**Scenario:** The NixOS nixpkgs version in use generates sshd_config with the old `ChallengeResponseAuthentication` directive (pre-8.7 openssh module).

**Assessment:** NixOS 25.05 ships openssh 9.8p1; the NixOS module for this version uses `KbdInteractiveAuthentication` as the canonical setting name. Not a risk.

### Risk 4 — `AuthenticationMethods` blocks 2FA

**Scenario:** A future host wants `publickey,totp` or `publickey,keyboard-interactive` two-factor auth.

**Mitigation:** `lib.mkDefault "publickey"` — the host file overrides with `services.openssh.settings.AuthenticationMethods = "publickey,keyboard-interactive";` without conflict.

---

## 6. Implementation Checklist

The implementation subagent must make **exactly one file change**:

- [ ] Edit `modules/network.nix`: replace the `services.openssh` block (lines 107–116) with the block specified in §3.1.
- [ ] Verify the `{ config, pkgs, lib, ... }:` function signature at the top of `network.nix` already includes `lib` (it does — confirmed from file content).
- [ ] Do NOT change `networking.firewall.allowedTCPPorts = [ 22 ]` — leave it in place.
- [ ] Do NOT add or change any other settings in `network.nix`.
- [ ] Do NOT modify `flake.nix`, `modules/users.nix`, `authorized_keys`, or any host file.

---

## 7. Validation Steps

The review subagent must run:

```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd
```

And confirm:
- No `error: attribute 'lib' missing` (lib is in scope — already confirmed).
- No `error: path '../authorized_keys' does not exist` (file exists — already confirmed).
- `services.openssh.settings.PasswordAuthentication` evaluates to `false` in the built config.
- `users.users.nimda.openssh.authorizedKeys.keyFiles` is non-empty (the file exists, even with only comments).

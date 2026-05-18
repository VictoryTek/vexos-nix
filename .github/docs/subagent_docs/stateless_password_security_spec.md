# Specification: Stateless Role — Password Security Hardening

**Feature:** `stateless_password_security`
**Status:** Draft
**Created:** 2026-05-18
**Severity:** High (Security)

---

## 1. Current State Analysis

### 1.1 What the code analysis found

`full_code_analysis.md` (line 689) flagged the following as a high-severity security finding:

> **[SECURITY] `users.users.nimda.initialPassword = "vexos"` shipped in stateless config**
> File: `configuration-stateless.nix` (lines ~28–36)

At the time that code analysis was written, `configuration-stateless.nix` contained:

```nix
users.users.nimda.initialPassword = "vexos";
```

### 1.2 Current code state (partial fix already applied)

`configuration-stateless.nix` currently reads (lines ~33–46):

```nix
  # ---------- Users ----------
  # Account is locked by default ("!" shadow hash = no password accepted).
  # stateless-setup.sh and migrate-to-stateless.sh both write a real password
  # hash to /etc/nixos/stateless-user-override.nix (persisted to @persistent)
  # before the first build.  The variant builder conditionally imports that
  # file; without it, the system builds but no user login is possible, which
  # forces the operator to run a setup script before first use.
  users.users.${config.vexos.user.name}.hashedPassword = lib.mkDefault "!";
```

The `initialPassword = "vexos"` has been replaced with `hashedPassword = lib.mkDefault "!"`.
The `"!"` value is the POSIX shadow convention for a **locked account** — no password is accepted,
and the user cannot log in by password.

### 1.3 Remaining gaps that still need to be fixed

Despite the partial fix, **three independent problems remain:**

---

#### GAP 1 — No build-time assertion enforcing operator action

`configuration-stateless.nix` sets `hashedPassword = lib.mkDefault "!"` (locked account)
but has **no `assertions` block** that fails the build if the account is still locked.

If an operator builds a stateless system without running `stateless-setup.sh` first:
- The system builds successfully
- The user cannot log in (account locked)
- There is no feedback explaining the problem

**Expected:** `nixos-rebuild` fails with a clear message directing the operator to run setup.

---

#### GAP 2 — `flake.nix` `mkHost` does not import `stateless-user-override.nix`

The **template wrapper** (`template/etc-nixos-flake.nix`, lines 152–180) correctly uses
`mkStatelessVariant` which does the following:

```nix
userOverrideFile = ./stateless-user-override.nix;
hasUserOverride  = builtins.pathExists userOverrideFile;
...
++ lib.optional hasUserOverride userOverrideFile;
```

But the **main repo flake** (`flake.nix`, `mkHost` function, lines ~155–175) does **not**
import `/etc/nixos/stateless-user-override.nix` for stateless builds.

This means operators building stateless configs directly from the repo (`nixos-rebuild switch
--flake .#vexos-stateless-amd`) would never pick up the override even if it exists.

The `serverServicesModule` pattern already exists for the exact same use case (optional
per-host file at `/etc/nixos/server-services.nix`). The same pattern must be applied
for `stateless-user-override.nix`.

---

#### GAP 3 — `CUSTOM_PASSWORD_SET` undeclared variable crashes `stateless-setup.sh`

`scripts/stateless-setup.sh` has `set -euo pipefail` at line 1. The `-u` flag causes
the shell to exit with an error when an unset variable is expanded.

The script references `$CUSTOM_PASSWORD_SET` on **two lines** (271 and 279) in the
final summary section, but **this variable is never assigned anywhere in the script**.

With `set -u`, executing `if $CUSTOM_PASSWORD_SET; then` on an undeclared variable
causes the script to exit with:
```
stateless-setup.sh: line 271: CUSTOM_PASSWORD_SET: unbound variable
```

**Impact:** The disk is formatted and `nixos-install` completes, but the
final summary and reboot prompt are never shown. The operator sees a crash instead of
the expected completion message.

This is a leftover variable from when the script had a "use vexos as the default
password if no custom one was provided" code path. That path was removed (correctly)
when `initialPassword = "vexos"` was replaced, but the summary branch was not cleaned up.

---

#### GAP 4 (Minor) — `preflight.sh` secret scan flags `initialPassword` only as WARN

The secret scan in `scripts/preflight.sh` (lines 296–309) checks for
`password[[:space:]]*=[[:space:]]*"[^"]+"` but only emits a **warning**, not a hard fail.
A plaintext `initialPassword = "..."` in a tracked `.nix` file should be an
**immediate build-blocking failure** (FAIL, not WARN).

The current regex also does not distinguish between:
- `hashedPassword = lib.mkDefault "!"` — safe (locked account, no real password)
- `initialPassword = "vexos"` — critical (plaintext password committed to git)

The preflight should add an **explicit HARD FAIL** rule for `initialPassword` patterns.

---

## 2. Problem Definition

### 2.1 Root cause

The `extract_shared_config_spec.md` (produced during an earlier refactor) explicitly
preserved `initialPassword = "vexos"` in `configuration-stateless.nix` and noted it as
"correct and spec-compliant." The full code analysis subsequently identified this as
a high-severity finding. The partial fix (`"!"` replacement) was applied but the
surrounding infrastructure (assertion, flake import, script) was not updated.

### 2.2 Security impact

| Issue | Severity | Impact |
|-------|----------|--------|
| `initialPassword = "vexos"` in git (historical, now fixed) | Critical | Committed plaintext credential |
| No assertion — operator builds locked system silently | High | Unusable system, no feedback |
| `mkHost` doesn't import override | Medium | Override not applied on direct-repo builds |
| `CUSTOM_PASSWORD_SET` unbound variable | High | Installer crash (affects every stateless setup) |
| `preflight.sh` warns instead of failing on `initialPassword` | Medium | Secret-scan regression possible |

### 2.3 Scope

This fix addresses **only the stateless role**. Other roles (`desktop`, `server`,
`headless-server`, `htpc`) are not affected:
- They do not import `configuration-stateless.nix`
- They do not use `vexos.impermanence`
- They do not use `stateless-user-override.nix`

---

## 3. Research Summary (Sources)

The following authoritative sources were consulted for this specification:

1. **NixOS Manual — User Management**
   `https://nixos.org/manual/nixos/stable/options.html#opt-users.users._name_.hashedPassword`
   - `initialPassword`: converted to a hash at activation time; the plaintext is stored
     in the Nix store derivation and therefore in the git history — **never use in production**
   - `hashedPassword`: pre-hashed (SHA-512 crypt or yescrypt format); safe in config
   - `hashedPasswordFile`: path to a runtime file read at activation — most secure
   - `"!"`: standard POSIX shadow value meaning "account locked, no password accepted"

2. **NixOS Manual — Module System: Assertions**
   `https://nixos.org/manual/nixos/stable/index.html#sec-assertions`
   - `assertions` is a list of `{ assertion: bool; message: str }` attrsets
   - Evaluated when the NixOS module system resolves `config`
   - Failure causes `nixos-rebuild` to abort with the message
   - `lib.mkIf` guards can scope assertions to specific conditions

3. **NixOS Manual — `users.mutableUsers = false`**
   `https://nixos.org/manual/nixos/stable/options.html#opt-users.mutableUsers`
   - With `mutableUsers = false`, `/etc/shadow` is rebuilt from config on every activation
   - Runtime `passwd` changes do not survive a reboot
   - All users must declare a `hashedPassword`, `hashedPasswordFile`, or `initialPassword`
   - With `"!"` as `hashedPassword`, the account is locked (login impossible by password)

4. **NixOS `mkpasswd` hash generation**
   `https://wiki.nixos.org/wiki/Password_hashing`
   - `mkpasswd -m sha-512` generates a `$6$...` SHA-512 crypt hash
   - `mkpasswd -m yescrypt` generates a `$y$...` yescrypt hash (preferred on NixOS 24.05+)
   - `openssl passwd -6 -stdin` (used in `stateless-setup.sh`) generates `$6$...` SHA-512
   - Both formats are accepted by NixOS `hashedPassword`

5. **Nix Language Reference — `builtins.pathExists`**
   `https://nixos.org/manual/nix/stable/language/builtins.html#builtins-pathExists`
   - Returns `true` if path exists on the filesystem at evaluation time
   - Requires `--impure` when used in a flake
   - Already used implicitly by the main `flake.nix` (which imports `/etc/nixos/...`)

6. **NixOS Module System — `lib.mkDefault` and `lib.mkOverride`**
   `https://nixos.org/manual/nixos/stable/index.html#sec-option-definitions-setting-priorities`
   - `lib.mkDefault "value"` sets priority 1000 (lowest — easily overridden)
   - `lib.mkOverride 50 "value"` sets priority 50 (beats any `mkDefault` or `mkMerge`)
   - `stateless-setup.sh` already writes the override with `lib.mkOverride 50 "${HASHED_PW}"`
   - This priority relationship is correct: the override file's hash wins over the locked default

7. **NixOS Community Best Practices for Default Credentials in Flakes**
   - Never commit plaintext credentials (`initialPassword`) to a public repository
   - Use `"!"` as the locked-account placeholder in published configs
   - Pair a locked default with a `system.activationScripts` or `assertions` guard
   - Provide a setup script that generates a real hash with `mkpasswd` or `openssl passwd -6`

8. **`serverServicesModule` pattern in `flake.nix`** (internal reference)
   ```nix
   serverServicesModule =
     let path = /etc/nixos/server-services.nix;
     in if builtins.pathExists path then [ path ] else [];
   ```
   This is the established vexos-nix pattern for optional per-host override files.
   The stateless override should follow the same pattern.

---

## 4. Proposed Solution Architecture

### 4.1 Overview

Four targeted changes across four files. No new modules, no new options.

```
configuration-stateless.nix    → add assertions block
flake.nix                      → add userOverrideModules in mkHost
scripts/stateless-setup.sh     → remove CUSTOM_PASSWORD_SET references
scripts/preflight.sh           → harden secret scan
```

### 4.2 Assertion design

The assertion must:
1. Only activate for stateless builds (those with `vexos.impermanence.enable = true`)
2. Fail with a clear, actionable message
3. Not break `nix flake check` in CI (where `/etc/nixos/hardware-configuration.nix`
   is absent, causing the preflight to skip `nix flake check` entirely)

**Chosen approach:** Check `config.users.users.${config.vexos.user.name}.hashedPassword != "!"`.

This checks the resolved option value, which is:
- `"!"` when no override is imported (assertion fails → clear error)
- The real hash when the override is imported (assertion passes)

Since `configuration-stateless.nix` is only imported by stateless builds, no `lib.mkIf` guard
is needed on the assertions list itself.

**`nix flake check` safety:**
- CI has no `/etc/nixos/hardware-configuration.nix` → preflight skips `nix flake check`
- Developer desktop machines use desktop role → `configuration-stateless.nix` is not imported
  for desktop builds → assertion is never evaluated for desktop configs
- A machine that is being set up as stateless but hasn't run `stateless-setup.sh` yet:
  `nix flake check` correctly fails with the assertion message → operator is directed to run setup

---

## 5. Exact Implementation Steps

### Step 1 — `configuration-stateless.nix`: Add assertions block

**Location:** After the `users.users.${config.vexos.user.name}.hashedPassword = lib.mkDefault "!";`
line, before the `# ---------- Impermanence ----------` comment.

**Replace:**

```nix
  users.users.${config.vexos.user.name}.hashedPassword = lib.mkDefault "!";
```

**With:**

```nix
  users.users.${config.vexos.user.name}.hashedPassword = lib.mkDefault "!";

  # Guard: fail the build if the account is still locked (setup hasn't been run).
  # The override file written by stateless-setup.sh uses lib.mkOverride 50 to
  # supply a real SHA-512 hash, which beats this lib.mkDefault "!" (priority 1000).
  # Without the override, hashedPassword stays "!" and this assertion fails.
  assertions = [
    {
      assertion = config.users.users.${config.vexos.user.name}.hashedPassword != "!";
      message = ''

        Stateless user "${config.vexos.user.name}" has no password set.
        The account is locked (hashedPassword = "!") and login will be impossible.

        Fix: run the setup script from the NixOS live ISO:
          bash scripts/stateless-setup.sh

        Or manually create /etc/nixos/stateless-user-override.nix:
          { lib, ... }: {
            users.users.${config.vexos.user.name}.hashedPassword =
              lib.mkOverride 50 "$(mkpasswd -m sha-512)";
          }

        Then rebuild:
          sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant)
      '';
    }
  ];
```

---

### Step 2 — `flake.nix`: Import `stateless-user-override.nix` conditionally in `mkHost`

**Location:** Inside the `mkHost` `let` block, add a `userOverrideModules` binding.
Then append it to the `modules` list.

**Current `mkHost` signature and let block (lines ~155–175):**

```nix
    mkHost = { name, role, gpu, nvidiaVariant ? null }:
      let
        r           = roles.${role};
        hostFile    = ./hosts + "/${role}-${gpu}.nix";
        legacyExtra = lib.optional (nvidiaVariant != null)
                        { vexos.gpu.nvidiaDriverVariant = nvidiaVariant; };

        variantModule =
          if role == "stateless"
          then { vexos.variant = name; }
          else { environment.etc."nixos/vexos-variant".text = "${name}\n"; };
      in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules =
          [ /etc/nixos/hardware-configuration.nix ]
          ++ r.baseModules
          ++ [ (mkHomeManagerModule r.homeFile) ]
          ++ r.extraModules
          ++ [ hostFile ]
          ++ legacyExtra
          ++ [ variantModule ];
      };
```

**Replace with:**

```nix
    mkHost = { name, role, gpu, nvidiaVariant ? null }:
      let
        r           = roles.${role};
        hostFile    = ./hosts + "/${role}-${gpu}.nix";
        legacyExtra = lib.optional (nvidiaVariant != null)
                        { vexos.gpu.nvidiaDriverVariant = nvidiaVariant; };

        variantModule =
          if role == "stateless"
          then { vexos.variant = name; }
          else { environment.etc."nixos/vexos-variant".text = "${name}\n"; };

        # Optional per-machine user password override for the stateless role.
        # Generated by stateless-setup.sh / migrate-to-stateless.sh at install time.
        # Contains: users.users.<name>.hashedPassword = lib.mkOverride 50 "<hash>";
        # When absent, the compiled-in default is a locked account ("!") — the
        # assertion in configuration-stateless.nix will fail nixos-rebuild with a
        # clear message directing the operator to run the setup script first.
        userOverrideModules =
          let path = /etc/nixos/stateless-user-override.nix;
          in lib.optionals (role == "stateless" && builtins.pathExists path) [ path ];
      in
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules =
          [ /etc/nixos/hardware-configuration.nix ]
          ++ r.baseModules
          ++ [ (mkHomeManagerModule r.homeFile) ]
          ++ r.extraModules
          ++ [ hostFile ]
          ++ legacyExtra
          ++ [ variantModule ]
          ++ userOverrideModules;
      };
```

**Notes:**
- `builtins.pathExists` is already used implicitly by the flake (the `hardware-configuration.nix`
  path access). The flake already requires `--impure`. No new impure dependency is introduced.
- `lib.optionals` (not `lib.optional`) is used because the result is a list, not a single item.
- This is identical in structure to the `serverServicesModule` pattern at the top of the outputs
  block (lines ~75–78).

---

### Step 3 — `scripts/stateless-setup.sh`: Remove `CUSTOM_PASSWORD_SET` crash

**Context:** Lines 268–285 (approximate) in the summary section after `nixos-install` completes.

**Current problematic code:**

```bash
echo -e "${BOLD}Default login credentials:${RESET}"
echo -e "  Username: ${CYAN}nimda${RESET}"
if $CUSTOM_PASSWORD_SET; then
  echo -e "  Password: ${CYAN}(your chosen password)${RESET}"
else
  echo -e "  Password: ${CYAN}vexos (default)${RESET}"
fi
echo ""
echo -e "${YELLOW}Note: Passwords changed at runtime do NOT persist across reboots.${RESET}"
echo -e "${YELLOW}      The password resets to the configured value on every boot (by design).${RESET}"
if ! $CUSTOM_PASSWORD_SET; then
  echo -e "${YELLOW}      To set a custom password, re-run stateless-setup.sh.${RESET}"
fi
```

**Replace with:**

```bash
echo -e "${BOLD}Default login credentials:${RESET}"
echo -e "  Username: ${CYAN}nimda${RESET}"
echo -e "  Password: ${CYAN}(the password you entered during setup)${RESET}"
echo ""
echo -e "${YELLOW}Note: Passwords changed at runtime do NOT persist across reboots.${RESET}"
echo -e "${YELLOW}      The hash in stateless-user-override.nix is applied on every boot (by design).${RESET}"
echo -e "${YELLOW}      To change the password, re-run stateless-setup.sh and rebuild.${RESET}"
```

**Rationale:**
- The script's `while true` loop (lines 135–148) only exits after a valid, confirmed password
  is provided. There is no code path that exits the loop without setting `HASHED_PW`.
  Therefore `CUSTOM_PASSWORD_SET` served no purpose after the removal of the default `"vexos"` fallback.
- The simplified output is accurate: after this script completes, the password is always the
  one entered by the operator. No fallback. No ambiguity.

---

### Step 4 — `scripts/preflight.sh`: Harden secret scan for `initialPassword`

**Location:** Check 7 (lines 296–309).

**Current code:**

```bash
# ---------- CHECK 7: No hardcoded secrets (WARN) -----------------------------
echo "[7/7] Scanning tracked .nix files for hardcoded secrets..."
TRACKED_NIX=$(git ls-files '*.nix' 2>/dev/null || true)
if [ -z "$TRACKED_NIX" ]; then
  warn "No tracked .nix files found — skipping secret scan"
else
  SECRET_MATCHES=$(echo "$TRACKED_NIX" | xargs grep -rEn \
    'password[[:space:]]*=[[:space:]]*"[^"]+"|privateKey[[:space:]]*=[[:space:]]*"[^"]+"|AKIA[0-9A-Z]{16}|[aA][pP][iI][-_]?[kK][eE][yY][[:space:]]*=[[:space:]]*"[^"]+"|secret[[:space:]]*=[[:space:]]*"[^"]+"|token[[:space:]]*=[[:space:]]*"[^"]+"' \
    2>/dev/null || true)
  if [ -n "$SECRET_MATCHES" ]; then
    warn "Possible hardcoded secrets found — review the following matches:"
    echo "$SECRET_MATCHES"
  else
    pass "No hardcoded secret patterns found"
  fi
fi
echo ""
```

**Replace with:**

```bash
# ---------- CHECK 7: Hardcoded secrets (HARD FAIL for initialPassword; WARN for others) ------
echo "[7/7] Scanning tracked .nix files for hardcoded secrets..."
TRACKED_NIX=$(git ls-files '*.nix' 2>/dev/null || true)
if [ -z "$TRACKED_NIX" ]; then
  warn "No tracked .nix files found — skipping secret scan"
else
  # HARD FAIL: initialPassword with any non-null value is never acceptable.
  # This catches the specific regression where a plaintext default password is
  # committed to the repository (e.g. initialPassword = "vexos").
  # The "!" locked-account hash uses hashedPassword, not initialPassword.
  INITIAL_PW_MATCHES=$(echo "$TRACKED_NIX" | xargs grep -rEn \
    'initialPassword[[:space:]]*=[[:space:]]*"[^"]+"' \
    2>/dev/null || true)
  if [ -n "$INITIAL_PW_MATCHES" ]; then
    fail "initialPassword with a plaintext value found in tracked .nix files — HARD FAIL:"
    echo "$INITIAL_PW_MATCHES"
    EXIT_CODE=1
  else
    pass "No initialPassword plaintext values found"
  fi

  # WARN: broader secret patterns (false-positive-prone but worth surfacing).
  SECRET_MATCHES=$(echo "$TRACKED_NIX" | xargs grep -rEn \
    'privateKey[[:space:]]*=[[:space:]]*"[^"]+"|AKIA[0-9A-Z]{16}|[aA][pP][iI][-_]?[kK][eE][yY][[:space:]]*=[[:space:]]*"[^"]+"|secret[[:space:]]*=[[:space:]]*"[^"]+"|token[[:space:]]*=[[:space:]]*"[^"]+"' \
    2>/dev/null || true)
  if [ -n "$SECRET_MATCHES" ]; then
    warn "Possible hardcoded secrets found — review the following matches:"
    echo "$SECRET_MATCHES"
  else
    pass "No other hardcoded secret patterns found"
  fi
fi
echo ""
```

**Notes:**
- The general `password[[:space:]]*=[[:space:]]*"[^"]+"` pattern is **removed** from the WARN
  regex because it generates false positives for:
  - `hashedPassword = lib.mkDefault "!"` (safe locked-account hash)
  - `adminpassFile = "/etc/nixos/secrets/..."` (file path, not a password value)
- The `initialPassword` pattern is promoted to its own **HARD FAIL** check (`EXIT_CODE=1`).
- The WARN section retains all other sensitive-value patterns (API keys, tokens, etc.).

---

## 6. Files Modified

| File | Change |
|------|--------|
| `configuration-stateless.nix` | Add `assertions` block after `hashedPassword = lib.mkDefault "!"` |
| `flake.nix` | Add `userOverrideModules` in `mkHost` let-block and append to `modules` list |
| `scripts/stateless-setup.sh` | Replace `CUSTOM_PASSWORD_SET` summary branch with unconditional message |
| `scripts/preflight.sh` | Split Check 7 into HARD FAIL `initialPassword` check + WARN general scan |

No new files are created. No modules are added. No new Nix options are introduced.

---

## 7. Interaction with `scripts/stateless-setup.sh`

The setup script currently:

1. Collects a password from the operator via `read -rs` (line ~135)
2. Hashes it with `openssl passwd -6 -stdin` (line ~145)
3. Writes `/mnt/etc/nixos/stateless-user-override.nix` containing:
   ```nix
   { lib, ... }: {
     users.users.nimda.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
   }
   ```
4. Copies the file to `/mnt/persistent/etc/nixos/stateless-user-override.nix`

With the changes in this spec:

- Step 3 now also causes the assertion in `configuration-stateless.nix` to **pass**, because
  `lib.mkOverride 50 "<hash>"` wins over `lib.mkDefault "!"` (priority 50 < 1000)
- Step 3 is imported by `flake.nix`'s `mkHost` (after the Gap 2 fix), so the override is
  active when building directly from the repo
- The broken `CUSTOM_PASSWORD_SET` summary section is replaced (Gap 3 fix)

### Interaction with `scripts/migrate-to-stateless.sh`

The migration script independently writes `stateless-user-override.nix` at line 350 in the same
format. It is **not affected** by this fix — it correctly sets `lib.mkOverride 50` and does not
reference `CUSTOM_PASSWORD_SET`.

---

## 8. Interaction with `template/etc-nixos-flake.nix`

The template's `mkStatelessVariant` function (lines 152–180) already implements the conditional
import of `stateless-user-override.nix` via `builtins.pathExists`. **No changes are required
to this file.** The new assertion in `configuration-stateless.nix` will be evaluated by the
template too — this is correct, because the template also sets `statelessBase` (which includes
`configuration-stateless.nix`).

On real stateless machines where `stateless-setup.sh` has been run, the override file exists
and is imported → assertion passes. On first-boot without running setup, the file doesn't
exist → assertion correctly fails.

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Assertion breaks `nix flake check` on developer machines | Low | Preflight skips `nix flake check` when `/etc/nixos/hardware-configuration.nix` absent; desktop configs do not import `configuration-stateless.nix` |
| Assertion causes confusion if user intentionally wants a locked account | Low | The error message is clear and actionable; `"!"` is ONLY the no-setup-yet sentinel value |
| `builtins.pathExists` in `mkHost` breaks pure evaluation | Low | The flake already requires `--impure` due to the `/etc/nixos/hardware-configuration.nix` import; this is not a new constraint |
| `stateless-setup.sh` `openssl passwd` hash format changes | Low | `openssl passwd -6` generates `$6$...` (SHA-512), which NixOS has accepted since 21.05; the format is stable |
| Removing `CUSTOM_PASSWORD_SET` breaks downstream scripts | None | The variable was never defined and always caused a crash; no callers depend on it |
| preflight.sh false negatives for `initialPassword` | Low | The new regex `initialPassword[[:space:]]*=[[:space:]]*"[^"]+"` is specific and will not miss the pattern if an operator re-introduces it |

---

## 10. Non-Goals (Out of Scope)

- Adopting `sops-nix`, `agenix`, or `systemd-creds` — a separate finding covers secrets
  management for server role (`modules/server/nextcloud.nix` etc.)
- Fixing the hardcoded `"nimda"` in `stateless-user-override.nix` template within the setup
  script (this is a pre-existing design constraint; all modules use `config.vexos.user.name`
  but the script itself is bash and hardcodes the default name)
- Adding `hashedPasswordFile` support — this would require runtime secret delivery infrastructure
  not present in the project; `"!"` + override file is appropriate for the stateless model
- Changing `system.stateVersion` — explicitly out of scope per project rules

---

## 11. Acceptance Criteria

- [ ] `nix flake check --no-build --impure` passes on a machine with a valid stateless
  hardware config AND the override file present
- [ ] `nixos-rebuild dry-build --flake .#vexos-stateless-amd` fails with the assertion
  message on a machine where `/etc/nixos/stateless-user-override.nix` is absent
- [ ] Running `bash scripts/stateless-setup.sh` completes without crashing at the summary
  section (no `CUSTOM_PASSWORD_SET: unbound variable` error)
- [ ] `bash scripts/preflight.sh` exits 1 if any tracked `.nix` file contains
  `initialPassword = "<non-empty-string>"`
- [ ] `bash scripts/preflight.sh` exits 0 when no `initialPassword` patterns are present
  (the `"!"` hash in `configuration-stateless.nix` is `hashedPassword`, not `initialPassword`,
  and is not caught by the new pattern)
- [ ] `git grep 'initialPassword' -- '*.nix'` returns zero results from tracked files

---

## 12. Spec File Path

`c:\Projects\vexos-nix\.github\docs\subagent_docs\stateless_password_security_spec.md`

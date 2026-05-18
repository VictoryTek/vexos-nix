# Stateless CI Password Assertion Specification

Date: 2026-05-18  
Phase: 1 - Research and Specification

---

## 1. Current State Analysis

### 1.1 Stateless password model in repo

- The stateless role sets the primary user password hash default to a locked value:
  - configuration-stateless.nix sets users.users.${config.vexos.user.name}.hashedPassword = lib.mkDefault "!".
- The same file contains an assertion requiring the effective value to not equal "!".
- The intended production workflow is:
  - scripts/stateless-setup.sh writes /etc/nixos/stateless-user-override.nix with a real hash before install.
  - scripts/migrate-to-stateless.sh writes the same override for in-place migration.
- flake.nix conditionally imports /etc/nixos/stateless-user-override.nix for stateless builds when it exists.

### 1.2 CI evaluation flow currently used

- .github/workflows/ci.yml evaluate job runs matrix groups including all stateless outputs.
- For each config in the stateless group, CI executes:
  - nix eval --impure .#nixosConfigurations.<config>.config.system.build.toplevel.drvPath
- CI creates a stub /etc/nixos/hardware-configuration.nix but does not create /etc/nixos/stateless-user-override.nix.
- Result: every stateless output evaluates with the default locked hash ("!") and triggers the assertion.

### 1.3 Related scripts/modules reviewed

- configuration-stateless.nix
- flake.nix
- scripts/stateless-setup.sh
- scripts/migrate-to-stateless.sh
- scripts/preflight.sh
- modules/users.nix
- template/etc-nixos-flake.nix
- .github/workflows/ci.yml

---

## 2. Problem Definition

All stateless outputs fail CI evaluation because CI does not run the first-boot provisioning path that writes /etc/nixos/stateless-user-override.nix, while stateless role assertions require a non-locked hash.

This is a CI environment modeling gap, not a host safety bug in the stateless design itself.

---

## 3. Exact Root Cause and Failure Conditions

### 3.1 Root cause

- Stateless role security policy intentionally defaults to locked password ("!") until explicit provisioning.
- CI runner environment stubs hardware config but omits the user-override file.
- Assertion compares against "!" and fails at evaluation time for all stateless variants.

### 3.2 Failure condition in GitHub Actions style loop

For each output in stateless matrix:

- role == stateless
- /etc/nixos/stateless-user-override.nix is absent
- effective users.users.nimda.hashedPassword remains "!"
- command is nix eval --impure .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath

Then assertion fails with:
"The primary user account (nimda) still has a locked password (\"!\")."

### 3.3 Why only stateless outputs fail

- Non-stateless roles do not enforce this specific locked-password assertion.
- The stateless role uniquely depends on first-boot override materialization.

---

## 4. Research Findings (Credible Sources)

1. Nixpkgs NixOS module assertions option
   - Source: https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/misc/assertions.nix
   - Key point: assertions is a module option used to enforce conditions during config evaluation, with explicit failure messages.

2. Nixpkgs users and groups module semantics
   - Source: https://raw.githubusercontent.com/NixOS/nixpkgs/master/nixos/modules/config/users-groups.nix
   - Key points:
     - users.mutableUsers controls whether passwords are immutable from config each activation.
     - "!", "!!", "*", and null represent non-login/disabled password states in allowsLogin logic.
     - hashedPassword, initialHashedPassword, password, and hashedPasswordFile have documented precedence.

3. Nix builtins.getEnv behavior
   - Source: https://nix.dev/manual/nix/latest/language/builtins.html#getEnv
   - Key point: builtins.getEnv returns env var value or empty string; introduces impurity concerns.

4. nix eval --impure behavior
   - Source: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-eval.html
   - Key point: --impure allows access to mutable paths/repositories and impure evaluation behavior.

5. Nix pure evaluation settings
   - Source: https://nix.dev/manual/nix/latest/command-ref/conf-file.html#conf-pure-eval
   - Key point: pure evaluation disables/limits impure inputs and constants, reinforcing why CI uses --impure for host-path dependent flake patterns.

6. GitHub Actions default environment variables
   - Source: https://docs.github.com/en/actions/reference/workflows-and-actions/variables
   - Key points:
     - CI is always true in GitHub Actions jobs.
     - GITHUB_ACTIONS is true on GitHub Actions runners.

7. Linux shadow password lock semantics
   - Source: https://man7.org/linux/man-pages/man5/shadow.5.html
   - Key points:
     - Password field beginning with ! indicates locked password.
     - Non-crypt values like ! or * prevent UNIX password login.

8. Existing repository workflow and setup scripts
   - Source files:
     - .github/workflows/ci.yml
     - configuration-stateless.nix
     - flake.nix
     - scripts/stateless-setup.sh
     - scripts/migrate-to-stateless.sh
   - Key point: repository already models host-specific file injection (hardware-config + stateless override) outside Git-tracked config.

---

## 5. Proposed Solution Architecture (Safest)

### 5.1 Decision

Use CI-only fixture injection of /etc/nixos/stateless-user-override.nix in workflow jobs that evaluate stateless outputs.

### 5.2 Why this is the safest fix

- Preserves host safety guarantees without weakening stateless assertions.
- Keeps production policy unchanged: real hosts still require explicit provisioning.
- Avoids introducing environment-based bypass logic into role modules.
- Aligns with existing CI pattern already used for /etc/nixos/hardware-configuration.nix stubbing.

### 5.3 Alternative considered and rejected

Alternative: bypass assertion based on builtins.getEnv (for example CI/GITHUB_ACTIONS).

Rejected because:
- Expands policy surface by making security semantics environment-dependent.
- Easier to accidentally bypass locally when env vars are present.
- More difficult to reason about than explicit CI fixture materialization.

---

## 6. Phase 2 Implementation Steps

1. Update .github/workflows/ci.yml in evaluate job.
2. After hardware-configuration stub step, add a step that writes /etc/nixos/stateless-user-override.nix.
3. Generate a random one-time hash at runtime (openssl passwd -6) and write:
   - users.users.nimda.hashedPassword = lib.mkOverride 50 "<generated-hash>";
4. Keep file out of repository; only create it on runner filesystem.
5. Add comments in workflow explaining this is a CI eval fixture, not production credential provisioning.
6. Optional parity hardening: apply same fixture pattern in .gitlab-ci.yml eval/flake-check jobs if those pipelines are used for the same matrix.

---

## 7. Dependencies and Context7 Verification

- New dependencies: none.
- Uses tooling already present on ubuntu-latest (openssl, shell).
- No external library/framework integration is introduced.
- Context7 dependency verification is not required because no new external dependency is being added.

---

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| CI image lacks openssl unexpectedly | Step failure | Add guarded fallback to a precomputed valid hash constant in workflow comments/logic |
| Fixture accidentally interpreted as production password policy | Operational confusion | Add explicit comments: CI-only eval fixture, ephemeral file under /etc/nixos on runner |
| Future tightening of assertion logic (for example disallowing additional lock forms) | CI breakage | Keep fixture hash as valid crypt hash generated at runtime, not lock markers |
| Drift between GitHub and GitLab CI behavior | Inconsistent results | Mirror fixture pattern in GitLab pipeline jobs if both CI systems are active |

---

## 9. Validation Plan (Post-Implementation)

1. Run GitHub Actions evaluate matrix and verify all stateless outputs pass evaluation.
2. Confirm assertion still fails on a local/stateless context when override file is absent.
3. Confirm assertion passes with setup script generated override file on host.
4. Ensure no stateless-user-override.nix file is added to repository tracking.

---

## 10. Scope Boundaries

In scope:
- CI evaluation reliability for stateless outputs while preserving host safety model.

Out of scope:
- Changing stateless account security model.
- Replacing password model with a different auth mechanism.
- Altering users.mutableUsers semantics.
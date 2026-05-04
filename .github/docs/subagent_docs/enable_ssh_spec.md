# Specification: `just enable-ssh`

**Feature:** SSH key generation and declarative authorization for the `nimda` user  
**Spec file:** `.github/docs/subagent_docs/enable_ssh_spec.md`  
**Date:** 2026-05-04  

---

## 1. Current State Analysis

### 1.1 `modules/users.nix`

```nix
# modules/users.nix
{ ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];
  };
}
```

- No SSH authorized keys are declared.
- The `nimda` user has no `openssh.authorizedKeys.*` options set.
- The module takes no arguments beyond the implicit `...`, so `lib` is not yet imported.

### 1.2 `modules/network.nix`

The SSH daemon is already configured and open:

```nix
services.openssh = {
  enable = true;
  settings = {
    PasswordAuthentication = false;  # key-based auth only
    PermitRootLogin        = "no";
  };
};
networking.firewall.allowedTCPPorts = [ 22 ];
```

- Password auth is already **disabled** — a key MUST be authorized before SSH becomes usable.
- Tailscale is also enabled; SSH is reachable over both LAN and Tailscale network.

### 1.3 `justfile` — Style and Conventions

| Property | Value |
|---|---|
| Shell | `#!/usr/bin/env bash` per recipe |
| Error handling | `set -euo pipefail` in every recipe |
| Indentation | 4 spaces |
| Variable syntax | `{{varname}}` for just parameters; `$VAR` for shell variables |
| Private recipes | `[private]` annotation; `_underscore_prefix` naming |
| Stderr errors | `echo "error: ..." >&2; exit N` |
| Variant detection | `cat /etc/nixos/vexos-variant 2>/dev/null` |
| Flake resolution | `just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}"` |
| Rebuild | `sudo nixos-rebuild switch --flake "path:${_flake_dir}#${TARGET}"` |

The `_resolve-flake-dir` private recipe probes candidates (`justfile()` dir, `/etc/nixos`, `$HOME/Projects/vexos-nix`) and returns the first one that contains the requested `nixosConfigurations` attribute.

### 1.4 `flake.nix` — Host Output Names

All 30 outputs follow the pattern `vexos-<role>-<gpu>` where:

- **roles:** `desktop`, `stateless`, `htpc`, `server`, `headless-server`
- **gpu variants:** `amd`, `nvidia`, `nvidia-legacy535`, `nvidia-legacy470`, `intel`, `vm`

The active host's output name is written to `/etc/nixos/vexos-variant` at every `nixos-rebuild switch` (via `environment.etc."nixos/vexos-variant".text`).

### 1.5 `scripts/preflight.sh` — What It Already Checks

The preflight performs 7 stages:

- [0/7] `nix` and `jq` availability  
- [1/7] `nix flake check --no-build --impure`  
- [2/7] `nixos-rebuild dry-build` for all 30 outputs  
- [3/7] `hardware-configuration.nix` is NOT git-tracked  
- [4/7] `system.stateVersion` present in all 5 `configuration-*.nix` files  
- [5/7] `flake.lock` committed, pinned, and fresh  
- [6/7] Nix formatting  
- [7/7] Secret scan  

The preflight has no SSH-specific checks. No changes to `preflight.sh` are required by this feature.

---

## 2. Problem Definition

The `nimda` user account has no SSH authorized keys in the NixOS configuration.
Because `PasswordAuthentication = false` is set in `network.nix`, SSH is entirely unusable
until at least one public key is authorized.

There is no automation in the repository to:
1. Generate an SSH key pair for `nimda`
2. Register the public key in the NixOS configuration declaratively
3. Rebuild and switch so the authorization takes effect

The goal is a single `just enable-ssh` recipe that performs all three steps idempotently.

---

## 3. Approach Evaluation

### Approach A — Repo-tracked `authorized_keys` file (RECOMMENDED)

Add an `authorized_keys` plain-text file at the repo root.  
Reference it in `modules/users.nix` via:

```nix
openssh.authorizedKeys.keyFiles =
  lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
```

The `just enable-ssh` recipe:
1. Generates `~/.ssh/id_ed25519` if it does not exist.
2. Appends the public key to `[repo_root]/authorized_keys` (idempotent — skips if already present).
3. Rebuilds with `sudo nixos-rebuild switch`.

**Pros:**
- No fragile sed/string manipulation of Nix syntax — only a plain text file is written.
- SSH public keys are not secrets; tracking them in git is safe, auditable, and useful for multi-machine deployment.
- `builtins.pathExists` guard means the build succeeds on fresh checkouts where the file does not yet exist.
- Multiple keys accumulate naturally in the file (one per line, standard `authorized_keys` format).
- The file is version-controlled and reviewable.
- Works with `path:` flake URLs (untracked local files are accessible; git-tracked files are accessible everywhere).

**Cons:**
- Requires committing `authorized_keys` to the repo to make the keys available when building from a git-committed revision.
- On first run the file is untracked; `nix flake check` with `--impure` includes it, and `nixos-rebuild switch --flake path:...` always resolves from the filesystem so the build works before a commit.

### Approach B — `keyFiles` pointing to `~/.ssh/id_ed25519.pub`

```nix
openssh.authorizedKeys.keyFiles = [ "/home/nimda/.ssh/id_ed25519.pub" ];
```

**Rejected because:**
- The file must exist on every machine at every `nixos-rebuild` invocation; if the key is absent the build fails.
- Absolute home-dir paths are fragile and host-specific.
- Loses the declarative nature — the key is not in version control.

### Approach C — `/etc/nixos/authorized_keys` (outside repo)

```nix
openssh.authorizedKeys.keyFiles =
  lib.optional (builtins.pathExists /etc/nixos/authorized_keys) /etc/nixos/authorized_keys;
```

**Rejected because:**
- Creates a hidden per-host dependency on a file outside the repository.
- Cannot be reviewed or audited through git history.
- Diverges from the project's "all configuration lives in tracked Nix modules" philosophy.
- The file would need to be manually reprovisioned on every new host.

---

## 4. Recommended Approach: Approach A

**Summary of changes:**

| File | Change |
|---|---|
| `modules/users.nix` | Add `lib` import + `openssh.authorizedKeys.keyFiles` with `builtins.pathExists` guard |
| `authorized_keys` (repo root) | New file; created/appended by the recipe at runtime; commit after first run |
| `justfile` | Add `enable-ssh` recipe |
| All other files | No changes required |

`flake.nix`, `network.nix`, any `configuration-*.nix`, and `preflight.sh` require **no modifications**.

---

## 5. Exact Changes Required

### 5.1 `modules/users.nix` — Add `lib` and `keyFiles`

**Current:**

```nix
{ ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];
  };
}
```

**New:**

```nix
# modules/users.nix
# Primary user account. Applies to all roles.
# Role-specific groups are appended by service modules (audio.nix, gaming.nix,
# virtualization.nix, etc.) via NixOS list merging.
{ lib, ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];

    # Declarative SSH authorized keys.
    # The authorized_keys file at the repo root is populated by `just enable-ssh`.
    # builtins.pathExists guard: the build succeeds on fresh checkouts where the
    # file has not yet been created.
    openssh.authorizedKeys.keyFiles =
      lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
  };
}
```

**Key notes:**
- `{ lib, ... }:` replaces `{ ... }:` to bring `lib` into scope for `lib.optional`.
- `../authorized_keys` is a Nix path literal. Since `users.nix` lives in `modules/`, `../` resolves to the repo root. Nix resolves path literals relative to the file in which they appear.
- `builtins.pathExists ../authorized_keys` evaluates to `true` when the file exists on the build host; `lib.optional false x` returns `[]`, so the list is empty and the build succeeds without the file.
- When `authorized_keys` exists, Nix copies it into the store at evaluation time and passes the store path to the SSH daemon's `authorized_keys` mechanism.

### 5.2 New File: `authorized_keys` (repo root)

This file does **not** need to be pre-created manually. The `just enable-ssh` recipe creates it on first run.

The file uses the standard OpenSSH `authorized_keys` format — one key per line, blank lines and `#` comment lines ignored by OpenSSH.

After the recipe runs, the user should `git add authorized_keys && git commit` so the key is available for future builds from git-committed revisions. (Builds using `path:` URLs work even before the file is committed.)

**Example contents after `just enable-ssh`:**

```
ssh-ed25519 AAAA... nimda@vexos-desktop-amd
```

### 5.3 `justfile` — `enable-ssh` Recipe

Insert the following recipe after the `rollforward` recipe and before the server services section. Follow all existing style conventions exactly.

```just
# Generate an SSH ed25519 key for nimda (if needed) and register it
# declaratively via authorized_keys, then rebuild the current variant.
# Safe to run multiple times — key generation and key registration are both idempotent.
# After first run: git add authorized_keys && git commit to persist the key.
enable-ssh:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "error: 'sudo' command not found. Use a Linux host with sudo configured." >&2
        exit 127
    fi
    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just enable-ssh must be run on Linux (NixOS target host)." >&2
        exit 1
    fi

    TARGET=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [ -z "$TARGET" ]; then
        echo "error: /etc/nixos/vexos-variant not found." >&2
        echo "       Run 'just switch' first to build and activate a vexos variant." >&2
        exit 1
    fi

    KEY_FILE="$HOME/.ssh/id_ed25519"
    PUB_FILE="${KEY_FILE}.pub"

    # ── Step 1: Generate key pair if not present ──────────────────────────
    if [ ! -f "$KEY_FILE" ]; then
        echo "Generating SSH ed25519 key pair for $USER..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "${USER}@$(hostname)"
        echo "Key written: $PUB_FILE"
    else
        echo "SSH key already exists: $PUB_FILE (skipping generation)"
    fi

    PUB_KEY=$(cat "$PUB_FILE")

    # ── Step 2: Append public key to authorized_keys (idempotent) ─────────
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")
    AUTH_KEYS="${_jf_dir}/authorized_keys"

    if [ ! -f "$AUTH_KEYS" ]; then
        echo "Creating ${AUTH_KEYS}..."
        touch "$AUTH_KEYS"
    fi

    if grep -qF "$PUB_KEY" "$AUTH_KEYS" 2>/dev/null; then
        echo "Public key already present in authorized_keys (skipping append)"
    else
        echo "$PUB_KEY" >> "$AUTH_KEYS"
        echo "Public key appended to authorized_keys"
        echo ""
        echo "Reminder: commit the updated authorized_keys file to persist the key:"
        echo "  git add authorized_keys && git commit -m 'chore: register nimda SSH key'"
    fi

    # ── Step 3: Rebuild and switch ─────────────────────────────────────────
    echo ""
    echo "Rebuilding: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "")
    sudo nixos-rebuild switch --flake "path:${_flake_dir}#${TARGET}"

    echo ""
    echo "SSH enabled. Connect with: ssh nimda@$(hostname)"
    echo ""
```

---

## 6. Rebuild Target Strategy

The recipe reads `/etc/nixos/vexos-variant` to obtain the active target (e.g., `vexos-desktop-amd`).
This file is written by every `nixos-rebuild switch` invocation via the `variantModule` in `flake.nix`:

```nix
{ environment.etc."nixos/vexos-variant".text = "${name}\n"; }
```

This is the same detection strategy used by the `default`, `update`, and `rollback` recipes.

If the file is absent (e.g., a fresh machine that has never been switched, or a stateless
variant after a reboot before the persistent layer is active), the recipe aborts with a clear
error instructing the user to run `just switch` first.

The `_resolve-flake-dir` helper is reused unchanged — it probes the justfile directory,
`/etc/nixos`, and `$HOME/Projects/vexos-nix` in order and returns the first one that
contains `nixosConfigurations.${TARGET}`.

The rebuild uses `path:${_flake_dir}#${TARGET}` (the `path:` prefix forces Nix to read from
the filesystem, not from git objects), which means the freshly-written `authorized_keys` file
is included even before it is committed.

---

## 7. `nix flake check` Requirement

`nix flake check` does **not** need to be run as part of this recipe.

`sudo nixos-rebuild switch` performs full Nix evaluation of the affected configuration,
which catches all type errors, missing files, and evaluation failures. Running `nix flake
check` before the switch would evaluate all 30 outputs and would be redundant and slow.

The preflight script (`scripts/preflight.sh`) already runs `nix flake check --no-build
--impure` as its [1/7] check — that is the appropriate gate before a `git push`, not before
every `nixos-rebuild switch`.

---

## 8. Edge Cases

| Scenario | Behavior |
|---|---|
| Key already exists at `~/.ssh/id_ed25519` | Generation skipped; public key is read and processed normally |
| Public key already in `authorized_keys` | `grep -qF` match prevents duplicate append; idempotent no-op |
| `authorized_keys` file does not exist | `touch` creates an empty file before appending |
| Running as root (not as `nimda`) | `$HOME` resolves to `/root` — key is generated at `/root/.ssh/id_ed25519.pub`; NixOS will authorize that root key for `nimda` login, which is wrong. **Mitigation:** The recipe uses `$USER` in the key comment; add a warning if `$USER = root` |
| `vexos-variant` absent (stateless post-reboot) | Recipe exits with error; user is directed to run `just switch` first |
| `authorized_keys` not yet git-tracked | Rebuild uses `path:` URL so the file is resolved from the filesystem directly; build succeeds without a commit |
| Multiple machines / multiple keys | Each `just enable-ssh` run appends one key; all keys accumulate in `authorized_keys`; all are authorized |
| `_resolve-flake-dir` cannot find flake | Existing error handling in `_resolve-flake-dir` triggers; exits with `error: no flake provided target '...'` |
| `ssh-keygen` not available | `set -euo pipefail` causes the recipe to abort with a non-zero exit |

### 8.1 Root User Warning

Add a guard immediately after the `TARGET` detection block:

```bash
if [ "$(id -u)" -eq 0 ]; then
    echo "warning: running as root — SSH key will be generated at /root/.ssh/." >&2
    echo "         Consider running as nimda: sudo -u nimda just enable-ssh" >&2
fi
```

This is a warning, not a hard abort, to allow power users who intentionally run as root to proceed.

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `authorized_keys` not committed; git push rebuilds from store and loses the key | Medium | Recipe prints a `git add / git commit` reminder after every new key append |
| `builtins.pathExists ../authorized_keys` evaluated at the wrong relative path | Medium | Path is relative to `modules/users.nix`; `../` correctly resolves to repo root — this is standard Nix path resolution; verify with `nix eval --impure '.#nixosConfigurations.vexos-desktop-amd.config.users.users.nimda.openssh.authorizedKeys.keyFiles'` |
| Nix copies `authorized_keys` content into the store, so keys in old closures are permanent | Low | This is the intended NixOS behavior — removing a key from `authorized_keys` and rebuilding is the revocation mechanism |
| Recipe run on wrong machine (wrong variant in vexos-variant) | Low | `_resolve-flake-dir` validates the target exists; worst case is rebuilding the already-active variant, which is safe |
| Empty `authorized_keys` file after `touch` but before append causes build with no keys | Low | `lib.optional (builtins.pathExists ...)` still returns a file path even for an empty file; NixOS will authorize zero keys (equivalent to no SSH access), which is the correct state before the append completes — `set -euo pipefail` ensures the recipe never exits between `touch` and the append without failing |
| Line endings: `authorized_keys` created on Windows with CRLF | Low | Recipe runs on NixOS (Linux); `>>` redirection writes LF. If the repo is ever checked out on Windows and the file edited there, OpenSSH silently ignores malformed key lines — the usual repo `.gitattributes` `text eol=lf` convention covers this |

---

## 10. Implementation Checklist

- [ ] Modify `modules/users.nix`: add `lib` to argument set; add `openssh.authorizedKeys.keyFiles` with `builtins.pathExists` guard
- [ ] Add `enable-ssh` recipe to `justfile` at the position described in §5.3
- [ ] Verify recipe position: after `rollforward`, before `# ── Server Services Management ───`
- [ ] Verify `authorized_keys` file is NOT pre-created in the implementation — the recipe creates it at runtime
- [ ] `flake.nix` — no changes
- [ ] `network.nix` — no changes
- [ ] `configuration-*.nix` files — no changes
- [ ] `preflight.sh` — no changes
- [ ] Test rebuild evaluates `openssh.authorizedKeys.keyFiles` correctly when `authorized_keys` is present
- [ ] Test rebuild succeeds (empty `keyFiles`) when `authorized_keys` is absent

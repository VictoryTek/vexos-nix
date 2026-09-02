# justfile: unguarded `openssl` calls fail on hosts without it on PATH — Spec

## Current state analysis

The `enable` recipe in `justfile` (private recipe starting at line ~2429) contains four
bare invocations of `openssl` used to generate secrets non-interactively:

- `justfile:2699` — `openssl rand -base64 48 | sudo tee "$_backup_pw_file" > /dev/null`
  (interactive `just enable backup` path, generates restic password when the user
  didn't already have one)
- `justfile:2740` / `justfile:2741` — `$(openssl rand -hex 32)` ×2, inside the
  Arcane-specific block, generating `ENCRYPTION_KEY` / `JWT_SECRET` for
  `/etc/nixos/secrets/arcane-env`
- `justfile:2839` — `openssl rand -base64 48 | sudo tee "$pw_default" > /dev/null`,
  inside `_ensure_backup_defaults()`, the non-interactive auto-enable-backups path
  that runs for the *first* service enabled on a host

All four assume `openssl` is already resolvable on the invoking user's `$PATH`. That
is not guaranteed — this justfile is meant to run on a freshly-installed VexOS host
before a full rebuild has necessarily pulled in every CLI tool, and on the reporting
VM `openssl` was not on PATH, causing:

```
/run/user/1000/just/just-oqKKof/enable: line 2839: openssl: command not found
error: recipe `enable` failed with exit code 127
```

Because `_ensure_backup_defaults` runs *after* `vexos.server.backup.enable = true` is
already written to `/etc/nixos/server-services.nix` (justfile:2857-2860), the crash
mid-helper leaves `backup.enable = true` persisted with no `passwordFile` populated —
a broken half-state — and also skips the `"  + Backups also enabled..."` echo at
justfile:2863, which is why the next `just enable searxng` run showed no backup
message (the guard at justfile:2856 saw backups already "enabled" and did nothing).

The repo already has an established precedent for exactly this problem: `secrets-init`
(justfile:1744-1758) needs `age-keygen`, which also isn't guaranteed to be on PATH, so
it runs it via `sudo nix shell nixpkgs#age -c age-keygen ...` instead of a bare call.

## Problem definition

Bare `openssl` calls in the `enable` recipe fail with "command not found" on any host
where `openssl` isn't already on the invoking shell's PATH, aborting `just enable`
partway through and leaving `server-services.nix` in an inconsistent state (backup
enabled with no password file).

## Proposed solution

Apply the same fix used for `age-keygen` in `secrets-init`: wrap each bare `openssl`
call in `sudo nix shell nixpkgs#openssl -c openssl ...`, guaranteeing the binary is
available regardless of host PATH, without adding `openssl` as a permanent system
package (surgical, matches existing project convention, no new module or flake
changes needed).

This is a shell-script-level (justfile) change only — no `.nix` module changes, no new
flake inputs. Module Architecture Pattern (Option B) does not apply here since no NixOS
module is touched.

## Implementation steps

In `justfile`, replace:

1. Line 2699:
   `openssl rand -base64 48 | sudo tee "$_backup_pw_file" > /dev/null`
   →
   `sudo nix shell nixpkgs#openssl -c openssl rand -base64 48 | sudo tee "$_backup_pw_file" > /dev/null`

2. Lines 2740-2741:
   `printf 'ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)"`
   `printf 'JWT_SECRET=%s\n' "$(openssl rand -hex 32)"`
   →
   `printf 'ENCRYPTION_KEY=%s\n' "$(sudo nix shell nixpkgs#openssl -c openssl rand -hex 32)"`
   `printf 'JWT_SECRET=%s\n' "$(sudo nix shell nixpkgs#openssl -c openssl rand -hex 32)"`

3. Line 2839:
   `openssl rand -base64 48 | sudo tee "$pw_default" > /dev/null`
   →
   `sudo nix shell nixpkgs#openssl -c openssl rand -base64 48 | sudo tee "$pw_default" > /dev/null`

Leave the comment at justfile:2819 and the help text at justfile:3379 (`echo "...
openssl rand -base64 48"`) untouched — the latter is user-facing copy-paste guidance
for a command the user runs themselves in their own shell, not a recipe invocation.

## Dependencies

None — `nixpkgs#openssl` is resolved ad hoc via `nix shell`, same as `nixpkgs#age`
already is elsewhere in this file. No Context7 lookup needed (no external library
integration, just a CLI flag already used elsewhere in this exact repo).

## Configuration changes

None.

## Risks and mitigations

- **Risk:** `sudo nix shell nixpkgs#openssl -c ...` requires network/cache access on
  first use if `openssl` isn't already in the local Nix store.
  **Mitigation:** `openssl` is a near-universal transitive dependency already in the
  Nix store on virtually any NixOS system (pulled in by systemd, curl, etc.), so this
  is a non-issue in practice, and matches the risk profile already accepted for
  `nixpkgs#age` in `secrets-init`.
- **Risk:** none to `server-services.nix` state format — no changes to what gets
  written, only to how the binary is located.
- **Out of scope / not fixed here:** the already-broken state left on the reporting VM
  (`backup.enable = true` with no `passwordFile`) — user has confirmed this VM is
  disposable/for testing and does not need remediation.

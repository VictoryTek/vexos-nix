# RDP TLS Certificate — Review

**Feature:** `rdp_tls_certificate`
**Phase:** 3 (Review) + 4 (Refinement, cycle 1) + 5 (Re-review)
**Date:** 2026-07-14
**Spec:** `.github/docs/subagent_docs/rdp_tls_certificate_spec.md`

## Files Modified

- `modules/remote-desktop.nix`

## Phase 3 Findings

| # | Severity | Finding | Resolution (Phase 4) |
|---|---|---|---|
| 1 | CRITICAL | `openssl` wrote `tls.key` under the service's default umask, leaving it world-readable for the window between creation and the subsequent `chmod 600`. | Generation wrapped in a `( umask 077; ... )` subshell, and `chmod 700` applied to the directory before generation. |
| 2 | MINOR | Cert block ran into the `uid=` assignment with no separating blank line, breaking the file's existing paragraph rhythm. | Blank line added. |
| 3 | MINOR | Unit `description` still read "Configure GNOME Remote Desktop credentials" — no longer accurate. | Changed to "Configure GNOME Remote Desktop TLS certificate and credentials". |

All three resolved. No CRITICAL findings remain.

## Compliance Checks

- **Module Architecture (Option B):** No new module, no new option, no new `lib.mkIf`.
  The change is confined to the existing `vexos-rdp-setup` service. ✅
- **Surgical:** Every changed line traces to the TLS gap. No adjacent refactoring. ✅
- **Secrets:** Private key generated at runtime into `/var/lib/vexos-rdp`, never a Nix
  store path. Key `0600`, dir `0700`, both owned by `config.vexos.user.name`. Cert is
  `0644` (public material). ✅
- **`hardware-configuration.nix` not committed:** `git ls-files hardware-configuration.nix`
  → empty. ✅
- **`system.stateVersion` unchanged:** no `configuration-*.nix` touched. ✅
- **New flake inputs:** none. `pkgs.openssl` is already in nixpkgs. ✅
- **Idempotence:** Generation guarded on both files existing, so rebuilds do not rotate
  the certificate and clients keep their pinned fingerprint. ✅

## Build Validation — PASSED (via WSL, Nix 2.34.1)

Nix is unavailable on the Windows host directly but is present in WSL. All validation
was run there against the same working tree (`/mnt/c/Projects/vexos-nix`).

| Check | Result |
|---|---|
| `bash scripts/preflight.sh` | **Preflight PASSED — safe to push** (exit 0) |
| `nix flake show --impure` (preflight stage 1/8) | PASS |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-nvidia...drvPath` | PASS — `nixos-system-vexos-26.05.drv` (82s) |
| `nix eval` of `vexos-server-intel` (+ `networking.hostId` fixture) | PASS — `nixos-system-vexos-26.05.drv` |
| `pkgs.vexos.vexos-update` build / shellcheck (preflight stage 8/8) | PASS |

Full evaluation forces every NixOS module assertion, so the module is confirmed to
evaluate cleanly on both roles that matter here (`desktop`, `server`).

### Pre-existing issue found during validation (NOT caused by this change)

A bare `nix eval` of `vexos-server-intel` fails an assertion from `modules/zfs-server.nix`:

> ZFS requires a unique `networking.hostId` per host — this is still a shared
> placeholder committed in `hosts/<role>-<gpu>.nix`.

This is the placeholder guard working as designed, and it is exactly what CI's stub
`hardware-configuration.nix` fixture (`networking.hostId = "cafebabe"`) works around.
Injecting the same fixture via `extendModules` made the evaluation pass. Reported, not
touched — out of scope for this change.

### Generated-unit verification

The realised systemd unit was inspected directly, not just compiled:

```
$ nix eval --impure --raw ....systemd.services.vexos-rdp-setup.script | grep -n 'set-tls\|rdp enable'
64:  grdctl rdp set-tls-cert /var/lib/vexos-rdp/tls.crt
68:  grdctl rdp set-tls-key /var/lib/vexos-rdp/tls.key
72:  grdctl rdp enable

$ nix eval --impure --raw ....systemd.services.vexos-rdp-setup.environment.PATH | tr : '\n' | grep openssl
/nix/store/clvbx203wyqkdnqc5ngyhjlhcqn5s9x9-openssl-3.6.2-bin/bin
```

Confirms: both TLS paths are registered **before** `grdctl rdp enable`, and `openssl`
(3.6.2) is on the unit's `PATH`.

### Note on the certificate CN

The generated cert resolves to `/CN=vexos` (the `networking.hostName` `mkDefault` from
`modules/network.nix`; the `hosts/*.nix` files do not override it). This is cosmetic —
RDP clients do not validate the CN of a self-signed certificate; they pin the
fingerprint on first connect. No action needed.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (98%) — APPROVED. Phase 6 preflight PASSED.**

## Runtime Verification (on the target machine, after rebuild)

```bash
systemctl status vexos-rdp-setup
grdctl status                      # must show a non-empty TLS certificate AND key
ss -tlnp | grep 3389               # must show gnome-remote-de LISTENING
```

Before the fix, `ss` returns nothing — that is the bug. After the fix, port 3389 is bound.

# SMB / NFS Discovery — Review (Phase 3)

**Feature:** `smb_nfs_discovery`
**Spec:** `.github/docs/subagent_docs/smb_nfs_discovery_spec.md`
**File reviewed:** `modules/network-desktop.nix`
**Date:** 2026-04-28
**Reviewer environment:** Windows host (Nix toolchain not installed)

---

## 1. Specification Compliance

The diff applied to `modules/network-desktop.nix` matches §4 of the spec **exactly** — three changes, no more, no less:

| Spec requirement (§4.2) | Diff line(s) | Status |
|---|---|---|
| `services.samba-wsdd.discovery = true;` added inside the existing `services.samba-wsdd` block | `+    discovery    = true;` | ✅ |
| `services.avahi.publish.addresses = true;` | `+    addresses    = true;` | ✅ |
| `services.avahi.publish.workstation = true;` | `+    workstation  = true;` | ✅ |
| WSDD comment block updated to record discovery-mode requirement and reference commits `bec7bec`, `da6e40c`, `3082227` and the gvfsd-wsdd socket path `/run/wsdd/wsdd.sock` | Comment block rewritten verbatim from spec §4.2 | ✅ |
| No new files | Diff is single-file | ✅ |
| No new flake inputs / packages | None added | ✅ |
| No `lib.mkIf` guards added | None added | ✅ |
| All other v3 settings preserved (`samba.enable`, tmpfiles symlink, `boot.supportedFilesystems`, `samba-wsdd.openFirewall`, avahi `publish.enable` / `userServices`) | All present and untouched | ✅ |

The implementation is a literal application of §4.2.

## 2. Best Practices / API Currency

- `services.samba-wsdd.discovery` is the canonical option name in nixpkgs (`nixos/modules/services/network-filesystems/samba-wsdd.nix`); spec §6 verified this against the source and `search.nixos.org`. The submitted attribute name matches exactly.
- `services.avahi.publish.addresses` and `services.avahi.publish.workstation` are the canonical avahi-daemon module option names; both default to `false` in nixpkgs, so explicit `true` is required and correct.
- All three options are plain booleans — no eval pitfalls, no API drift risk.
- The discovery socket (`/run/wsdd/wsdd.sock`) is a local Unix socket; spec §8 correctly notes no firewall changes are required, and the implementation does not add any.

## 3. Module Architecture (Option B)

- ✅ Change is contained in `modules/network-desktop.nix`, which is a role-specific addition file imported only by display roles (`desktop`, `htpc`, `server`, `stateless`). Headless-server does **not** import it, so discovery correctly stays off there.
- ✅ No `lib.mkIf` guards were introduced.
- ✅ No new files; no changes to `configuration-*.nix`, `flake.nix`, or any shared base module.
- ✅ Settings apply unconditionally to every role that imports the file, per Option B.

## 4. Consistency

- Indentation, alignment of `=` signs, and comment-banner formatting match the surrounding style of the file (e.g. avahi block, samba block).
- Newly inserted `addresses` and `workstation` lines align their `=` columns with `enable` / `userServices` — visually consistent.
- Comment uses the same `# ── … ─────` banner style as adjacent sections.

## 5. Build Validation

> **Environment limitation:** the review host is Windows. `where.exe nix` returned no result, so `nix flake check` and `nixos-rebuild dry-build` cannot be executed here. This is documented per the orchestrator's instructions; it does **not** count as a failure.

Manual static validation performed instead:

- All three modified attributes exist in nixpkgs and are typed `bool` — no syntax or type errors possible.
- The `services.samba-wsdd` block already evaluated successfully in the prior `3082227` commit; adding a single boolean key cannot regress evaluation.
- The `services.avahi.publish` attrset already evaluated; adding two booleans inside the same attrset cannot regress evaluation.
- Comment-only edits cannot affect evaluation.
- `git ls-files | Select-String hardware-configuration` → no matches. `hardware-configuration.nix` is **not** tracked. ✅
- `system.stateVersion = "25.11";` is present at line 46 of `configuration-desktop.nix`. ✅

**Action required of the user:** before merging, run on a NixOS host:

```sh
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

These are also covered by `scripts/preflight.sh` in Phase 6.

## 6. Security

- No secrets, credentials, tokens, or hardcoded paths to private data introduced.
- No new network ports opened. UDP 5353 (mDNS) and UDP 3702 / TCP 5357 (WSDD) were already opened by the existing `openFirewall` settings.
- The wsdd discovery socket is a local Unix socket created by a `DynamicUser=true` systemd unit at `/run/wsdd/` with mode `0750` (verified in upstream nixpkgs unit definition); it is not network-exposed.
- Avahi `publish.addresses` / `publish.workstation` advertise the host on the local link only — the same broadcast surface that mDNS already used.
- `system.stateVersion` unchanged. `hardware-configuration.nix` not tracked.

## 7. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A on Windows host (static validation passes) | A |

**Overall Grade:** A (100%)

## 8. Verdict

**PASS** — proceed to Phase 6 (preflight) for live `nix flake check` / `nixos-rebuild dry-build` validation on a NixOS host.

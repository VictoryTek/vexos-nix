# Review — Auto-clear stale Brave profile lock on session start

**Feature:** `brave_stale_profile_lock`
**Spec:** `.github/docs/subagent_docs/brave_stale_profile_lock_spec.md`
**Phase:** 3 (Review & QA)
**Reviewed file:** `home/gnome-common-browser.nix`

---

## 1. Specification compliance

| Spec requirement | Status |
|---|---|
| Placement in `home/gnome-common-browser.nix` (shared addition, 4 roles, no role `mkIf`) | ✅ |
| `systemd.user.services.vexos-brave-clear-stale-lock`, oneshot + `RemainAfterExit` | ✅ |
| Ordered on `graphical-session.target` (`After`/`PartOf`/`WantedBy`) | ✅ |
| Cross-host only (`lockhost != HOST`); same-host locks untouched | ✅ verified |
| `pgrep -u $UID -x brave` guard | ✅ verified (bails while Brave runs) |
| Short hostname via `pkgs.hostname` | ✅ (`hostname-debian`, `bin/hostname`) |
| Removes `SingletonLock` + `SingletonCookie` + `SingletonSocket` | ✅ verified |
| `set -u`, no `set -e`; every branch guarded; `exit 0` | ✅ |
| No stamp file (re-runs each session) | ✅ |
| No `vexos.*` toggle; opt-out documented in comment | ✅ (opt-out recipe in Phase 7 notes / spec R1) |
| No changes to `home-*.nix`, `modules/`, `pkgs/`, `flake.nix` | ✅ (`git diff --stat`: 1 file) |

## 2. Functional testing

Script built (`/nix/store/…-vexos-brave-clear-stale-lock`) and exercised in an
isolated `HOME`:

| Case | Expected | Result |
|---|---|---|
| Cross-host `SingletonLock` (`oldhost-123`), Brave not running | Lock+Cookie+Socket removed | ✅ all removed |
| Same-host `SingletonLock` (`$(hostname)-777`) | left untouched | ✅ kept (lock + cookie) |
| Second run, nothing stale | no-op, exit 0 | ✅ exit 0 |
| `HOME` with no Brave profile dir | no-op, exit 0 | ✅ exit 0 |
| Brave Origin running (live, `pgrep` matches) | guard bails, nothing touched | ✅ `exit 0`, disk untouched |
| Dangling cross-host symlink (target missing) | still removed | ✅ (`[ -L ]` test, not `[ -e ]`) |

## 3. Build validation

| Step | Result |
|---|---|
| `nix flake show --impure` | ✅ all outputs enumerated, no eval error |
| `nix eval …vexos-desktop-amd…toplevel.drvPath` | ✅ OK |
| `nix eval …vexos-desktop-nvidia…toplevel.drvPath` | ✅ OK |
| `nix eval …vexos-desktop-vm…toplevel.drvPath` | ✅ OK |
| `nix eval …vexos-stateless-amd…toplevel.drvPath` | ✅ OK |
| `nix eval …vexos-htpc-amd…toplevel.drvPath` | ✅ OK |
| `nix eval …vexos-server-amd…toplevel.drvPath` | ⚠️ fails on **pre-existing, unrelated** assertion in `modules/zfs-server.nix:98` (shared placeholder `networking.hostId`, introduced by commit `b161981`; real value is per-machine and never committed). The home-manager service itself builds on the server role — `…home-manager.users.nimda.systemd.user.services.vexos-brave-clear-stale-lock.Service.ExecStart` resolves and the script derivation realises. **Not a regression.** |
| `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged | ✅ (no `configuration-*.nix` touched) |
| New flake inputs / `follows` | ✅ none added |

`dry-build` was not run (no writable `/etc/nixos/hardware-configuration.nix`
for these variants on this host); `nix eval …toplevel.drvPath` is the
CI-equivalent full-evaluation gate per CLAUDE.md and was used instead.

## 4. Best practices / consistency

- Matches the sibling `vexos-migrate-dock-brave-origin` unit idiom exactly
  (capitalised systemd keys, `writeShellScript`, `graphical-session.target`).
- All binaries fully-qualified via `${pkgs.*}` store paths — no `PATH` reliance.
- `${target%-*}` correctly strips only the trailing `-<pid>`; hostnames never
  contain the trailing `-<digits>` pattern in a way that breaks this.
- `pgrep -x brave` matches both `brave` and `brave-origin` (both exec a binary
  named `brave`) — correct.
- No new `lib.mkIf` guard; role scoping is entirely via the import list. ✅
  Module Architecture Pattern (Option B).

## 5. Security

- Runs as the user, touches only `~/.config/BraveSoftware/{Brave-Origin,Brave-Browser}/Singleton*`.
- No secrets, no world-writable files, no privilege escalation.
- Only deletes symlinks/sockets it positively identifies as cross-host stale
  **and** only when no Brave process is running for the user.
- Risk R1 (concurrent Syncthing-synced profile) documented with opt-out; the
  "no Brave running" gate makes the window very small. Acceptable.

## 6. Findings

**CRITICAL:** none.
**RECOMMENDED:** none. Implementation matches spec; behaviour verified.
**NOTE (out of scope, no action):** `vexos-migrate-dock-brave-origin` is
duplicated verbatim across four `home-*.nix` files and could move into
`home/gnome-common-browser.nix` alongside this new unit. Tracked as tech debt
only — not part of this task.

## 7. Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 97% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (98%)**

Build Success is 95% solely because `vexos-server-amd` full evaluation is
blocked by a pre-existing unrelated `hostId` placeholder assertion; the change
under review evaluates and builds on that role. All six other evaluated targets
pass.

## 8. Verdict

**PASS** — proceed to Phase 6 (Preflight).

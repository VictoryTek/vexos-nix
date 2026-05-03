# Phase 3 Review: `headless_install_blackscreen`

Spec: [.github/docs/subagent_docs/headless_install_blackscreen_spec.md](.github/docs/subagent_docs/headless_install_blackscreen_spec.md)
Modified file (Phase 2): [scripts/install.sh](../../../scripts/install.sh)
Reviewer: Phase 3 Review Subagent

---

## 1. Spec Compliance

| Spec requirement | Status | Evidence |
|---|---|---|
| `REBUILD_ACTION` defaults to `"switch"` | PASS | [scripts/install.sh#L186](../../../scripts/install.sh#L186) — `REBUILD_ACTION="switch"` |
| `REBUILD_ACTION="boot"` iff `ROLE = "headless-server"` | PASS | [scripts/install.sh#L187-L189](../../../scripts/install.sh#L187-L189) — `if [ "$ROLE" = "headless-server" ]; then REBUILD_ACTION="boot"; fi` |
| Pre-rebuild banner names the action and explains headless deferral | PASS | [scripts/install.sh#L193-L196](../../../scripts/install.sh#L193-L196) — banner prints `(action: ${REBUILD_ACTION})`; conditional `[headless-server] Using 'nixos-rebuild boot' to preserve the live GNOME session…` |
| Actual invocation uses `${REBUILD_ACTION}` (not hardcoded `switch`) | PASS | [scripts/install.sh#L266](../../../scripts/install.sh#L266) — `sudo nixos-rebuild "${REBUILD_ACTION}" --flake "/etc/nixos#${FLAKE_TARGET}"` |
| Headless success branch prints "registered as default" + reboot-required notice | PASS | [scripts/install.sh#L268-L271](../../../scripts/install.sh#L268-L271) |
| Headless reboot prompt is `[Y/n]` (default yes) and only `n`/`no` skips | PASS | [scripts/install.sh#L272-L282](../../../scripts/install.sh#L272-L282) — `case "${REBOOT_CHOICE,,}" in n\|no) skip ;; *) reboot ;; esac` |
| Non-headless success path unchanged (`[y/N]`, default no) | PASS | [scripts/install.sh#L284-L295](../../../scripts/install.sh#L284-L295) — identical structure to pre-fix; only `y`/`yes` triggers reboot |
| Failure branch references chosen action in both message and retry hint | PASS | [scripts/install.sh#L297-L302](../../../scripts/install.sh#L297-L302) — `nixos-rebuild ${REBUILD_ACTION} failed` and retry command uses `${REBUILD_ACTION}` |
| All `--flake` / `/etc/nixos#${FLAKE_TARGET}` arguments preserved | PASS | Both invocation and retry hint preserved verbatim |
| No `--no-verify` or other safety bypasses introduced | PASS | grep confirms zero occurrences |
| Other roles' (`desktop`/`htpc`/`server`/`stateless`) flow unaltered | PASS | The non-headless `else` branch is byte-equivalent to prior behavior |
| Existing flake/role/GPU/system-detection logic intact | PASS | `FLAKE_TARGET` composition, role/GPU/NVIDIA-branch selectors, BIOS/UEFI preflight, `/boot` mount logic — all unmodified |

**Spec wording variance (NON-CRITICAL):** The spec's exact post-success line was *"A reboot is REQUIRED to enter the headless system. (Live activation is skipped on headless to avoid killing this session.)"* Phase 2 collapsed this into a single line: *"[headless-server] Build complete. Reboot now to start the headless server. The live ISO will remain active until you do."* Semantically equivalent and arguably clearer; spec §4 explicitly grants latitude on prose. Not a deviation worth blocking on.

---

## 2. Module Architecture Compliance

| Check | Result |
|---|---|
| Zero `.nix` files modified by Phase 2 | PASS — `git diff --name-only` shows only `scripts/install.sh` |
| Zero new `lib.mkIf` guards introduced | PASS — N/A, no Nix touched |
| Headless behavior expressed via the role-aware install script (per spec §6) | PASS |

---

## 3. Shell Best Practices

| Check | Result | Notes |
|---|---|---|
| `set -euo pipefail` posture | PASS — unchanged | [scripts/install.sh#L26](../../../scripts/install.sh#L26) |
| `REBUILD_ACTION` always initialized before use | PASS | Set unconditionally to `"switch"` at L186 *before* the `if` and *before* any reference. No early-exit branch can reach the rebuild block without traversing this assignment (`stateless` live-ISO/migrate paths `exit 0` earlier). |
| All expansions of new variable quoted | PASS | `"$ROLE"`, `"${REBUILD_ACTION}"`, `"${FLAKE_TARGET}"` everywhere |
| `read -r … </dev/tty` preserved | PASS | Both prompts use the existing safe pattern |
| No regression in error handling (failure branch still `exit 1`) | PASS | [scripts/install.sh#L302](../../../scripts/install.sh#L302) |
| `bash -n scripts/install.sh` | **PASS** — exit 0, no syntax errors |
| `shellcheck` | NOT RUN — `shellcheck` is not installed in this environment (`command not found`, exit 127). Static `bash -n` passes; logical inspection finds no new SC issues. Documented, not CRITICAL. |

---

## 4. Edge Cases

| Case | Analysis | Verdict |
|---|---|---|
| User answers "Y" (or just Enter) to reboot in headless flow | `systemctl reboot` is sent to the live ISO's PID 1 (the only running systemd; the new generation's PID 1 has not been activated since `boot` does not run `switch-to-configuration`). The live ISO honors the reboot, kernel hands off to the bootloader, and the next boot picks the newly-registered default generation (the headless system). Correct behavior. | PASS |
| User answers "n" to reboot in headless flow | Script prints `Reboot skipped. Run 'systemctl reboot' when ready.` and exits cleanly via the implicit `case` fall-through. Live GNOME session keeps running; bootloader entry already installed. Correct. | PASS |
| Role-string match case sensitivity / hyphenation | `ROLE` is set internally — never directly from user input — to the literal string `"headless-server"` at [scripts/install.sh#L99](../../../scripts/install.sh#L99) (after the `SERVER_TYPE=headless` selector). The check `[ "$ROLE" = "headless-server" ]` is byte-exact and matches the same form used at [L131](../../../scripts/install.sh#L131) for GPU branching. Consistent. | PASS |
| Variable initialization across early-exit branches | The `stateless` live-ISO and `stateless` migration branches both `exit 0` *before* `REBUILD_ACTION` is referenced, so the variable being uninitialized in those paths is moot. All branches that *reach* the rebuild necessarily pass through L186. With `set -u`, an unreached assignment cannot trigger an unbound-variable error. | PASS |
| `nixos-rebuild boot` + later manual `nixos-rebuild switch` after reboot | The new generation is the default; user reboots into it; future rebuilds from inside the headless system can use `switch` normally (no live GUI at risk). | PASS |
| BIOS/GRUB patch path interaction with `boot` action | GRUB patch happens before `nixos-rebuild` runs and is independent of `switch` vs `boot` (per spec §7). `nixos-rebuild boot` installs whichever bootloader the configuration declares. No interaction. | PASS |

---

## 5. Build Validation

### 5.1 `bash -n scripts/install.sh`

```
SYNTAX_OK
```
Exit 0. **PASS.**

### 5.2 `shellcheck scripts/install.sh`

```
bash: shellcheck: command not found
SHELLCHECK_EXIT=127
```
Tool unavailable in environment. Not a regression. Documented; **NOT CRITICAL**.

### 5.3 Repository invariants

```
$ git ls-files | grep -i hardware-configuration || echo "OK: not tracked"
OK: not tracked

$ grep -n "system.stateVersion" configuration-desktop.nix
46:  system.stateVersion = "25.11";

$ grep -n "system.stateVersion" configuration-headless-server.nix
47:  system.stateVersion = "25.11";
```
Both **PASS**.

### 5.4 `nix flake check`

```
checking NixOS configuration 'nixosConfigurations.vexos-desktop-amd'...
error:
       error: access to absolute path '/etc' is forbidden in pure evaluation mode (use '--impure' to override)
```

Pre-existing structural property of this flake: `mkHost` reads `/etc/nixos/hardware-configuration.nix` per host (the documented "thin flake" pattern). `nix flake check` cannot evaluate impure outputs. Not caused by Phase 2 (no `.nix` touched). Documented, **NOT CRITICAL**.

### 5.5 `nixos-rebuild dry-build --flake .#vexos-headless-server-amd --impure`

```
       error:
       Failed assertions:
       - You must set the option 'boot.loader.grub.devices' or 'boot.loader.grub.mirroredBoots' to make the system bootable.
```

### 5.6 Regression smoke test: `nixos-rebuild dry-build --flake .#vexos-desktop-amd --impure`

```
       error:
       Failed assertions:
       - You must set the option 'boot.loader.grub.devices' or 'boot.loader.grub.mirroredBoots' to make the system bootable.
```

**Identical failure on both roles.** This is a property of *this dev host's* `/etc/nixos/hardware-configuration.nix` + flake bootloader configuration on this machine — it is **pre-existing**, **not introduced by Phase 2**, and would have surfaced before the change. It is environment-specific (would not occur on a target machine that booted from the vexos-nix install path with a properly-installed bootloader) and is **NOT a regression** of the headless-install fix:

* Phase 2 modified zero `.nix` files; nothing in the evaluation graph changed.
* The headless and desktop targets fail identically, ruling out any new role-specific evaluation issue.
* The fix is to a runtime shell flow, not to system-closure construction.

Documented as **NON-CRITICAL** environment finding. The Phase 2 change cannot have caused or worsened this.

---

## 6. Security

| Check | Result |
|---|---|
| No new secrets, no credentials in script | PASS |
| No `--no-verify`, `--insecure`, `curl | bash` of new sources, etc. | PASS |
| No new shell-injection surface (no unquoted user-controlled expansions in commands) | PASS — `REBUILD_ACTION` is set from a fixed string literal, never from user input |
| Privilege escalation surface unchanged (still single `sudo nixos-rebuild` call) | PASS |
| OWASP A03 (injection) — quoted expansions verified | PASS |

---

## 7. Score Table

| Category | Score | Grade |
|----------|------:|:-----:|
| Specification Compliance | 100% | A |
| Best Practices           |  98% | A |
| Functionality            | 100% | A |
| Code Quality             |  98% | A |
| Security                 | 100% | A |
| Performance              | 100% | A |
| Consistency              | 100% | A |
| Build Success            |  85% | B |

**Overall Grade: A (98%)**

Build Success scored 85% solely because `nix flake check` and `nixos-rebuild dry-build` cannot complete in *this* review environment due to pre-existing host-specific evaluation issues unrelated to the Phase 2 change. Both `bash -n` and logical analysis pass cleanly, and the same failure occurs on an unmodified role (`vexos-desktop-amd`), confirming non-regression.

---

## 8. Verdict

**PASS** — no CRITICAL findings. Phase 2 implemented the spec faithfully and minimally. No `.nix` files touched, no `lib.mkIf` guards added, no other role's behavior altered, and the script remains syntactically valid with all safety flags intact. The two environment-bound build observations (missing `shellcheck`, host-specific bootloader assertion under `--impure`) are documented and explicitly not regressions.

---

## 9. Summary for Orchestrator

* **Findings:** All 12 spec-compliance checks PASS. All 6 edge cases PASS. Module architecture rule (zero `.nix`, zero `lib.mkIf`) PASS. `bash -n` PASS. Repo invariants (`hardware-configuration.nix` untracked, `system.stateVersion` present) PASS. One minor non-blocking note: a phrasing micro-deviation in the post-success message (semantically equivalent, more concise — well within spec §4 latitude).
* **Build dry-build for `vexos-headless-server-amd`:** evaluation halts on the pre-existing assertion `boot.loader.grub.devices' or 'boot.loader.grub.mirroredBoots'`. The identical failure occurs for `vexos-desktop-amd`, proving this is host-environment state, not a Phase 2 regression.
* **Verdict:** **PASS**
* **Review file:** [.github/docs/subagent_docs/headless_install_blackscreen_review.md](.github/docs/subagent_docs/headless_install_blackscreen_review.md)

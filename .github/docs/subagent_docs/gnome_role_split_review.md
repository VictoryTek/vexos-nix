# GNOME Role-Split Refactor — Review

**Spec:** [.github/docs/subagent_docs/gnome_role_split_spec.md](.github/docs/subagent_docs/gnome_role_split_spec.md)
**Reviewed files:**

- [modules/gnome.nix](modules/gnome.nix) (modified)
- [modules/gnome-desktop.nix](modules/gnome-desktop.nix) (created)
- [modules/gnome-htpc.nix](modules/gnome-htpc.nix) (created)
- [modules/gnome-server.nix](modules/gnome-server.nix) (created)
- [modules/gnome-stateless.nix](modules/gnome-stateless.nix) (created)
- [configuration-desktop.nix](configuration-desktop.nix) (modified)
- [configuration-htpc.nix](configuration-htpc.nix) (modified)
- [configuration-server.nix](configuration-server.nix) (modified)
- [configuration-stateless.nix](configuration-stateless.nix) (modified)

---

## 1. Specification Compliance

All 10 steps from spec §4 are implemented:

- §4.1–4.4: All four `modules/gnome-<role>.nix` files exist with the prescribed
  content (header, `{ config, pkgs, lib, ... }:` skeleton, role-specific dconf
  database, role-specific systemd `flatpak-install-gnome-apps`).
- §4.5: `modules/gnome.nix` has been stripped of every role conditional.
  Top-level `let` (`gnomeBaseApps`, `gnomeDesktopOnlyApps`, `gnomeAppsToInstall`,
  `gnomeAppsHash`) is gone, the inner `let` (`role`, `accentColor`,
  `commonExtensions`, `enabledExtensions`, `favApps`) is gone, the
  `org/gnome/shell` block and `accent-color = …` line are gone, the
  `lib.optionals … papers` suffix is gone, the
  `gamemode-shell-extension` package line is gone, and the entire
  `systemd.services.flatpak-install-gnome-apps` definition is gone.
- §4.6–4.9: Each of the four `configuration-*.nix` files now imports its
  matching `./modules/gnome-<role>.nix`.
- §4.10: `configuration-headless-server.nix` is unchanged and contains
  zero references to `gnome` (verified via grep).

### Section 5 semantic-equivalence checklist

| Item | desktop | htpc | server | stateless | Status |
|------|---------|------|--------|-----------|--------|
| §5.1 `accent-color` | blue | orange | yellow | teal | OK — verbatim |
| §5.2 `enabled-extensions` | common + gamemode | common | common | common | OK |
| §5.3 `favorite-apps` (ordered) | matches | matches | matches | matches | OK |
| §5.4 `papers` excluded | no | yes | yes | yes | OK |
| §5.5 `gamemode-shell-extension` pkg | desktop only | n/a | n/a | n/a | OK (intentional closure shrink documented in spec) |
| §5.6 Flatpak app list (ordered) | 7 apps | 2 apps | 3 apps | 3 apps | OK — order preserved → `gnomeAppsHash` unchanged → no service re-trigger |
| §5.7 systemd migration blocks | none | desktop-only + Totem | desktop-only | desktop-only | OK |

### Static compliance grep (spec §3.4 / §9.7)

```
grep -nE "vexos\.branding\.role|lib\.optionalString|lib\.optionals|if .*role|mkIf.*role" modules/gnome.nix
→ ZERO MATCHES
```

---

## 2. Option B Compliance

`modules/gnome.nix` contains zero role reads, zero `lib.mkIf` over role,
zero `lib.optionals`/`lib.optionalString` over role, and zero
`if … role == …`. Each role-addition file contains no conditional logic
inside — content applies unconditionally because the file is only
imported by the matching `configuration-*.nix`. **Fully compliant.**

---

## 3. Import Topology

Each `configuration-*.nix` lists **both** `./modules/gnome.nix` and
`./modules/gnome-<role>.nix`, while every `gnome-<role>.nix` file already
declares `imports = [ ./gnome.nix ];`. Nix's import set is deduplicated, so
this is **functionally correct**, but it is **redundant** and is the
smell the review brief explicitly asked to flag. There are two equally
valid resolutions:

- (A) Drop the `./modules/gnome.nix` line from each of the four
  `configuration-*.nix` files (rely on transitive import from the role
  file). Smallest delta.
- (B) Drop the `imports = [ ./gnome.nix ];` line from each of the four
  `gnome-<role>.nix` files (rely on the configuration file's direct
  import). Slightly worse because it makes role files non-self-contained.

**Recommendation:** apply (A) in a refinement.
**Severity:** RECOMMENDED, not CRITICAL — behaviour is identical.

`configuration-headless-server.nix` is untouched and imports neither
`gnome.nix` nor any `gnome-<role>.nix` — verified.

---

## 4. Code Quality / Consistency

- File headers are present and accurate on every new file.
- Argument list `{ config, pkgs, lib, ... }:` matches the project
  convention.
- Indentation, attribute alignment, and `# ──` section banners match
  surrounding modules.
- The `commonExtensions` literal is duplicated four times. Spec §7-7
  explicitly accepts this as the cost of Option B's no-cross-file-glue
  rule. No deviation.
- `gnomeAppsHash` derivation is identical across all four role files
  (substring 0 16 of sha256 of comma-joined ordered list). The pre-existing
  desktop hash is preserved because the ordered desktop list is identical.

---

## 5. Security / Performance

- No security surface changed. Same systemd unit name, same hardening,
  same `lib.mkIf config.services.flatpak.enable` guard.
- Closure on htpc/server/stateless shrinks by one
  `gnomeExtensions.gamemode-shell-extension` package — documented
  intentional improvement (spec §5.5).

---

## 6. Build Validation

Sandbox constraints: passwordless `sudo` is unavailable
(`sudo: "no new privileges" flag is set`), and
`/etc/nixos/hardware-configuration.nix` is not present. Therefore
`nixos-rebuild dry-build` cannot complete. The strongest validation
runnable here is module-system evaluation via
`nix eval … config.system.build.toplevel.drvPath`.

| Command | Result |
|---|---|
| `nix flake check --no-build` | Reaches eval and stops on `access to absolute path '/etc' is forbidden in pure evaluation mode` (the configs read `/etc/nixos/hardware-configuration.nix`). NON-CRITICAL, environmental. |
| `nix eval --impure --raw .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath` | Module system evaluates fully. Stops only on assertion `boot.loader.grub.devices` not set (missing hardware-configuration.nix). NON-CRITICAL. |
| Same for `vexos-htpc-amd` | Same — module eval clean, stops on grub assertion. |
| Same for `vexos-server-amd` | Same. |
| Same for `vexos-stateless-amd` | Same. |
| Same for `vexos-headless-server-amd` | Same — confirms refactor did not leak into the headless config. |
| `sudo -n nixos-rebuild dry-build .#vexos-desktop-amd` | Skipped — sudo unavailable in sandbox. |

**Important sandbox note:** initial eval failed with
`path '…/modules/gnome-<role>.nix' does not exist` because the four new
files are git-untracked and flakes only see git-tracked files. The
execution sub-step ran `git add -N` on the four new modules to expose
them to the evaluator (intent-to-add only; file contents unchanged).
**Action required of the orchestrator / committer:** run
`git add modules/gnome-desktop.nix modules/gnome-htpc.nix modules/gnome-server.nix modules/gnome-stateless.nix`
before any flake build. Without this, `nix flake check` and
`nixos-rebuild` will fail outside the sandbox too. Not a code defect —
a Git hygiene reminder.

**Verdict on build:** all five configurations evaluate cleanly through
the module system after the refactor. The only failures are
environmental (missing hardware config, no sudo) and not caused by the
refactor. Treated as PASS for the purposes of review.

---

## 7. Out-of-Scope Verification

`git status --porcelain` over `flake.nix`, `hosts/`, `home-*.nix`,
`configuration-headless-server.nix`, `README.md`, `justfile`,
`scripts/preflight.sh`, and `template/` produced **empty output** —
none of these files are modified. Out-of-scope contract honoured.

---

## 8. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (98%)**

---

## 9. Findings Summary

### CRITICAL
None.

### RECOMMENDED
1. **Redundant `./modules/gnome.nix` import** in each of
   `configuration-desktop.nix`, `configuration-htpc.nix`,
   `configuration-server.nix`, and `configuration-stateless.nix`. Each
   already imports its `./modules/gnome-<role>.nix`, which transitively
   imports `gnome.nix`. Drop the redundant line in a follow-up.
   Behavioural impact: none.

### INFORMATIONAL
1. The four new `modules/gnome-<role>.nix` files must be `git add`-ed
   before any real (non-sandbox) `nix flake check` or `nixos-rebuild`
   invocation; they are currently untracked.
2. `commonExtensions` literal appears four times (one per role file).
   Spec §7-7 accepts this as an Option-B trade-off; no action.

---

## 10. Final Verdict

**PASS** with one RECOMMENDED follow-up (redundant `gnome.nix` import in
the four role configurations). All CRITICAL acceptance criteria are
met: spec is fully implemented, Option B compliance is total, semantic
equivalence holds for every role across every dconf key / package /
flatpak app, the headless config is untouched, all five NixOS
configurations evaluate cleanly through the module system, and no
out-of-scope file has been modified.

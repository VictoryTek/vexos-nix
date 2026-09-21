# Installer Audit — Findings & Remediation Tracker

**Scope:** `scripts/install.sh` (940), `scripts/stateless-setup.sh` (594),
`scripts/migrate-to-stateless.sh` (633), `scripts/lib/progress.sh` (260),
`template/etc-nixos-flake.nix`, `template/stateless-disko.nix`.

**Method:** static reading of the scripts plus targeted verification of option
scope, import chains and preflight coverage in the repo. **No finding below was
observed on a running machine** — the installer cannot be executed from the dev
environment. Each item records how it was established so it can be confirmed on
real hardware before or during the fix.

**How to use:** work items top to bottom. Each is independently shippable and
carries its own verification step. Items 1-2 are safe in any order; item 3 is a
prerequisite for most of the cleanup below it.

| # | Item | Severity | Size | Status |
|---|------|----------|------|--------|
| 1 | `features.nix` never reset on re-run | Bug | S | ☑ |
| 2 | No shellcheck coverage of `scripts/*.sh` | Gap | S | ☑ |
| 3 | Text-patching `flake.nix` instead of side-file imports | Fragility | M | ☑ |
| 4 | Prompt/bootstrap logic triplicated across 3 scripts | Duplication | M | ☑ |
| 5 | `VEXOS_REV` pin does not cover the config; `disko` unpinned | Correctness | S | ☑ |
| 6 | ASUS patch fails open | Bug | S | ☑ (dissolved by 3) |
| 7 | Fake progress bar hides real build state | UX | M | ☑ |
| 8 | No unattended / non-interactive mode | Gap | M | ☑ (CI VM job not done) |
| 9 | Divergent install-swap policies | Inconsistency | S | ☐ |
| 10 | No resume after a failed `nixos-install` | UX | M | ☐ |
| 11 | Stale comments + dead code | Hygiene | S | ☐ |
| 12 | **Overhaul:** no live-ISO path for 5 of 6 roles | Architecture | L | ☐ |

---

## 1. `features.nix` is write-only and never reset

**Severity:** Bug — silent misconfiguration, no error shown to the user.

### Evidence
- `features_set()` (`scripts/install.sh:731-752`) only writes or replaces a key.
  Nothing ever removes one.
- The desktop-environment write is guarded by `[ "$DESKTOP_ENV" != "gnome" ]`
  (`scripts/install.sh:757`), so selecting GNOME writes nothing and leaves any
  previous value in place.
- `features.nix` is imported for the **desktop, htpc and server** roles
  (`template/etc-nixos-flake.nix:205, 261, 345`).
- Verified option scope: `modules/desktop-environment.nix` is the only declarer of
  `vexos.desktop.environment`, but `modules/gnome.nix` imports it and is itself
  imported by `configuration-htpc.nix` and `configuration-server.nix`. So a stale
  value **evaluates cleanly** rather than erroring — which is what makes it silent.

### Reproduction (to confirm on hardware)
1. Install `desktop` + Hyprland. → `features.nix` contains `vexos.desktop.environment = "hyprland"`.
2. Re-run the installer, choose `desktop` + GNOME. → still Hyprland.
3. Re-run the installer, choose `server`. → `features.nix` still says `hyprland`;
   `isGnome` is false, and the Hyprland modules are desktop-only. Expected result
   is a GUI server that boots with **no desktop environment at all**.

This path is explicitly advertised: `scripts/lib/progress.sh:122` tells the user
"Re-run this installer any time to switch role or GPU variant."

### Proposed fix
Make each run fully express the chosen role rather than layering onto the last:
- Add `features_unset <key>` (mirror of `features_set`), and call it for every key
  the current selection does *not* set — notably `vexos.desktop.environment` when
  the role is not `desktop`, or when the role is `desktop` and the DE is `gnome`.
- Alternative, simpler and preferred if acceptable: regenerate `features.nix` from
  scratch each run from the full set of answers, so the file is a pure function of
  the current selection. Any keys set by `just enable-feature` outside the
  installer would need to be preserved or explicitly re-prompted — decide which
  before implementing.

### Resolution
Implemented as targeted `features_unset` (the first option), **not** regeneration:
`features.nix` also holds `just enable-feature` toggles (gaming, development,
kernel …) that a rewrite would wipe. Also covers `vexos.vm.platform`, which had
the identical bug (VirtualBox → QEMU re-run left `virtualbox` behind) and was not
in the original audit. Verified against the real function bodies with a temp
file: stale keys removed, unrelated toggles preserved, absent file is a no-op.
Not yet confirmed on hardware.

### Verification
Run the three-step reproduction above; after step 2 `features.nix` must contain no
`vexos.desktop.environment` key, and after step 3 it must contain no desktop keys.

---

## 2. No shellcheck coverage of `scripts/*.sh`

**Severity:** Gap — 2,200 lines of root-running, disk-formatting code with no lint gate.

### Evidence
`scripts/preflight.sh` has nine stages `[0/8]`-`[8/8]`; none lint the installer
scripts. Verified by grepping `preflight.sh` for `scripts/` — the only hits are its
own usage comments. The sole shellcheck run in the repo is incidental, via
`writeShellApplication` when building `pkgs.vexos.vexos-update` (`preflight.sh:451`).

### Proposed fix
Add a preflight stage running `shellcheck` over `scripts/*.sh` and
`scripts/lib/*.sh`. Notes:
- `shellcheck` is not guaranteed present; follow the existing preflight idiom of
  WARN-and-skip when a tool is missing (as stages 5b/6/7e already do), or fetch it
  via `nix run nixpkgs#shellcheck`.
- Baseline is already clean: `shellcheck -S warning scripts/install.sh` exits 0 as
  of this audit. Confirm the other scripts before wiring it as a hard gate; start
  at `-S warning` and tighten later if clean.
- Renumber the stage banners (`[0/8]`…) when adding one.

### Resolution
Added as stage `[9/9]` (appended rather than inserted, so existing stage numbers
are unchanged; only the `/8` denominators became `/9`). Hard-fails on findings at
`-S warning`; WARN-and-skip only when neither a local `shellcheck` nor
`nix shell nixpkgs#shellcheck` is available. Baseline was clean for all 9 scripts,
and a deliberate `for f in $(ls)` file made the stage fail with exit 1.

### Verification
`bash scripts/preflight.sh` exits 0 with the new stage reporting PASS; introduce a
deliberate `$foo` typo in a script and confirm the stage fails.

---

## 3. Text-patching `flake.nix` instead of optional side-file imports

**Severity:** Fragility — the most dangerous code in the repo.

### Evidence
Three host settings are applied by rewriting `/etc/nixos/flake.nix` in place:

| Setting | Mechanism | Location |
|---|---|---|
| GRUB (legacy BIOS) | `awk` brace-depth block replace, anchored to `/^    bootloaderModule = \{ \.\.\. \}: \{/` | `install.sh:563-583` |
| Limine (opt-in UEFI) | same `awk` pattern, second copy | `install.sh:653-672` |
| ASUS ROG/TUF | `sed` on the exact literal `hardwareModule = { ... }: { };` | `install.sh:691-695`, duplicated at `stateless-setup.sh:439-443` |
| ZFS `hostId` | `sed` on `networking.hostId = "XXXXXXXX"` | `install.sh:719-723` |

Every one is keyed to exact whitespace and literal text in the template. A
reformat of `template/etc-nixos-flake.nix` breaks them.

Meanwhile the template already uses a robust idiom for the *same job* in six
places — `builtins.pathExists` + `lib.optional`:
`featuresFile`, `vmPlatformFile`, `storagePoolFile`, `storageRemoteFile`,
`zfsPoolsFile`, `kernelOverrideFile` (`template/etc-nixos-flake.nix:141-174`).

### Proposed fix
Move the three holdouts onto the established pattern. The installer then only ever
*writes small Nix files* and never rewrites the template:
- `bootloader.nix` → `vexos.bootloader` / `vexos.grub.device`
- `hardware-local.nix` → ASUS options or the OpenRGB block
- `host.nix` → `networking.hostId`

Consequences to handle:
- The `XXXXXXXX` placeholder and the `hostModule` block can be dropped from the
  template entirely, as can `hardwareModule` and the default `bootloaderModule`
  (or keep `bootloaderModule` as the systemd-boot default and let `bootloader.nix`
  override it — decide which, since two modules setting `boot.loader.*` at equal
  priority will conflict; the existing code already routes through `vexos.*`
  options for exactly this reason, see `install.sh:561-562`).
- **Vanilla role carve-out:** `configuration-vanilla.nix` sets
  `boot.loader.systemd-boot.enable` directly and never imports `modules/system.nix`,
  so `vexos.bootloader` is not a declared option there. `install.sh:631` already
  skips the Limine prompt for vanilla; preserve that.
- The new files must be `git add`-ed before evaluation, same as the existing ones
  (`install.sh:820-824`).
- Deletes roughly 120 lines, including both copies of the `awk` block-replacer.

### Resolution
Spec: `wrapper_sidefiles_spec.md`. Implemented as four optional side-files —
`bootloader.nix`, `hardware-local.nix`, `host.nix` and a new `hostname.nix` —
imported by all six builders via one shared `localFiles` list (`host.nix` only by
the two server builders). The wrapper's default `bootloaderModule` was dropped
outright: `modules/system.nix` already defaults to systemd-boot, and the inline
copy was what caused the equal-priority conflict. `install.sh`,
`stateless-setup.sh`, `just switch-bootloader` and `just set-hostname` now write
whole files; no awk/sed rewrite of `flake.nix` remains.

Findings beyond the audit:
- **Existing machines keep the old wrapper** (never resynced), so a side-file
  installer alone would be silently ignored on them. Added
  `scripts/upgrade-wrapper.sh` (called from `ensure_flake_wrapper` and both
  justfile recipes): fail-closed, backs up to `flake.nix.legacy.bak`, carries over
  bootloader / hostId / hardwareModule contents. Tested against fixtures built
  from the real old template (empty, GRUB, Limine, ASUS laptop/desktop, real
  hostId, garbage → abort, GRUB-without-device → abort, current wrapper → no-op).
- **Vanilla + BIOS/GRUB was broken** (wrote `vexos.bootloader`, undeclared on
  vanilla). Confirmed by evaluation: "The option `vexos.bootloader' does not
  exist". Vanilla now gets direct `boot.loader.grub` options.
- `just switch-bootloader`'s "Already configured" grep matched the commented
  example in the old wrapper header; now anchored.
- `stateless-setup.sh` / `migrate-to-stateless.sh` persist the new side-files;
  `vexos-update` and the installer force-add them to git.

Verified by per-role `nix eval` of the new template against the local checkout,
using the heredoc text extracted from `install.sh` itself: no side-files
(desktop/htpc/vanilla), GRUB and Limine (`grub.enable`/`systemd-boot.enable`
resolve correctly), ASUS laptop (`asus.enable`, `batteryChargeLimit = 80`) and
desktop, `host.nix` on server + headless-server, `hostname.nix`, stateless.
Not verified on hardware. Deliberate parity: installer only *writes*
`bootloader.nix`/`hardware-local.nix` (never deletes), so a re-run answering "N"
to Limine cannot flip an installed Limine host back to systemd-boot.

Observation, not changed: a server role with no real hostId fails evaluation with
"`networking.hostId` is defined both null and not null" before the friendlier
assertion in `zfs-server.nix` is reached. Same for any config lacking a
normal-priority hostId (CI stubs one for this reason); worth a look if someone
hand-installs the template on a server without the installer.

### Verification
Per-target `sudo nixos-rebuild dry-build` for an affected variant with each file
present and absent; confirm `vexos.bootloader` resolves as expected. Reformat the
template (whitespace only) and confirm the installer still applies every setting.

---

## 4. Prompt and bootstrap logic triplicated across three scripts

**Severity:** Duplication — already drifted, with a comment admitting the problem.

### Evidence
Duplicated blocks, with `install.sh` holding the most advanced copy:

| Block | install.sh | stateless-setup.sh | migrate-to-stateless.sh |
|---|---|---|---|
| `VEXOS_REV` resolution | 35-46 | 46-54 | 57-65 |
| Colour helpers | 50-63 | 62-71 | 42-51 |
| progress-lib loader | 75-99 | 82-103 | 75-96 |
| GPU variant prompt | 286-318 | 146-168 | 345-367 |
| NVIDIA branch prompt | 351-385 | 170-190 | 369-389 |
| VM hypervisor prompt | 320-349 | 192-214 | 391-413 |
| ASUS prompt | 387-420 | 216-241 | — |
| Password prompt | — | 243-283 | 415-464 |

All three loader blocks carry the comment *"Keep this loader block in sync across
the three installer scripts"* — the codebase acknowledging the maintenance cost.

**Already drifted:** `install.sh` has the `gum` arrow-key UI (`ui_choose`,
`ui_confirm`, `ui_input`, `install.sh:101-149`); the other two still use numbered
`read` prompts only.

### Proposed fix
`scripts/lib/` already exists as the precedent. Add:
- `scripts/lib/bootstrap.sh` — `VEXOS_REV` resolution, colour helpers, and the
  progress-lib loader. The loader that fetches the lib cannot itself be fetched by
  the lib, so a minimal chicken-and-egg stub stays inline; keep it to a few lines.
- `scripts/lib/prompts.sh` — the `ui_*` helpers plus one function per question
  (`ask_gpu_variant`, `ask_nvidia_branch`, `ask_vm_platform`, `ask_asus`,
  `ask_password`).

Both stateless scripts then inherit the `gum` UI for free. Preserve the existing
best-effort fallback contract: every helper must degrade to a plain `read` prompt
when `gum` is unavailable.

### Resolution
Spec: `installer_shared_libs_spec.md`. Added `scripts/lib/bootstrap.sh` (colours,
loads `progress.sh` with its plain fallbacks, loads `prompts.sh`) and
`scripts/lib/prompts.sh` (`ui_*`, `init_gum`, a generic `ask_choice`, `ask_yes_no`,
`ask_gpu_variant`, `ask_nvidia_branch`, `ask_vm_platform`, `ask_asus`,
`ask_password`). `ask_choice` replaced the six hand-written numbered-menu loops
in `install.sh` (including role / server type / desktop env, which the audit did
not list) and the stateless copies. Each script keeps only `VEXOS_REV`
resolution and a ~15-line `_load_lib` stub — the unavoidable chicken-and-egg.
The stateless scripts now get the gum arrow-key UI; total across the three
scripts + libs went 2427 → 2299 lines.

Design points worth knowing:
- `ask_*` set globals instead of echoing (a fallback menu inside `$( )` would be
  swallowed) — this is also the shape item 8 (`--gpu` etc. flags) needs.
- `VEXOS_PROMPT_STYLE=full` (set only by `install.sh`) keeps its centred menus and
  header redraw; the stateless scripts stay plain, so nothing was restyled.
- Behaviour changes: a lib that cannot be loaded now aborts with a clear message
  (only the cosmetic `progress.sh` still degrades to plain output); prompt wording
  is generated ("Enter choice [1-N] or name (…)"); NVIDIA hints print above the
  menu everywhere; password prompt reads "Password (hidden):" in both scripts.
- Also resolves the first item-11 bullet (stale "only VirtualBox writes
  features.nix" comments): those blocks are gone, replaced by one accurate
  comment on `ask_vm_platform`.
- Found and fixed while testing: the old `center_block() { cat; }` fallback in
  `install.sh` ignored its argument (`center_block` takes text as `$1`, not stdin).

Verified by driving the real libs under a pty with scripted input (28 cases:
number / name / alias / case / default / empty / invalid-then-valid for every
`ask_*`, both styles, mismatched-then-matching password) plus a stub `gum` for
the value mapping, and by running each script's real loader stub against a fake
`curl` in ok / prompts-missing / fetch-fails modes. Not run on a live ISO or
against the real `gum` binary.

### Verification
`bash -n` + `shellcheck` on all four files; run each script to the first prompt
with and without `gum` on `PATH` and confirm both paths render.

---

## 5. `VEXOS_REV` pin does not cover the config; `disko` unpinned

**Severity:** Correctness — defeats the stated purpose of the pinning mechanism.

### Evidence
- `install.sh:29-46` resolves one commit for the run, with a comment explaining it
  exists so the script chain cannot "silently mix code from two different commits
  if main is updated mid-run."
- But `template/etc-nixos-flake.nix:100` declares `vexos-nix.url =
  "github:VictoryTek/vexos-nix"` with **no ref**, and `install.sh:834` runs
  `nix flake update --flake git+file:///etc/nixos`, which re-resolves `main` at that
  moment. The scripts are pinned; the system config being built is not.
- `stateless-setup.sh:325` runs `github:nix-community/disko/latest` — resolved at
  runtime, not a flake input, not in `flake.lock`. Verified: `disko` appears
  nowhere in `flake.nix`'s inputs.

### Proposed fix
- Pass `--override-input vexos-nix github:VictoryTek/vexos-nix/${VEXOS_REV}` to the
  `flake update` (and/or the `nixos-rebuild`) so the built config matches the
  scripts' commit. Confirm the override survives into the written `flake.lock`.
- Add `disko` as a proper flake input with `inputs.nixpkgs.follows = "nixpkgs"`,
  per the CLAUDE.md flake-input rule, and have `stateless-setup.sh` use the pinned
  revision instead of `latest`.

### Resolution
- **Config pin:** `install.sh` and `stateless-setup.sh` now run
  `flake update … --override-input vexos-nix github:VictoryTek/vexos-nix/${VEXOS_REV}`.
  Tested empirically (Nix 2.34.1) against a wrapper flake pinned to an older pushed
  commit: the written lock has `locked.rev` = the pin while `original` stays the
  unpinned URL, so plain commands accept the lock as current (no re-resolve to
  main), and a later plain `flake update` — what `vexos-update` does — moves to
  main as normal. So the pin costs nothing after install.
- **Beyond the audit:** `migrate-to-stateless.sh` never ran a `flake update` at all,
  so it built whatever lock `/etc/nixos` already had (possibly one predating the
  stateless role, or a fresh unpinned one). Its `nixos-rebuild boot` now carries the
  same `--override-input`, applied in memory only (verified: pins in memory, leaves
  the on-disk lock alone).
- **disko:** added as a flake input (`github:nix-community/disko/latest`,
  `inputs.nixpkgs.follows = "nixpkgs"`, verified against current disko docs via
  Context7). `nix flake lock` added exactly that node (22 insertions, nothing else
  moved; locked at `de57087`, 2026-01-20). `stateless-setup.sh` now runs
  `nix run --inputs-from github:VictoryTek/vexos-nix/${VEXOS_REV} disko -- …`,
  confirmed to resolve to the locked rev rather than `latest`. No disko module is
  imported; it stays a CLI-only input, so it adds no eval cost to any host.
- Verified: preflight exit 0; `nix eval` of `vexos-desktop-amd` and `vexos-htpc-vm`
  through the wrapper against the modified checkout.
- **Not verified:** a real `curl | bash` install, or an actual disko run. The disko
  invocation requires the pinned commit to contain the new input, so it only works
  once this change is pushed; running `stateless-setup.sh` from an *unpushed*
  working tree (VEXOS_REV = an older main without the input) will fail at that step.
- disko now follows the daily flake-update job like every other input, so the
  revision used to wipe disks changes when that job bumps it — but never mid-run.

### Verification
After an install, `nix flake metadata /etc/nixos` must report the `vexos-nix`
input locked to the same revision the installer printed as its source URL.

---

## 6. ASUS patch fails open

**Severity:** Bug — silent loss of hardware support.

### Evidence
The GRUB and Limine patches validate their result and `exit 1` on failure
(`install.sh:584-588`, `673-677`). The ASUS patch instead prints a warning and
continues (`install.sh:699-712`), so if the `hardwareModule = { ... }: { };` literal
ever drifts, an ASUS user gets a completed build with no `asusd`, no charge limit
and no OpenRGB — having answered "yes" to the prompt.

### Proposed fix
Make it consistent with the other two: fail hard, or verify the patch applied and
abort if not. Largely dissolved by item 3 — writing `hardware-local.nix` cannot
half-succeed the way a `sed` can.

### Verification
Temporarily alter the anchor literal in a local copy of the template and confirm
the installer aborts rather than proceeding.

---

## 7. Fake progress bar hides real build state

**Severity:** UX — cannot distinguish a slow build from a hung one.

### Evidence
`run_live_build` (`scripts/lib/progress.sh:140-223`) redirects all build output to a
temp log and renders a time-based curve: `pct=$(( 92 * elapsed / (elapsed + 60) ))`
(`progress.sh:207`). The function's own comment concedes this "trades away
transparency." On a from-source NVIDIA or noctalia build — explicitly expected per
`install.sh:424-447` and the "these N derivations will be built" note at
`install.sh:845-857` — the user watches a bar approach 92% for hours with no signal.

### Proposed fix
Keep the branded screen; restore the signal. Cheapest option is to tail the last
one or two lines of `$build_log` beneath the bar each frame. Better: drive
`nixos-rebuild` with `--log-format internal-json` and parse real built/total
counts into the percentage. Note the frame loop already clears exactly the five
lines it rewrites (`progress.sh:186-194`) and truncates to terminal width to avoid
wrap artefacts — any added line must follow the same discipline.

### Resolution
Took the cheap option, in `scripts/lib/progress.sh` (shared, so all three
installers get it): each frame now also draws a status line — an elapsed clock
plus the last line of the build log, e.g. `[12:34] building 'linux-7.2.drv'...` —
with `/nix/store/<hash>-` prefixes, ANSI escapes and CRs stripped for display
only (the log file itself is untouched, so the callers' `tail -n 60` on failure
still shows full paths). Frames are 6 rows instead of 5 and keep the
clear-only-what-you-rewrite discipline; the line is cut to `cols-2` with an
ellipsis so it never wraps.

Deliberately **not** done: `--log-format internal-json`. `run_live_build` wraps
three different commands (`nixos-rebuild`, `nixos-rebuild boot`, `nixos-install`)
and every caller's failure path prints the raw log for a human; internal-json
would make that unreadable and need a parser per call site. The status line
answers the actual question (slow or hung?) from plain Nix output.

The bar itself is still the time-based curve — it now only signals "alive"; the
status line is the real information. If a true percentage is wanted later, the
"these N derivations will be built" / "N paths will be fetched" lines in the log
are the plain-text source for it (units differ, so it needs a design decision).

Verified under a pty with a fake nix-style build: 80 and 40 columns (truncation
at 78/38), ANSI/CR/store-hash stripping, exactly 6 rows cleared per frame, and a
failing build (exit code preserved, animation dropped, log intact). Not verified
against a real multi-hour build or a real-terminal resize.

### Verification
Run a build with at least one from-source derivation and confirm the displayed
state advances in step with the log.

---

## 8. No unattended / non-interactive mode

**Severity:** Gap — blocks automated testing of everything above.

### Evidence
Every prompt reads `</dev/tty` (required for `curl | bash`, and correct as such),
but there is no flag or environment override for any answer. The installer cannot
be smoke-tested in a VM in CI, nor scripted for a repeatable rebuild.

### Proposed fix
Accept `--role`, `--gpu`, `--nvidia-branch`, `--vm-platform`, `--desktop`,
`--asus`, `--yes` (and/or `VEXOS_*` environment equivalents), defaulting to the
interactive prompt when absent. Pairs naturally with item 4: each `ask_*` function
returns its flag value when set and prompts otherwise. Then add a CI job that runs
a full install in a VM.

### Resolution
One mechanism: every question reads a `VEXOS_ANSWER_<NAME>` variable; the flags are
sugar that set and export them (so the `curl | bash` hand-offs inherit them, and
`install.sh` forwards them through `sudo` to `migrate-to-stateless.sh`).
`VEXOS_YES=1` / `--yes` means "never prompt": an unanswered question takes a safe
default (no ASUS, no Limine, no reboot, GNOME) or aborts naming the missing flag
when it has none (role, GPU, NVIDIA branch, VM platform, disk, password). Logic
lives in `scripts/lib/prompts.sh` (`parse_answer_flags`, `preset_block_device`,
`preset_yes_no`, presets inside `ask_choice`/`ask_asus`/`ask_password`), so all three
scripts share it — item 4's `ask_*`-sets-a-global design is what made this small.

Flags: `--role` (incl. `headless-server`), `--desktop`, `--gpu`, `--nvidia-branch`,
`--vm-platform`, `--asus`, `--grub-device`, `--efi-device`, `--limine`, `--disk`,
`--password-hash`, `--reboot`/`--no-reboot`, `--yes`; `--flag=value` accepted;
`--help` lists them. Beyond the audit's list, because they also block a no-TTY run:
the GRUB/EFI device prompts, the Limine question, the destructive "proceed"
confirmations and the reboot prompts. A typo in a preset aborts (never falls
through to a prompt). Presets accept the same values/aliases as the interactive
prompt, case-insensitively.

Decisions to be aware of:
- **Password:** hash only (`--password-hash`, e.g. from `openssl passwd -6`); a
  plaintext password on a command line would land in `ps` and shell history.
- **`--yes` confirms the disk-erasing prompt**, but `--disk` must be passed
  explicitly — an unattended stateless install aborts rather than guessing a disk.
- `run_live_build` now streams plain output (no cursor animation) when stdout is not
  a terminal, keeping the same log / exit-code contract, so CI logs stay readable.
- `init_gum` is skipped under `--yes`; README has a short "Unattended install"
  section.

Verified with no controlling terminal (`setsid`, stdin `/dev/null`, so any stray
`/dev/tty` read would fail): 39 cases across flag parsing, every preset, `--yes`
defaults and aborts, block-device validation, and `run_live_build` non-tty
(no escape codes, exit codes kept); the real `install.sh` for `--help` (rc 0),
`--bogus` (rc 2), `--yes` alone (aborts naming `--role`) and an invalid `--gpu`;
plus a 9-case interactive pty regression (both styles). Preflight exit 0.

**Not done:** the audit's "add a CI job that runs a full install in a VM".
Everything needed to drive one now exists, but the job itself (a NixOS VM in
GitHub Actions running `install.sh --yes …`) is a separate piece of work. **Not
verified:** an end-to-end unattended install on a real machine, and the
`sudo`-forwarded env reaching `migrate-to-stateless.sh` (depends on sudoers policy).

### Verification
A fully-flagged invocation completes with no TTY attached.

---

## 9. Divergent install-swap policies

**Severity:** Inconsistency.

### Evidence
Two different answers to the same OOM problem:
- `install.sh:466-515` — conditional: skips when RAM+swap ≥ 8 GiB, checks for ≥10
  GiB free, refuses on tmpfs/zfs roots, handles btrfs vs ext4 separately, 4 GiB,
  removed by an `EXIT` trap.
- `stateless-setup.sh:347-351` — unconditional 8 GiB on `/mnt/persistent`, no
  capacity or RAM check. Also created on a machine with ample RAM.
- `migrate-to-stateless.sh:516-523` — unconditional 8 GiB on `@persist`.

The stateless variants are deliberately sized to match what
`modules/impermanence.nix` expects for the installed system, so they are not simply
wrong — but the guards differ for no documented reason.

### Proposed fix
Extract one `ensure_install_swap()` into `scripts/lib/`, parameterised by size and
target path, carrying `install.sh`'s guards. Document why the stateless path uses
the impermanence-managed location and size.

### Verification
Install on a ≥8 GiB machine and confirm no temporary swapfile is created where the
guards say it should be skipped.

---

## 10. No resume after a failed install

**Severity:** UX.

### Evidence
`stateless-setup.sh:323-330` always runs disko with `--mode destroy,format,mount`
and `--yes-wipe-all-disks`. A `nixos-install` failure late in the build
(`stateless-setup.sh:533`) means a re-run re-partitions from scratch and rebuilds
everything.

### Proposed fix
Detect an already-provisioned target (`@nix` and `@persist` present with the
expected layout) and offer to skip straight to `nixos-install`.
`migrate-to-stateless.sh:205-220` already does exactly this kind of
existing-subvolume detection — reuse that approach.

### Verification
Interrupt an install during the build, re-run, and confirm the resume path is
offered and completes.

---

## 11. Stale comments and dead code

**Severity:** Hygiene. Flagged, not to be removed except where noted.

- ~~`stateless-setup.sh:192-195` and `migrate-to-stateless.sh:391-394` claim
  "only VirtualBox writes `/etc/nixos/features.nix`"~~ — resolved by item 4.
- `stateless-setup.sh:29-35` — `cleanup()` removes `/tmp/disk-password`, which is
  never created: LUKS is hardwired off at `stateless-setup.sh:288-291`. Pre-existing
  dead code; flagged per CLAUDE.md, do not delete unless explicitly asked.
- ~~`template/etc-nixos-flake.nix:78-86` — the BIOS/GRUB header comment shows a
  `bootloaderModule = {` stanza *without* the `{ ... }:` prefix~~ — resolved by
  item 3 (header rewritten, block removed).
- `install.sh:442-447` — `INSTALL_CACHE_OPTS` duplicates keys from `flake.nix`'s
  `nixConfig`, kept in sync by hand. The comment explains why (standalone
  `curl | bash`, no local checkout). Accepted cost; noted so it is not forgotten
  when cache keys change.

---

## 12. OVERHAUL — no live-ISO install path for five of six roles

**Severity:** Architecture. The largest item; do last, and only if wanted.

### Evidence
The live-ISO detection branch sits **inside** the `if [ "$ROLE" = "stateless" ]`
block (`install.sh:257-284`). Only `stateless` gets a disko-based bare-metal
install. For `desktop`, `htpc`, `server`, `headless-server` and `vanilla` on a live
ISO, the script continues into the normal path: it prompts for and mounts the EFI
partition (`install.sh:594-617`), git-inits `/etc/nixos`, refreshes the flake, and
only then fails on the missing `./hardware-configuration.nix`
(`template/etc-nixos-flake.nix:198`) with an opaque Nix path error — after several
minutes and a mutated system.

`README.md:26` states the assumption ("Assumes NixOS is installed and
`hardware-configuration.nix` already exists"), so this is a known boundary rather
than a regression. But the same README now presents a single install command, and
the installer's own tip text invites re-running it freely.

### Proposed fix
Extend the disko path to every role, so `install.sh` handles bare metal end to end:
- Generalise `template/stateless-disko.nix` into a layout selectable per role
  (impermanence subvolumes for stateless; a conventional single-root layout
  otherwise).
- On live-ISO detection, run disko → `nixos-generate-config --root /mnt` →
  `nixos-install` for **any** role, rather than only stateless.
- `stateless-setup.sh` then collapses into a role argument of the shared path
  instead of a separate 594-line script.

Interim mitigation, worth doing regardless and cheap: move the tmpfs/live-ISO
detection **above** the role branch and fail fast with a clear message for roles
that have no ISO path.

### Verification
Install each role from a live ISO in a VM and boot the result. Requires item 8 to
be practical in CI.

---

## Appendix — checks run during this audit

| Check | Result |
|---|---|
| `bash -n scripts/install.sh` | OK |
| `shellcheck -S warning scripts/install.sh` (0.11.0) | Clean, exit 0 |
| `bash scripts/preflight.sh` (WSL, Nix 2.34.1) | Exit 0, PASSED |
| `grep` for `scripts/` in `preflight.sh` | No lint stage — confirms item 2 |
| `grep -rn "options.vexos.desktop"` | Single declarer; `gnome.nix` imports it — confirms item 1 evaluates silently |
| `grep -n disko flake.nix` | No input — confirms item 5 |
| `grep -n "hasFeatures\|featuresFile" template/etc-nixos-flake.nix` | Imported for desktop, htpc, server — confirms item 1 blast radius |

Not verified: any runtime behaviour. Every reproduction step above should be
confirmed on real hardware or in a VM before the corresponding fix is called done.

# Justfile Deep Dive — Review & Improvement Spec

Phase 1 (Research & Specification). Nothing in this document has been implemented.
Subject: `justfile` (3,970 lines, ~190 KB, 39 public + ~45 private recipes), as of
commit `753c723`. Installed `just`: 1.51.0.

---

## 1. Current state

### How the justfile is deployed and invoked

| Path | Mechanism |
|---|---|
| `/etc/nixos/justfile` | `environment.etc."nixos/justfile".source = ../justfile` (`modules/packages-common.nix:8`) |
| `/etc/nixos/scripts/`, `/etc/nixos/template/{features,server-services}.nix` | also deployed via `environment.etc` |
| `/etc/nixos/pkgs/` | **not** deployed |
| Interactive shell | alias `just = "just --justfile /etc/nixos/justfile --working-directory /etc/nixos"` (`home/bash-common.nix:44`) |
| VexPortal daemon | runs **as root**: `just --justfile /etc/nixos/justfile --working-directory /etc/nixos …`, env cleared, `VEXOS_ASSUME_YES=1`, **stdin = /dev/null** unless a secret is piped |
| VexPortal GUI | reads `just --dump --dump-format json` (recipe names, parameter order, and `doc`) and checks a curated catalog against it (`catalog/src/drift.rs`) |

Consequences that matter throughout this review:

- `{{justfile_directory()}}` is always `/etc/nixos`, never the repo checkout.
- Every recipe's working directory is `/etc/nixos`, **not** where the user typed the command.
- Recipe names, parameter order, and the `doc` string are a **public contract with VexPortal**.
  Any rename, reordering, or move into a `mod` namespace needs a matching VexPortal change.

### Structure

```
default (private)                     ← `just --list` + hand-written server list
System Build & Deploy                 variant switch build rebuild update update-all deploy bootloader
System Upgrades & Rollbacks           upgrade-analysis rollback rollforward
System Administration                 reboot shutdown reset-defaults set-hostname ssh remote-storage
VPN                                   setup-tailscale vpn kill-switch
Optional Feature Toggles              fix-flake feature
AI Assistant                          agent diagnose ai-*  (8)
Binary Cache                          cache
(no group)                            kernel secrets-init backup-now nas-sync-status nas-sync-now
                                      backup-plex restore-plex restore-service
(private but user-facing)             service plex-pass zfs-pool mergerfs-pool prune-services
```

There is a good shared menu engine, `_menu` (lines 1834–1919). It dispatches
`just <group> <action>` to a hidden `_<group>-<action>` recipe, prompts for a
missing argument, keeps read-only actions in the menu with the `stay` flag, and
prints usage when it has no TTY. Seven grouped commands use it.

---

## 2. Findings: correctness bugs (verified)

Each finding below was checked against the code, a live command, or the module source.

### B1 — `just switch` exits 0 when `nixos-rebuild switch` fails  ·  CRITICAL
`justfile:402-415`
```bash
if ! sudo nixos-rebuild switch ...; then
    _rc=$?          # ← always 0: $? is the status of `! cmd`
    if [ $_rc -eq 4 ]; then ... else exit $_rc; fi
```
Verified with `bash -c 'if ! false; then echo $?; fi'`, which prints `0`. A failed
switch prints nothing helpful and **exits successfully**. VexPortal therefore
reports success. The "exit code 4 is OK" branch can never run. `rebuild`
(line 708) uses the correct `cmd || { _rc=$?; … }` form and can serve as the fix pattern.

### B2 — `just update`'s role/GPU picker is dead code  ·  HIGH
`justfile:726-835`. When `/etc/nixos/vexos-variant` is missing, the recipe asks
for role, GPU, and NVIDIA branch, builds `target=…`, prints "Updating to: …", and then
runs `sudo vexos-update` **without passing the target**. `vexos-update` reads
`vexos-variant` itself and fails if it is missing (`pkgs/vexos-update/default.nix:30-32`).
The user answers three prompts and then gets an error. The picker also has no `vanilla`
option (`switch` has 5 roles, `update` has 4).

### B3 — Server unit-name table is wrong for some services  ·  HIGH
`_service-units` (line 2532) drives both `service status` and `service restart`:

| service | justfile unit | actual |
|---|---|---|
| ntfy | `ntfy` | `ntfy-sh` (module uses `services.ntfy-sh`; the `service enable` text even says `ntfy-sh.service`) |
| mealie | `mealie` | `docker-mealie` / `podman-mealie` (module is an OCI container, `modules/server/mealie.nix:38`) |
| paperless | `paperless` | the NixOS module creates `paperless-web`, `-scheduler`, `-consumer`, `-task-queue` (confirm with `systemctl list-units 'paperless*'`) |

`just service restart ntfy` fails with "Unit ntfy.service not found".

### B4 — Service list has drifted from the modules  ·  HIGH
`_server_service_names` (line 1751) is hand-maintained. These modules declare
`vexos.server.<x>.enable` and appear in `template/server-services.nix`, yet
`just service enable <x>` rejects them as "unknown service":
**`mediamanager`, `sportarr`, `tdarr`, `listenarr`, `bookshelf`** (and
`alertmanager`, `cloudflare-ddns`, `fluent-bit`, if they are meant to be user-toggled).

Root cause: service metadata is copied into **five** hand-synced tables (see §3, D1).

### B5 — Relative paths resolve against `/etc/nixos`, not the user's directory  ·  MEDIUM
Because of `--working-directory /etc/nixos`:
- `just backup-plex` with no argument writes `./plex-backup-*.tar.gz` **into `/etc/nixos`**.
- `just restore-plex plex.tar.gz` run from `~` reports "not found".
- `_run-storage-script` and the kiji-proxy block "walk up from `$PWD`", which is always `/etc/nixos`.

Fix: resolve user paths against `invocation_directory()`, or mark those recipes `[no-cd]`.

### B6 — Doc comments shown in `--list` and VexPortal are sentence fragments  ·  MEDIUM
`just` uses only the **last** comment line before a recipe as its doc. In 15 of the
39 public recipes, that line is the tail of a longer paragraph. Excerpt from `just --dump`:

```
secrets-init     "the right tool for the job."
nas-sync-status  "fixed list."
deploy           "seconds and are never the cause of a cache block."
update           "never the cause of the block. See pkgs/vexos-update/default.nix."
update-all       "and take a long time.  For normal daily use, run 'just update' instead."
reset-defaults   "results, since GNOME may re-write some keys while running."
switch           "just switch desktop vm "" "" virtualbox — VM hypervisor (qemu / virtualbox)"
build            "Example: just build desktop amd"
backup-now       "Requires vexos.server.backup.enable = true."
backup-plex / restore-plex / restore-service / nas-sync-now / set-hostname / ssh / upgrade-analysis …
```
VexPortal reads the same `doc` field (`catalog/src/lib.rs:5` mentions `backup-plex`
documenting itself this way), so the GUI shows these fragments too.
Fix: add `[doc('…')]` (just ≥1.27) to every public recipe. Long comments can stay as plain comments.

### B7 — Interactive `read` under `set -e` partially applies changes when there is no TTY  ·  MEDIUM
VexPortal runs recipes with stdin at `/dev/null`. `read -r -p …` returns 1 at EOF, so
`set -e` aborts the script. In `_service-enable`, the enable flag is written to
`server-services.nix` **before** the Plex Pass, Proxmox, backup, arr, and zigbee prompts.
For example, enabling `plex` with no TTY writes `plex.enable = true` and then exits non-zero.
That skips the backup auto-enable and the summary, leaving the file half-configured.
`_menu` already handles this correctly with `[ -t 0 ] || …`. The per-service prompts need
the same guard: take the default, or fail **before** writing anything.

### B8 — `just kernel status` never shows pinned versions on deployed hosts  ·  LOW
`_kernel-status` globs `{{justfile_directory()}}/pkgs/kernels/*/version.json`, which is
`/etc/nixos/pkgs/…`. `pkgs/` is not deployed, and `nullglob` hides the miss, so the
"Pinned kernel versions" heading always prints with nothing under it.

### B9 — Smaller defects
- `build`'s doc says "Dry-run build without switching" but it runs `nixos-rebuild build`, which builds fully and writes a root-owned `result` link in `/etc/nixos`.
- `zigbee2mqtt` enable prints "✓ Enabled" and "Run 'just rebuild'" twice (lines 3014/3143 and 3570–3571).
- `vexboard` enable text says to disable by hand-editing the file instead of `just service disable vexboard`.
- `kiji-proxy` enable runs `sed -i` on a **source file** (`pkgs/kiji-proxy/default.nix`) found by walking the filesystem. A runtime admin command should not mutate a repo checkout.
- Stale comments: line 1754 references `just available-services` (it is `just service available`). Line 2817 says `justfile_directory()` is "~" (it is `/etc/nixos`).
- `_service-info` shows kiji-proxy on `:8080`, which is also SABnzbd's port in the same table. That is a real conflict or a stale value, so verify it.
- `just --fmt --check --unstable` reports ~197 changed lines (cosmetic).
- Shellcheck was **not** run during this review: the extraction command was blocked. It should be run as part of implementation (see §6).

---

## 3. Findings: design and maintainability

### D1 — Service metadata is duplicated five times
For each server service, data is hand-copied into:
1. `_server_service_names` (validation list)
2. `_service_catalog` (group | name | description)
3. `_service-info` `case` (port and URL text)
4. `_service-units` `case` (systemd units)
5. `_service-status` `URLS` `case` (health-check URLs)

…plus the per-service blurb in `_service-enable` (~430 lines), plus
`template/server-services.nix` and `modules/server/default.nix`. B3 and B4 are direct
results of this. **Proposal:** extend the single `_service_catalog` heredoc to
`group|name|units|url|description` and derive 1, 3, 4, and 5 from it in bash (`cut`/`awk`).
That replaces ~250 lines of `case` with one table. Better still, generate the
catalog from Nix option metadata at build time. `prune-services` already derives names from
option declarations, so the precedent exists.

### D2 — Copy-pasted blocks
| Pattern | Copies | Proposed helper |
|---|---|---|
| Role / GPU / NVIDIA picker | 2 (`switch`, `update`) | `_pick-target` (fixes B2 for free) |
| `command -v vexos-ai … \|\| exit` guard | 8 | `_require-ai` dependency |
| `nix` / `sudo` / `uname` preflight | 2 | `_require-nixos` dependency |
| Template-locate-and-copy for `features.nix` / `server-services.nix` | 3 | one `_seed-from-template <name>` |
| "replace-or-append `key = value;`" sed | ~12 | one `_nix_set_option` bash function, sourced from `scripts/lib/` |
| "valid service?" check | 4 | one `_require-known-service` |
| Typed-`yes` confirmation | 2 | `_confirm` with a `typed` mode |

### D3 — Size: one 3,970-line file
`just` supports `import 'path.just'`, which merges recipes into the same namespace.
Recipe names and the VexPortal contract stay the same. Proposed split:
```
justfile                 (settings, default, shared helpers, imports)
just/system.just         switch build rebuild update deploy rollback…
just/admin.just          hostname ssh reset-defaults remote-storage bootloader
just/features.just       feature fix-flake
just/vpn.just
just/ai.just
just/server.just         service plex-pass zfs/mergerfs backup/restore nas-sync secrets-init
just/server-enable.just  _service-enable and its per-service text (the bulk)
just/cache-kernel.just
```
`mod` (namespaced submodules) would also give `just server …`. **Do not use `mod`**: it
renames every recipe and breaks VexPortal and users' habits. Deployment change needed:
`environment.etc."nixos/just".source = ../just;` alongside the justfile, and the
impermanence relink in `modules/impermanence.nix:262-272` must cover it too.

### D4 — Argument interpolation into bash
Most recipes write `VAR="{{arg}}"`. An argument containing `"`, `$(…)`, or a
backtick is executed by bash. VexPortal's daemon runs **as root** but validates every
argument (`Slug`, `AbsPath` formats in `catalog/src/validate.rs`), so the practical risk
today is low. The justfile itself has no defense, though. The `ai-*` recipes already use
`{{quote(x)}}`. Adopt `set positional-arguments` with `"$1"`, or `quote()`, everywhere. Also
add `[arg('x', pattern='…')]` (just ≥1.45) on enum-like parameters such as `role`,
`variant`, `de`, `vmp`, `action`, and service names, so `just` rejects bad input before the script runs.

### D5 — Recursive `just` calls
Recipes call bare `just …` about 40 times. This works only because cwd is `/etc/nixos`.
The robust form is `{{just_executable()}} --justfile {{justfile()}} …`, which can be put in a
variable (`_just := just_executable() + " -f " + justfile()`).

### D6 — Grouping and visibility inconsistencies
- 8 public recipes have no `[group]` and appear first, in an untitled "Available recipes" block.
- `service`, `plex-pass`, `zfs-pool`, and `mergerfs-pool` are the main server commands, but they are
  `[private]`. They are advertised through a hand-written `echo` block in `default`, so they are
  missing from `--list`, from shell completion, and probably from VexPortal's drift check. `prune-services`
  is private and reachable only by name.
- Group names mix styles ("Optional Feature Toggles" vs "VPN").

---

## 4. Menu and look-and-feel improvements

### Current
```
Available recipes:
    kernel action="" *args                          # Custom kernel builder (server): …
    secrets-init                                    # the right tool for the job.
    …
    [System Build & Deploy]
    switch role="" variant="" flake="" de="" vmp="" # just switch desktop vm "" "" virtualbox — …
```
Submenus (`_menu`): plain text, a fixed-length rule, `%-14s` keys, `0) Quit`,
"  invalid" on bad input, and no colour.

### Proposed
1. **Fix the top-level list** (cheap, high impact):
   `[doc]` on every public recipe (B6), a `[group]` on every public recipe, and a `default` recipe
   that runs `just --list --unsorted` so groups follow file order (most-used first)
   instead of alphabetical order. Role-aware: server recipes get real groups, and the hand-written
   `echo` list is deleted.
2. **Short, uniform group names** with a consistent order, e.g.
   `system` · `maintenance` · `features` · `network` · `ai` · `server` · `storage` · `cache`.
3. **Parameter help:** `[arg('role', help='desktop|stateless|htpc|server|vanilla', pattern='…')]`
   (just ≥1.46) makes `just switch --help`-style usage self-documenting and shortens the
   `--list` signature column.
4. **`_menu` polish** (one function, so every menu benefits):
   - Colour via `tput`, only when stdout is a TTY and `NO_COLOR` is unset. Use a bold title, dim
     descriptions, and cyan keys. `_service-available` and `_kernel-status` already use raw ANSI
     codes inconsistently, so centralize them.
   - A title rule sized to the terminal (`tput cols`), not a fixed string.
   - Visually separate read-only items from actions that change things (e.g. a `·` marker, or a
     blank line between sections), and mark destructive actions (`⚠`).
   - Accept the key name as well as the number (`Choice [1-8 or name]`), matching `switch`'s
     own prompts.
   - A clearer invalid-input message: `"Enter 1-8, a name, or 0 to quit"`.
   - After a `stay` action, print "Press Enter to return to menu" so output isn't
     scrolled away by the redrawn menu.
5. **Optional fuzzy picker:** `fzf` is already on this machine. When `fzf` is
   available, `_menu` can offer it (searchable, with a preview of each action's description) and
   fall back to the numbered menu otherwise. Universal Blue's `ujust` does the
   equivalent with `gum` (`Choose()` → `ugum choose`), but adding `gum` is a new
   dependency and it has **no non-TTY fallback**. Keep the numbered menu as the baseline because
   VexPortal and SSH sessions depend on it.
6. **Top-level chooser:** add a `pick` / `menu` recipe running `just --choose`
   (built in, uses `$JUST_CHOOSER` or fzf). It skips recipes that need arguments, which here
   is almost none because nearly all parameters have defaults.
7. **Consistent output vocabulary:** one small helper set (`_ok`, `_warn`, `_err`, `_step`)
   for `✓ / ⚠ / ✗ / →`. Currently the markers vary by recipe (`✓ Enabled`, `✗ Disabled`
   used for a successful disable, `+ Backups also enabled`, plain `error:`).
8. **`reboot` / `shutdown`:** add `[confirm('Reboot now?')]` (just ≥1.23). These currently
   act immediately with one typo-able word. Note that `[confirm]` cannot be satisfied by
   `VEXOS_ASSUME_YES`, though `just --yes` can. Coordinate with VexPortal first.

---

## 5. Constraints and risks

| Risk | Mitigation |
|---|---|
| VexPortal contract (names, parameter order, `doc`) | Keep names and parameter order identical; `import` rather than `mod`; run VexPortal's `drift_against_justfile` test against the new file before merging |
| `import` needs extra files under `/etc/nixos` | Deploy `just/` via `environment.etc`; update the impermanence relink; vanilla role does not import the justfile, so nothing changes there |
| `[confirm]` and `[arg pattern]` change behaviour for non-interactive callers | Gate on VexPortal behaviour; patterns must accept every value VexPortal sends |
| Large mechanical refactor of `_service-enable` | Do it last, behind the catalog table, one service family at a time |
| `just` version floor | All proposed attributes are ≤1.46; installed 1.51. Add a comment noting the minimum version |
| SMB / remote-storage fragility | No changes proposed to the storage scripts themselves; only path resolution in the wrapper recipes |

---

## 6. Proposed implementation plan (tiered, each tier independently shippable)

**Tier 1 — Bug fixes (no UX change, no contract change)**
1. B1 `switch` exit code → verify: `nixos-rebuild` failure yields non-zero `just` exit.
2. B2 make `update` pass the chosen target, or remove the picker if `vexos-update` cannot take one.
3. B3 fix the ntfy/mealie/paperless units → verify on server with `systemctl list-units`.
4. B4 add the missing services → verify: `just service enable tdarr` accepted.
5. B5 resolve plex paths with `invocation_directory()`.
6. B7 add TTY guards before the first write in `_service-enable`.
7. B8, B9 small fixes.
Verify: preflight + `just --justfile justfile --dump --dump-format json` diff shows
no recipe or parameter changes.

**Tier 1 — decisions taken during implementation**
- B2: `vexos-update` cannot take a target, so the picker writes the chosen target to
  `/etc/nixos/vexos-variant` before calling it. That is safe on every role: NixOS etc
  activation (`setup-etc.pl` `atomicSymlink`) renames over a plain file, and on stateless
  the activation script rewrites it anyway. Picker gains `vanilla` to match `switch`.
- B3: also filter `_service-units` to units that exist (`systemctl list-unit-files`).
  Without this, `restart` fails for every docker+podman pair (arcane, dockhand, portainer)
  and for tdarr with `node.enable = false`. `status`/`restart` report "no units" instead.
- B4 scope: only the four services the template already exposes (`listenarr`,
  `mediamanager`, `sportarr`, `tdarr`). `bookshelf`, `alertmanager`, `cloudflare-ddns`,
  and `fluent-bit` were never in the template; whether to expose them is the user's call.
  `mediamanager` gets an admin-e-mail prompt because its module asserts `adminEmails != []`.
- B5 scope: `backup-plex`/`restore-plex` only. `_run-storage-script`'s `$PWD` walk is left
  as is because it feeds the remote-storage/SMB scripts. Its `getFlake` fallback also lacks
  `--impure` and therefore never works. Both are reported, not changed.
- B7: services that prompt (`arr plex proxmox backup zigbee2mqtt mediamanager`) are
  refused before any write when stdin is not a TTY.
- B9 not done: the kiji-proxy source-file patching (behaviour decision), and the kiji-proxy and
  SABnzbd collision on port 8080 (module-level, not justfile).

**Tier 2 — Presentation (contract-safe)**
`[doc]` on all public recipes, groups on all public recipes, server recipes made
public with real groups, `--list --unsorted` default, `_menu` colour/width/name-input,
output helpers, `just pick`. Verify: `just --list` screenshot before/after; VexPortal
drift test passes.

**Tier 2 — decisions taken during implementation**
- VexPortal reads only `private`, `doc`, and `parameters` from the dump (not `group`), and uses
  `doc` only in drift messages. It reports any *public* recipe that its catalog neither
  starts nor excludes as drift ("VexPortal is out of step"). Therefore:
  - `service`, `plex-pass`, `zfs-pool`, `mergerfs-pool` become public: the catalog already starts all four.
  - `prune-services` stays private (not in the catalog).
  - The new `pick` chooser is **private**, callable by name and advertised in the list heading.
- Existing group names are kept (renaming is churn with no reader benefit). New groups:
  `Server` (the formerly ungrouped server recipes, plus `service`, `plex-pass`) and `Storage`
  (`remote-storage`, `zfs-pool`, `mergerfs-pool`). `kernel` joins `Binary Cache`.
- Every public recipe gets a one-line `[doc]`, with signature usage removed (the list already
  shows parameters) and a "(menu)" suffix on commands that open a menu when run bare.
- `_menu`: a 4th item field `warn` marks disruptive actions (⚠). Read-only `stay` actions
  are left unmarked as the safe default. Colour only when stdout is a TTY and `NO_COLOR` is unset.
  Non-TTY output (VexPortal) is byte-identical.
- Deferred to Tier 3: unifying `✓/⚠/✗` output across all recipes (~300 echo lines, best
  done together with the helper refactor), `[confirm]` on reboot/shutdown (needs
  VexPortal coordination), and `[arg(help/pattern)]`.

**Tier 3 — Structure (larger)**
Single service catalog (D1), shared helpers (D2), `import` split (D3),
`positional-arguments`/`quote()` + `[arg pattern]` (D4), `just_executable()` (D5),
shellcheck over all shebang recipes added to preflight.

---

## 7. Sources

- just manual — attributes table (`[doc]`, `[group]`, `[confirm(PROMPT)]`, `[arg(… pattern/help)]`, `[default]`, `[no-cd]`, `[positional-arguments]`, `[script]`): https://just.systems/man/en/attributes.html (via Context7 `/websites/just_systems_man_en`)
- just manual — documentation comments and `[doc]`: https://just.systems/man/en/documentation-comments.html
- just manual — recipe parameters and `[arg pattern]`: https://just.systems/man/en/recipe-parameters.html
- just manual — `[no-cd]`: https://just.systems/man/en/disabling-changing-directory.html
- just manual — confirmation: https://just.systems/man/en/requiring-confirmation-for-recipes.html
- just manual — interactive chooser (`--choose`, `JUST_CHOOSER`): https://just.systems/man/en/selecting-recipes-to-run-with-an-interactive-chooser.html
- Universal Blue `ujust` helper library (`Choose`/`Confirm` via `ugum`): https://github.com/ublue-os/packages/blob/main/packages/ublue-os-just/src/lib-ujust/libfunctions.sh
- ublue-os/packages — ujust system management overview (composed justfile from `*.just` parts): https://deepwiki.com/ublue-os/packages/4.1-ujust-system-management
- BlueBuild justfiles module (importing multiple `.just` files into one user justfile): https://blue-build.org/reference/modules/justfiles/
- Bazzite ujust docs (`ujust --show`, recipe file layout): https://docs.bazzite.gg/cs/Installing_and_Managing_Software/ujust/
- hledger + just (chooser with preview pattern): https://hledger.org/just.html
- VexPortal source (contract: `just --dump --dump-format json`, root daemon, stdin null, arg validation): `github:VictoryTek/VexPortal` — `daemon/src/executor.rs`, `nix/module.nix`, `catalog/src/drift.rs`, `catalog/src/validate.rs`

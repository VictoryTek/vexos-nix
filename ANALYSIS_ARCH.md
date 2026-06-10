# vexos-nix — Architecture & Structure Analysis

Date: 2026-06-09
Scope: architecture and structure only (no functional/security audit beyond structural findings).
Method: full read of `flake.nix`, all `configuration-*.nix`, sampled `hosts/`, `modules/`, `modules/server/`, `modules/gpu/`, `pkgs/`, `scripts/`, `template/`, CI workflow, and repo-wide greps for pattern consistency.

Priorities: **HIGH** = actively causes drift, breakage risk, or violates the project's own architecture; **MEDIUM** = inconsistency or debt that will bite during maintenance; **LOW** = hygiene/cosmetic.

---

## 1. Architectural anti-patterns / design problems

### 1.1 HIGH — Builder-machine state leaks into flake outputs (impure eval by design, but leakier than documented)

**Files:** `flake.nix:89-99` (`serverServicesModule`, `statelessUserOverrideModule`), `flake.nix:217` (`/etc/nixos/hardware-configuration.nix`)

The "thin flake" choice to import `/etc/nixos/hardware-configuration.nix` is documented and deliberate. But `serverServicesModule` and `statelessUserOverrideModule` go further: they call `builtins.pathExists` on absolute paths **at flake evaluation time on whatever machine is evaluating**. Consequences:

- Evaluating `vexos-server-amd` from a desktop dev machine silently builds *without* the target's `server-services.nix`; evaluating it on a machine that happens to have one bakes *that machine's* service set into the output. The same output name produces different systems depending on where `nix` runs.
- Every consumer (CI, preflight, `nix flake show`) must use `--impure` and stub files, which CI indeed does — the impurity has propagated into all tooling.
- Outputs are not cacheable/comparable across machines (relevant since the project runs its own Attic cache, `modules/nix.nix`).

The repo already contains the correct alternative: the `nixosModules.*Base` exports consumed by `template/etc-nixos-flake.nix`, where the *host* flake supplies host-local files. Maintaining the impure direct path alongside it doubles the architecture (see 1.2).

### 1.2 HIGH — Two parallel distribution pathways that have already drifted, despite a comment claiming they cannot

**Files:** `flake.nix:120-124` (claim), `flake.nix:197-224` (`mkHost`), `flake.nix:285-314` (`mkBaseModule`)

The comment at `flake.nix:120-124` states that deriving both `mkHost` and `mkBaseModule` from the `roles` table "is what prevents the historical drift." It does not. `mkBaseModule` only consumes `roles.<role>.homeFile` and `extraModules`; it **re-implements** everything in `baseModules` by hand:

- `flake.nix:303-311` duplicates the unstable overlay verbatim instead of reusing `unstableOverlayModule` (`flake.nix:56-65`).
- `flake.nix:312-313` re-expresses the `upModule` inclusion as a role-name predicate (`role != "headless-server" && role != "vanilla"`) instead of reading `roles.<role>.baseModules`.
- `flake.nix:289-293` re-lists the proxmox/sops/vexboard wiring with its own `role == "server" || role == "headless-server"` conditionals, parallel to `proxmoxBase`/`sopsBase`/`vexboardBase` (`flake.nix:105-118`).

**Concrete drift already present:** `roles.vanilla.baseModules = []` (`flake.nix:165-169`) — the direct `vexos-vanilla-*` outputs get *no* overlays, matching the "stock NixOS baseline" intent. But `mkBaseModule` applies the unstable overlay and the `./pkgs` overlay unconditionally (`flake.nix:303-311`), so `nixosModules.vanillaBase` ships custom overlays the vanilla role is documented not to have. Latent today (vanilla configs don't reference `pkgs.unstable.*` yet), but it is exactly the class of divergence the comment claims is impossible. Any future edit to `commonBase` must be remembered in two places.

### 1.3 HIGH — `vexos.user.name` is a half-implemented abstraction: the option exists, the account is hardcoded

**Files:** `modules/users.nix:10-15` (option, "override per-host if needed"), `modules/users.nix:25` (`users.users.nimda = { ... uid = 1000; ... }`), `flake.nix:179-180` and `flake.nix:297-298` (home-manager keyed on `config.vexos.user.name`)

The option's description promises the primary user is configurable. It isn't:

- The account is literally `users.users.nimda`; overriding `vexos.user.name` only changes the account's `description` field (`modules/users.nix:27` — `description = cfg.name;`, which is itself wrong: a username is not a GECOS description).
- Home Manager wiring (`flake.nix:180`, `:298`) and every `extraGroups`-appending module key off `config.vexos.user.name`. Set it to anything other than `"nimda"` and home-manager configures a user that does not exist while `nimda` still gets created.

Either make `users.users.${cfg.name}` dynamic (the infinite-recursion concern in the comment at `modules/users.nix:18-22` applies to *reading* `users.users`, not to using the option value as a key — every other module already does this), or remove the option's "override per-host" promise.

### 1.4 HIGH — Runtime `git clone` of a moving HEAD + on-boot Docker image build (odysseus)

**Files:** `modules/server/odysseus.nix:96-103` (clone), `:121` (`docker-compose up -d --build`), `:67-69` (`chromadb/chroma:latest`)

The service's `preStart` clones `https://github.com/.../odysseus.git` (default branch, depth 1, no rev pin) into `/var/lib/odysseus/src` and builds the Docker image at service start. Commit `00faec7` ("remove fakeHash from odysseus, clone source at runtime") shows this replaced a proper Nix fetch because hashing was inconvenient. Problems:

- The deployed application version is whatever GitHub serves at first boot — unreproducible, unauditable, and different on every machine. This inverts the entire premise of a Nix-managed system.
- A compromised or force-pushed upstream repo executes arbitrary code as root-adjacent (docker build) with no hash verification.
- Re-deploys never update the app (clone is skipped if `src/.git` exists) — there is no declared upgrade path.

The Nix-native shape is `pkgs.fetchFromGitHub` with a pinned rev + `dockerTools.buildImage`, or at minimum pinning a commit/tag in the clone.

### 1.5 MEDIUM — Three coexisting deployment paradigms inside `modules/server/`

**Files:** e.g. native NixOS services (`modules/server/forgejo.nix`, `grafana.nix`, `jellyfin.nix`), `virtualisation.oci-containers` (`portainer.nix:23-31`, `homepage.nix`, `authelia.nix`, `dozzle.nix`, `dockhand.nix`, `stirling-pdf.nix`, `nginx-proxy-manager.nix`), and a hand-rolled `docker-compose`-in-a-oneshot-systemd-unit (`odysseus.nix:107-125`).

Each paradigm has different logging, restart, upgrade, and state semantics. The compose-in-systemd variant in particular bypasses both NixOS service management and `oci-containers`' declarative model (stop/start is `RemainAfterExit` oneshot; `systemctl status` lies about container health). Pick `oci-containers` as the single containerized-service pattern; reserve compose only where multi-container topology genuinely requires it, and document that exception.

### 1.6 MEDIUM — A 240-line shell application embedded as a string in a NixOS module

**Files:** `modules/nix.nix:130-243` (`vexos-update` via `writeShellScriptBin`), with the same heavy-build classification logic duplicated again at `modules/nix.nix:147` and `scripts/install.sh:368` (see 3.3)

`vexos-update` is a real program (lock backup/rollback, dry-build parsing with `awk`, regex classification engines, a stdout protocol consumed by the Up GUI) living inside a Nix string. It gets no shellcheck, no syntax check in preflight (which does run `bash -n` on `scripts/*.sh`), and bloats a module whose stated purpose is "Nix daemon configuration." Move it to `pkgs/vexos-update/` (or `scripts/`) and use `writeShellApplication` (which shellchecks at build time) — the project already has the `pkgs/` + overlay infrastructure for exactly this.

### 1.7 MEDIUM — ~2,000-line `justfile` as the operational control plane

**File:** `justfile` (1,995 lines, 18 top-level recipes, large embedded bash blocks including service enable/disable editing of `/etc/nixos/server-services.nix`)

The justfile is effectively a CLI application written in untestable, unlintable embedded bash. The role-detection/menu logic, flake-dir resolution, and service management each belong in standalone scripts under `scripts/` (lintable, shareable with `vexos-update`/installer logic), with the justfile reduced to thin dispatch.

---

## 2. Structural inconsistencies (naming, organization, module boundaries)

### 2.1 HIGH — `hosts/` files are not hosts; personal hardware config is baked into shared GPU variants

**Files:** `hosts/desktop-amd.nix:11-12`, `hosts/desktop-nvidia.nix:11-12`, `hosts/desktop-intel.nix:11-12` (all set `vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80;`); placeholder `networking.hostId` values with "REQUIRED: replace with the real value from the target host" in `hosts/server-amd.nix:16`, `hosts/headless-server-vm.nix:15`, and sibling server/headless host files.

The directory is named `hosts/` and CLAUDE.md calls them "per-variant NixOS host configs," but each file is a *role×GPU variant* shared by every machine that builds that output. Two boundary violations follow:

- Every consumer of `vexos-desktop-amd/nvidia/intel` gets ASUS laptop daemons and an 80% battery charge limit forced on, because the author's machines are ASUS laptops. That is per-machine config living in a shared variant file — the exact thing the thin-flake design pushes to `/etc/nixos`.
- ZFS-relevant `hostId` values are committed as shared placeholders (`a0000001`, `b0000004`, …). Every machine building `vexos-server-amd` shares hostId `a0000001` unless the user edits a tracked file — which the template-flake consumption model gives them no way to do. Per-machine identity belongs in the host-side override mechanism, not the repo.

Suggested split: rename the concept (these are `variants/`, not `hosts/`) or actually move per-machine deltas (asus, hostId, distroName suffix) behind options defaulted off.

### 2.2 MEDIUM — The project's own core modules violate its declared "Option B" pattern, in three different styles

**Files (declared rule):** CLAUDE.md "Module Architecture Pattern" — universal base files contain "NO `lib.mkIf` guards," existing guards are "tech debt to be eliminated."
**Files (violations in shared/universal modules):** `modules/system.nix:63,73,148,161`; `modules/network.nix:108`; `modules/flatpak.nix:51` (whole module gated on `vexos.flatpak.enable`); `modules/branding.nix:132`; `modules/gnome-flatpak-install.nix:40`; `modules/nix.nix:49`; `modules/impermanence.nix:82,236`; `modules/stateless-disk.nix:63`.

Meanwhile `modules/server/*` (57 files) uniformly uses the standard NixOS `options` + `config = lib.mkIf cfg.enable` idiom, and `modules/gpu/` uses pure import-composition. So the codebase actually contains **three** module paradigms: import-composition (Option B), option-gated shared modules, and enable-flag service modules. The server-module style is defensible (opt-in services need flags), but the rule as written doesn't carve it out, and the shared-module guards keep accumulating (`flatpak.nix`'s whole-module `mkIf` is structurally identical to what the rule forbids). Either eliminate the listed guards or amend the documented rule to define where option-gating is legitimate — right now the doc and the code disagree, which makes every review call ambiguous.

### 2.3 MEDIUM — Documentation/comment drift about the system's own shape (counts, group layout)

- CLAUDE.md says "The flake defines 30 outputs"; `flake.nix:227` says "34 outputs total: 30 historical + 4 vanilla." The flake is right; the orchestration doc is stale.
- `.github/workflows/ci.yml:64-65`: comment says "4 groups × ~5 min" and "all 22 configs"; the matrix actually has **6** groups (`ci.yml:78-114`) covering 34 configs.
- `scripts/preflight.sh:14`: stage description says "all 5 configuration-*.nix files"; the check at `:148-153` iterates 6.
- `flake.nix:250-259`: `# NEW` markers left on server/headless legacy-NVIDIA entries from whenever they were added.

None of these break builds, but this is the project's *control documentation* (CLAUDE.md drives the agent workflow; CI comments drive maintenance expectations), and all three disagree with reality in the same direction (vanilla role added without sweeping the docs).

### 2.4 LOW — Stale file-rename residue in comments

- `modules/network.nix:3`, `modules/gpu/vm.nix:10`, `modules/branding.nix:5` all reference `modules/performance.nix`, which does not exist (its content lives in `modules/system.nix`).
- `hosts/desktop-amd.nix:1` header still reads `# hosts/amd.nix` (pre-rename).
- `modules/gpu.nix:4` says variants are "imported by the host config in `hosts/{amd,nvidia,vm}.nix`" — that naming scheme is gone.

Low individually, but three pointers to a nonexistent file will misdirect anyone (or any agent) following them.

### 2.5 LOW — Naming-scheme seams

- Output names use `legacy535`/`legacy470` while the option value uses `legacy_535`/`legacy_470` (`flake.nix:228-229`, acknowledged in a comment). Harmless but permanently confusing at the CLI/option boundary.
- Home Manager layout is split inconsistently: role entry points at repo root (`home-desktop.nix`, …) but shared submodules under `home/` (`home/bash-common.nix`, …). The flat-root layout is documented for `configuration-*.nix`, but having a `home/` directory that contains *some* of the home config invites misplacement. Either move role files into `home/` or rename the dir `home/common/`-style.

---

## 3. Inconsistent patterns (same thing done differently in different places)

### 3.1 MEDIUM — Firewall exposure: ~18 modules make it optional, ~35 open ports unconditionally

**Examples with an `openFirewall`/conditional option:** `modules/server/seerr.nix:65-66` (`lib.mkIf cfg.openFirewall`), `modules/server/adguard.nix:66` (`lib.optional cfg.openDnsFirewall 53`), plus 16 others (grep `openFirewall` in `modules/server/`).
**Examples that open unconditionally:** `forgejo.nix:30`, `code-server.nix:55`, `kavita.nix:20` (hardcoded `5000`), `netdata.nix:18` (hardcoded `19999`), `portainer.nix:33`, `prometheus.nix:43`, `grafana.nix:47`, `proxmox.nix:124`, `portbook.nix:71` (hardcoded `7777`), `loki.nix:65` (hardcoded `3100`), `odysseus.nix:127`, ~25 more.

Two problems: (a) a user fronting services with the also-provided reverse proxies (`caddy.nix`/`traefik.nix`/`nginx.nix`) cannot keep backend ports LAN-closed for most services; (b) whether `enable = true` exposes a port to the network depends on which module you happen to enable — there is no rule a user can learn. Secondary inconsistency inside the same axis: some modules parameterize the port (`cfg.port`) and others hardcode it in both the service and the firewall line (`kavita`, `netdata`, `portbook`, `loki`, `ntfy.nix:27` `2586`, `unbound.nix:32` `5353`). Standardize on `port` + `openFirewall ? default true` across all 57 modules.

### 3.2 MEDIUM — Container image pinning: `:latest` in 7 modules, pinned tags elsewhere

**Unpinned:** `portainer.nix:25`, `homepage.nix:23`, `stirling-pdf.nix:23`, `authelia.nix:29`, `nginx-proxy-manager.nix:38`, `dockhand.nix:57`, `dozzle.nix:25`, plus `odysseus.nix:67` (`chromadb/chroma:latest`).
**Pinned:** `odysseus.nix:75` (`searxng/searxng:2026.5.31`) — pinned and unpinned images in the *same compose file*.

`:latest` means a reboot or container recreation silently changes the deployed software version, outside any Nix generation — rollback via `nixos-rebuild --rollback` won't restore the previous app. For a flake whose whole pitch is reproducible roles, image digests/tags should be pinned uniformly (and `authelia:latest` guarding auth is the worst of the set).

### 3.3 MEDIUM — `HEAVY_BUILD_REGEX` exists in three places with two different values

**Files:** `modules/nix.nix:147` and `modules/nix.nix:194` (both `^(linux-[0-9][^/]*-modules|...|openrazer-[0-9])`), `scripts/install.sh:368` (`^(NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])` — no kernel-module patterns).

The installer's variant may be intentionally narrower (kernel handled by the separate fallback path), but nothing records that, and the two copies inside `nix.nix` alone are pure duplication. When the heavy-package list changes (it already has history: the retired A/B/C engine comments at `modules/nix.nix:185-193`), three sites must be updated in lockstep. Define it once (single script per 1.6, or a shared sourced fragment).

### 3.4 LOW — `distroName` precedence handled three different ways

`configuration-server.nix` / `-htpc.nix` / `-headless-server.nix` use `lib.mkOverride 500` with explanatory comments; host files use bare assignments (`hosts/*.nix`); `modules/branding.nix` supplies the `lib.mkDefault`. The 500/1000/100 priority dance works but is re-derived in comments at every site; a single `vexos.branding.distroName` option with documented precedence would remove the need for priority arithmetic in role files.

### 3.5 LOW — Secrets consumption split across two conventions

`modules/secrets.nix` (plaintext files under `/etc/nixos/secrets`, tmpfiles-enforced perms) and `modules/secrets-sops.nix` (sops backend, default `"plaintext"` at `modules/secrets-sops.nix:11-13`). Individual server modules variously take `passwordFile`-style path options (`nextcloud.nix:70`, `photoprism.nix:27`) while the sops module hardcodes assertions for exactly six secret names (`secrets-sops.nix:49-90`), coupling the generic backend module to a specific subset of services. Adding a seventh sops-managed secret means editing the backend module — inverted dependency. A per-service `secretFile` option resolved through one helper would scale; today's shape is a transition state (see 4.2).

---

## 4. Half-implemented or abandoned

### 4.1 HIGH — In-flight, uncommitted "install kernel fallback" feature (work in progress, not abandoned — but currently a mixed working tree)

**Files:** modified & uncommitted: `modules/nix.nix`, `scripts/install.sh`, `template/etc-nixos-flake.nix`; untracked: `.github/docs/subagent_docs/install_kernel_fallback_spec.md`, `_review.md` (review dated today, graded A, but notes `dry-build` was **not run** — sandbox lacked sudo).

The feature spans installer + update script + template and is sitting half-landed in the working tree. Until committed (after a real dry-build on a NixOS host), every other change rides on top of an unvalidated kernel-fallback diff. Flagged here because anyone analyzing or building from this tree gets the WIP state.

### 4.2 MEDIUM — sops backend is opt-in scaffolding that nothing defaults to

`vexos.secrets.backend` defaults to `"plaintext"` (`modules/secrets-sops.nix:11-13`); sops-nix is wired into both server roles via `sopsBase` (`flake.nix:118,148,162`) and the input is pinned, but with the default backend the entire sops module is dead config on every deployment unless a user hand-assembles a `secrets.yaml` matching the six asserted names. There is no template, no example sops file, and no migration script — the encrypted backend is built but effectively unreachable. Either ship the on-ramp (example secrets file + docs + `just` recipe) or it will stay permanently at "plaintext."

### 4.3 LOW — `overlays/` directory is empty yet documented as a key directory

CLAUDE.md "Key Directories" lists `overlays/ — nixpkgs overlays`; the directory contains nothing and nothing references it (overlays actually live inline in `flake.nix` and in `pkgs/default.nix`). Remove the dir + doc line, or move the inline overlays there.

### 4.4 LOW — Expired dated TODO

`modules/server/plex.nix:43`: `TODO(2026-05): Remove this workaround once the upstream nixpkgs Plex module …` — the date has passed (today is 2026-06); the workaround should be re-checked against nixpkgs 25.11 and either removed or re-dated.

### 4.5 LOW — Retired-protocol archaeology accumulating in live code

`modules/nix.nix:121-127, 185-193` carries comment blocks documenting *two* generations of retired stdout prefixes and a retired three-class regex engine. Useful once; now it's a third of the module's commentary describing code that no longer exists. Git history holds this better.

---

## 5. Dependencies — unnecessary, misused, or outdated

### 5.1 MEDIUM — Unpinned runtime dependencies bypassing the lock file entirely

The flake.lock pins all Nix inputs correctly (incl. documented `follows` exceptions, `flake.nix:5-46` — this part is clean). But two whole classes of dependencies escape it:

- OCI images at `:latest` (7 modules, see 3.2) — version is whatever the registry serves.
- The odysseus source tree cloned at runtime (1.4) — version is whatever GitHub serves.

These are the only dependencies in the system that can change without a `flake.lock` diff, which makes them the only un-reviewable upgrades.

### 5.2 LOW — `intel-media-driver` shipped to every GPU build

`modules/gpu.nix:18` adds `intel-media-driver` to `hardware.graphics.extraPackages` for *all* builds with the comment "harmless on AMD/NVIDIA." It is harmless but contradicts the project's own pattern: brand-specific drivers belong in `modules/gpu/{intel,…}.nix` (where `modules/gpu/intel.nix` exists precisely for this). Dead weight in AMD/NVIDIA/VM closures.

### 5.3 LOW — Committed Python bytecode artifact

`scripts/__pycache__/configure-network.cpython-313.pyc` is tracked in git (confirmed via `git ls-files`). Bytecode is machine/Python-version-specific build output; remove and add `__pycache__/` to `.gitignore`.

### 5.4 LOW — Repo weight from process artifacts

`.github/docs/subagent_docs/` holds **384** spec/review markdown files (4.9 MB) — every historical feature's Phase-1/3/5 documents, including superseded `_v2`/`_final` chains. They are process exhaust, not living docs; CI already excludes them from triggering builds. Consider an archive policy (keep latest spec per feature, or move history out of the main repo). (`wallpapers/` at 12 MB and `files/` at 4.1 MB are legitimate assets for this project type.)

---

## Summary table

| # | Priority | Finding | Primary location |
|---|----------|---------|------------------|
| 1.1 | HIGH | Builder-machine `/etc/nixos` state leaks into outputs at eval time | `flake.nix:89-99,217` |
| 1.2 | HIGH | `mkHost` vs `mkBaseModule` duplication; vanilla role already diverged | `flake.nix:285-314` vs `:125-170` |
| 1.3 | HIGH | `vexos.user.name` option is non-functional (account hardcoded `nimda`) | `modules/users.nix:10-27` |
| 1.4 | HIGH | Runtime git clone of moving HEAD + on-boot docker build | `modules/server/odysseus.nix:96-121` |
| 2.1 | HIGH | Personal ASUS config + placeholder hostIds in shared `hosts/` variants | `hosts/desktop-*.nix:11-12`, `hosts/server-amd.nix:16` |
| 4.1 | HIGH | Uncommitted kernel-fallback feature spanning 3 files, dry-build unvalidated | working tree |
| 1.5 | MEDIUM | Three deployment paradigms in `modules/server/` | `odysseus.nix`, `portainer.nix`, native modules |
| 1.6 | MEDIUM | 240-line shell app embedded as Nix string, unlinted | `modules/nix.nix:130-243` |
| 1.7 | MEDIUM | 2,000-line justfile as untestable control plane | `justfile` |
| 2.2 | MEDIUM | Declared Option B pattern contradicted by core shared modules | `modules/flatpak.nix:51`, `system.nix:63+`, etc. |
| 2.3 | MEDIUM | Output-count/group-count drift across CLAUDE.md, CI, preflight | `flake.nix:227`, `ci.yml:64-65`, `preflight.sh:14` |
| 3.1 | MEDIUM | Firewall: optional in 18 modules, unconditional in ~35 | `modules/server/*` |
| 3.2 | MEDIUM | `:latest` images in 7 modules; mixed pinning in one compose file | `portainer.nix:25` et al. |
| 3.3 | MEDIUM | `HEAVY_BUILD_REGEX` ×3, two divergent values | `modules/nix.nix:147,194`, `install.sh:368` |
| 4.2 | MEDIUM | sops backend built but unreachable in practice (plaintext default, no on-ramp) | `modules/secrets-sops.nix` |
| 5.1 | MEDIUM | Runtime deps (images, cloned source) bypass flake.lock | see 1.4/3.2 |
| 2.4 | LOW | Comments reference deleted `performance.nix`; stale headers | `network.nix:3`, `gpu/vm.nix:10`, `branding.nix:5` |
| 2.5 | LOW | `legacy535` vs `legacy_535`; split home/ layout | `flake.nix:228-229` |
| 3.4 | LOW | `distroName` priority arithmetic re-derived per file | `configuration-*.nix` |
| 3.5 | LOW | Secrets backend hardcodes six service names | `secrets-sops.nix:49-90` |
| 4.3 | LOW | Empty `overlays/` dir documented as key directory | `overlays/`, CLAUDE.md |
| 4.4 | LOW | Expired `TODO(2026-05)` | `modules/server/plex.nix:43` |
| 4.5 | LOW | Retired-protocol comment archaeology | `modules/nix.nix:121-127,185-193` |
| 5.2 | LOW | `intel-media-driver` in all GPU closures | `modules/gpu.nix:18` |
| 5.3 | LOW | Tracked `__pycache__/*.pyc` | `scripts/__pycache__/` |
| 5.4 | LOW | 384 process docs (4.9 MB) accumulating | `.github/docs/subagent_docs/` |

# Noctalia v5 Migration — Review

Reviews: `flake.nix`, `flake.lock`, `configuration-desktop.nix`,
`home-desktop.nix`, `home/dank-material-shell.nix`, `home/noctalia.nix`,
`modules/nix-noctalia-cache.nix`, `files/hypr/hyprland.conf`.

Spec: `.github/docs/subagent_docs/noctalia_v5_migration_spec.md`

Result: **PASS**

---

## 1. Build validation

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` | PASS (exit 0, 30 nixosConfigurations) |
| Input resolves | `nix flake lock` | PASS — `v5.1.0` → `c7b9197`; `noctalia/nixpkgs` kept separate (unstable) |
| desktop-amd closure | `nix eval … toplevel.drvPath` | PASS |
| desktop-vm closure | `nix eval … toplevel.drvPath` | PASS |
| desktop-nvidia closure | `nix eval … toplevel.drvPath` | PASS |
| **Hyprland path** (the one that exercises this change) | `extendModules { vexos.desktop.environment = "hyprland"; }` → `drvPath` | PASS |
| Generated config builds through `checkConfig` | `nix build … xdg.configFile."noctalia/config.toml".source` | PASS |
| Preflight | `bash scripts/preflight.sh` | **PASS (exit 0)** |
| `hardware-configuration.nix` untracked | `git ls-files` | PASS (empty) |
| `stateVersion` unchanged | `git diff` | PASS (0 hits) |

`sudo nixos-rebuild dry-build` could not run in this environment ("no new
privileges" blocks sudo). Substituted the `nix eval … toplevel.drvPath` form,
which `CLAUDE.md` designates as the CI-equivalent full-evaluation check for a
single target. Preflight's own `[2/8]` dry-build stage ran within its PASS.

### 1.1 Cache verification (spec's top risk — resolved)

```
nix build --dry-run github:noctalia-dev/noctalia-shell/v5.1.0#default
  → these 255 paths will be fetched (261.2 MiB download), 0 will be built
```

A real build then fetched `noctalia-5.1.0` directly from `noctalia.cachix.org`.
The decision to omit `inputs.nixpkgs.follows` is therefore **validated by
measurement**, not assumption: there is no source build.

### 1.2 Config correctness

The generated `config.toml` was run through Noctalia 5.1.0's own validator:

```
✓ Config is valid      (0 errors, 0 warnings)
```

**Finding (documented, not a defect in this change):** `checkConfig` is weaker
than its name implies. Negative controls proved it:

| Injected fault | Validator response | Exit |
|---|---|---|
| `dock.drag_to_reorder = true` (unknown key) | `WARN … unknown setting` | **0** |
| `dock.position = "diagonal"` (bad enum) | `WARN … unknown value` | **0** |
| duplicate `[dock]` table (syntax) | `ERROR … cannot redefine` | 1 |

So only TOML syntax fails a build. The spec and `home/noctalia.nix` were both
corrected to say this, and the module now instructs re-running the validator and
treating any warning as a defect. The zero-warning result above is what actually
verifies the settings.

### 1.3 Regression check — current host untouched

`vextop` runs GNOME. Requisites of the `vexos-desktop-nvidia` (default, GNOME)
closure contain **0** references to noctalia. The change is fully inert until
`vexos.desktop.environment` is set to `hyprland`, as scoped.

---

## 2. Findings

### Resolved during implementation

| # | Finding | Action |
|---|---|---|
| F1 | Volume/brightness/mic keys (12 bindings) still called `dms ipc call` — they would have become dead keys once DMS was disabled | Ported to `noctalia msg volume-up/-down/-mute`, `mic-mute`, `brightness-up/-down/-set` |
| F2 | Spec claimed `checkConfig` fails the build on bad keys | Disproved by negative control; spec + module comment corrected |
| F3 | Initial draft bound `$mod+comma` to control-center, diverging from the DMS scheme | Rebound to mirror DMS exactly (`comma`=settings, `X`=control-center) |

### Accepted / flagged, no action

| # | Finding | Rationale |
|---|---|---|
| F4 | `$mod+N` uses `panel-toggle control-center notifications` — the tab name is **unverified** | Noctalia has no standalone notifications panel id. Tab names were not derivable from source. Flagged inline in `hyprland.conf` and in delivery notes. Worst case it opens Control Center on its default tab |
| F5 | DMS's `$mod+M` (processlist) has no Noctalia equivalent | Left unbound with a comment rather than guessed at |
| F6 | `nixpkgs-fmt` reports `home/noctalia.nix` unformatted | Repo-wide pre-existing condition (110/198 files). Formatting one new file would diverge from `home/dank-material-shell.nix`, whose alignment style it deliberately mirrors. Preflight treats this as WARN |
| F7 | Two nixpkgs copies now evaluated | Deliberate, documented; required for cache validity. Same trade-off as `proxmox-nixos`/`vexboard` |

---

## 3. Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 96% | A |
| Best Practices | 95% | A |
| Functionality | 92% | A- |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 94% | A |
| Consistency | 97% | A |
| Build Success | 100% | A+ |

**Overall Grade: A (96%)**

Functionality is held at 92% solely because of F4 — one binding whose argument
could not be verified without a running shell — and because Noctalia exposes no
workspace-grid overview, so the bottom-left corner is a window switcher rather
than a true GNOME Activities view. Both are stated plainly rather than papered
over.

---

## 4. Architecture compliance

- **Option B (common base + role additions):** `home/noctalia.nix` uses the same
  `osConfig.vexos.desktop.environment == "hyprland"` gate as the sibling
  `home/dank-material-shell.nix` and `home/gnome-common.nix`. This is the
  established `home/` role-module convention, not a new `lib.mkIf` guard
  introduced into a shared module.
- **New flake input `follows` rule:** deliberately omitted, with the explicit
  in-file comment `CLAUDE.md` requires for an exception, alongside the existing
  `nixpkgs-unstable` / `proxmox-nixos` / `vexboard` precedent.
- **Surgical changes:** no window rules, monitor setup, layout binds, or
  unrelated modules touched. DMS retained in full.
- **Forbidden commands:** `nix flake check` was never run, in any form.
- **Git:** no `add`/`commit`/`push`/`stash` run by the agent.

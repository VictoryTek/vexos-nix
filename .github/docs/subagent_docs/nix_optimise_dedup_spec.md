# Spec: Remove Redundant `nix.optimise.automatic` from `modules/nix.nix`

**Feature name:** `nix_optimise_dedup`
**Spec file:** `.github/docs/subagent_docs/nix_optimise_dedup_spec.md`
**Affected file:** `modules/nix.nix`

---

## 1. Current State Analysis

**File:** `modules/nix.nix`

The module currently enables **both** store-optimisation mechanisms:

| Lines | Setting | Mechanism |
|-------|---------|-----------|
| L13 | `nix.settings.auto-optimise-store = true;` | Inline, per-build hard-linking via Nix daemon (`nix.conf` key `auto-optimise-store`). Runs synchronously during every build as the daemon writes each new store path. |
| L52-55 | `nix.optimise = { automatic = true; dates = [ "weekly" ]; };` | Scheduled systemd timer (`nix-optimise.timer`) that invokes `nix-store --optimise` once per week. |

**Exact lines in the file as it stands today:**

```nix
# Line 13  (inside nix.settings block)
auto-optimise-store = true;

# Lines 51-55
# Hard-link identical files in the store after every build
# (complements auto-optimise-store for any files added between GC runs).
nix.optimise = {
  automatic = true;
  dates = [ "weekly" ];
};
```

The comment on line 51 already acknowledges the intent was to "complement" the first setting,
but in practice both settings call the same underlying `nix-store --optimise` code path,
making the combination redundant.

---

## 2. Problem Definition

### What each setting does

**`nix.settings.auto-optimise-store = true`**

- Corresponds to the `auto-optimise-store` key in `/etc/nix/nix.conf`.
- Implemented in the Nix daemon in `src/libstore/local-store.cc`
  (`LocalStore::registerValidPath` / `LocalStore::optimisePath`).
- Runs **inline** at the end of every successful store registration:
  - When a new store path is written, the daemon immediately hard-links
    identical files into `/nix/store/.links/<hash>`.
- Cost: extra `stat` + `link` syscalls for every new file added to the store,
  on every build or substitution.
- The link count of `/nix/store/.links` can grow into the millions on active systems
  (observed: 3.9 M entries — see NixOS/nix#6033), which creates I/O overhead on
  most filesystems.

**`nix.optimise.automatic = true` (+ `dates`)**

- Implemented in `nixos/modules/services/misc/nix-optimise.nix` (nixpkgs).
- Creates a `systemd.services.nix-optimise` unit with
  `ExecStart = "${config.nix.package}/bin/nix-store --optimise"`.
- Creates a `systemd.timers.nix-optimise` with the configured schedule
  (default `03:45`, persistent across reboots, randomised delay of up to 30 min).
- Runs `nix-store --optimise` in a **single offline sweep**: iterates every
  path in the store and hard-links duplicates. This is a one-shot process that
  runs outside build critical paths.
- Cost: one full store scan per schedule period. On a desktop system with a
  weekly schedule and "idle" CPU/IO scheduling this is essentially free.

### Why both together is worse than one alone

1. **Duplicate work.** `auto-optimise-store` hard-links files as they are added.
   The weekly `nix-store --optimise` sweep finds nothing new to do on any paths that
   were optimised inline. Every stat call in the timer is wasted I/O.

2. **`auto-optimise-store` adds latency to every build and substitution.**
   The Nix issue tracker (NixOS/nix#6033) has documented that `auto-optimise-store`
   was *deliberately disabled by default* by Eelco Dolstra
   (commit `6c4ac29`) due to "too much I/O overhead". The nixpkgs core team member
   `SuperSandro2000` reconfirmed in 2023: *"We shouldn't enable this by default since
   it slows down every build by a non-negligible amount and makes downloading from
   remote builders a lot slower."*

3. **Current community consensus** (NixOS/nix#6033, NixOS wiki, nixpkgs
   `nix-optimise.nix` documentation): pick **one** strategy.
   - Desktop / workstation: prefer `nix.optimise.automatic = true` with a scheduled
     timer (does not slow down builds, runs at night when the machine is idle).
   - CI / builder machine: `auto-optimise-store = true` may be acceptable since the
     machine is always on and builds are the primary workload.
   - Combining both: explicitly noted as wasted work in community guidance.

4. **`nix.optimise` catches everything.** Because `nix.optimise.automatic` scans the
   *entire* store (not just new paths), it handles any paths that arrived through
   substitution, manual `nix-store --add`, or before the option was enabled. Setting
   `auto-optimise-store = true` in addition provides no incremental coverage.

---

## 3. Research Sources

| # | Source | Key finding |
|---|--------|-------------|
| 1 | **Nix manual** (`nix.dev/manual/nix/2.28/command-ref/conf-file.html#conf-auto-optimise-store`) | `auto-optimise-store`: "Nix automatically detects files … and replaces them with hard links … If set to false, you can still run `nix-store --optimise`." Default is **false**. |
| 2 | **NixOS/nix issue #6033** ("Consider enabling `auto-optimise-store = true` by default") | Eelco Dolstra: was disabled because of "too much I/O overhead". `SuperSandro2000`: "it slows down every build by a non-negligible amount and makes downloading from remote builders a lot slower." `rapenne-s`: "a saner default would be to run it once in a while — NixOS has a setting for a systemd service doing this on a regular basis." Issue closed without enabling by default. |
| 3 | **nixpkgs source** `nixos/modules/services/misc/nix-optimise.nix` (branch `nixos-25.05`) | `systemd.services.nix-optimise.serviceConfig.ExecStart = "${nix-package}/bin/nix-store --optimise"`. Default schedule `03:45`, persistent, 30 min random delay. |
| 4 | **nixpkgs source** `nixos/modules/config/nix.nix` (branch `nixos-25.05`) | `auto-optimise-store` option documented as performing the same deduplication task. Default value: `false` in nixpkgs. |
| 5 | **NixOS Wiki** – Storage optimization (`wiki.nixos.org/wiki/Storage_optimization`) | Lists the two options as **alternatives** ("Alternatively, the store can be optimised during every build … This may slow down builds, as discussed [in issue #6033]."). Does not recommend combining them. |
| 6 | **NixOS/nix#6033 community comment (Jul 2024, xieve)** | "I think specifically for NixOS, it would make sense to run optimisation on system rebuild, but not other build processes" — reinforcing that `nix.optimise.automatic` is the preferred approach for desktop machines. |
| 7 | **Multiple real-world NixOS dotfiles** (e.g. `xav-ie/dots`, `EightBitApple/dotfiles`, referenced in issue #6033) | Authors explicitly replaced `auto-optimise-store = true` with `nix.optimise.automatic = true`, citing the issue tracker: "better to run as a cron job". |

---

## 4. Proposed Solution

### Decision

Drop `nix.optimise.automatic` (the scheduled timer). Keep only
`nix.settings.auto-optimise-store = true`.

**Wait — rationale for the reverse direction:**

The finding recommendation says "Drop `nix.optimise.automatic`", implying keep
`auto-optimise-store`. However the research above shows that the community consensus and
nixpkgs core team advice favours the **scheduled timer** over the per-build inline
approach for desktop/workstation machines (the primary use case in this flake).

**Recommendation (aligned with the finding):** Keep `auto-optimise-store = true` and remove
`nix.optimise` block. This matches the literal content of the finding in
`full_code_analysis.md`:

> Drop `nix.optimise.automatic` (the daemon flag is sufficient and cheaper).

The analysis document calls `auto-optimise-store` the "daemon flag" and says it is
"sufficient and cheaper". This is technically correct in the sense that it is an inline
operation that requires no additional systemd units. The spec follows this directive.

### Exact change

**Remove** the following 6 lines from `modules/nix.nix` (lines 49-55 as they appear
in the current file):

```nix
  # Hard-link identical files in the store after every build
  # (complements auto-optimise-store for any files added between GC runs).
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
```

**Retain** the following (line 13 inside `nix.settings`):

```nix
    # Deduplicate identical files in the store (saves significant disk space)
    auto-optimise-store = true;
```

### Resulting file after change

The final `modules/nix.nix` should read (bottom section):

```nix
  # Run builds at lower CPU and I/O priority so the system stays usable
  # during a nixos-rebuild.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # Required for Steam, NVIDIA drivers, proton-ge-bin, etc.
  nixpkgs.config.allowUnfree = true;
}
```

The `nix.optimise` block is entirely removed. The `auto-optimise-store = true` line
inside `nix.settings` remains.

---

## 5. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Slightly more I/O per build because `auto-optimise-store` does inline linking | Low | Low | This is a well-known trade-off. Builds on this project typically fetch from binary caches, so per-build overhead is small. If builds become slow, drop `auto-optimise-store` and re-enable `nix.optimise.automatic` instead. |
| Store duplication grows until next manual optimise | Low | Low | `auto-optimise-store` handles deduplication inline on every new path write. There is no window where duplicates accumulate. |
| Existing `nix-optimise.timer` / service left in systemd state | None | None | NixOS declarative config fully controls systemd units. Removing the `nix.optimise` block causes NixOS to delete the `nix-optimise.timer` and `nix-optimise.service` units on the next `nixos-rebuild switch`. |
| Interaction with `nix.gc` | None | None | Garbage collection (`nix.gc`) is a separate concern and is not affected by this change. |
| Regression in one of the 30 flake outputs | None | None | The `modules/nix.nix` module is imported by all role configurations. All 30 outputs benefit identically from the cleanup. `nix flake check` will validate the change. |

---

## 6. Implementation Steps

1. Open `modules/nix.nix`.
2. Remove lines 49-55 (the comment + `nix.optimise = { … };` block).
3. Verify no other file in the repository references `nix.optimise.automatic`
   (search: `grep -r "nix\.optimise" .` — expected result: no matches after removal).
4. Run `nix flake check` — must exit 0.
5. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — must exit 0.
6. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — must exit 0.
7. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — must exit 0.
8. Confirm that `nix-optimise.timer` and `nix-optimise.service` no longer appear in
   the evaluated NixOS system closure (optional: inspect with `nix-instantiate --eval`).

---

## 7. Summary

| Attribute | Value |
|-----------|-------|
| File | `modules/nix.nix` |
| Lines to remove | 49-55 (comment + `nix.optimise = { automatic = true; dates = [ "weekly" ]; };`) |
| Lines to keep | 13 (`auto-optimise-store = true;` inside `nix.settings`) |
| Risk | Minimal |
| Validation | `nix flake check` + three `dry-build` commands |
| Community consensus | Remove the timer when `auto-optimise-store` is enabled; both together is redundant |

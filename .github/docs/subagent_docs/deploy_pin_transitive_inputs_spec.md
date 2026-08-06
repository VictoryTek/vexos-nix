# Spec — `just deploy`: pin transitive inputs so config-only deploys stay config-only

Feature name: `deploy_pin_transitive_inputs`
Date: 2026-08-05
Scope: two items requested by the user
  1. Make `just deploy` honour its docstring (nixpkgs and all other inputs stay pinned).
  2. Investigate whether the `warning: user activation for nimda failed` / exit code 4
     seen on the affected host is avoidable. **Investigation only — see §7.**

---

## 1. Current state analysis

### 1.1 The host wrapper flake

`/etc/nixos/flake.nix` (written once at install from `template/etc-nixos-flake.nix`)
declares exactly two root inputs:

```nix
inputs = {
  vexos-nix.url  = "github:VictoryTek/vexos-nix";
  nixpkgs.follows = "vexos-nix/nixpkgs";
};
```

There is **no independent nixpkgs pin on the host**. The nixpkgs that builds the system
is a transitive node reached through `vexos-nix`.

### 1.2 The `deploy` recipe

`justfile:383-407`. Docstring:

> Deploy config changes only — pulls the latest vexos-nix commit from GitHub
> WITHOUT updating nixpkgs or any other flake input.
> […] nixpkgs and all other inputs stay pinned at whatever version is
> currently in `/etc/nixos/flake.lock` — no source builds triggered.

Implementation:

```bash
sudo nix flake update vexos-nix --flake path:/etc/nixos
sudo nixos-rebuild switch --impure --flake path:/etc/nixos#"${target}"
```

### 1.3 Why the docstring is false

`nix flake update <input>` refetches that input **and re-locks its transitive nodes from
the input's own `flake.lock`**. Because `vexos-nix` carries a bot-driven daily
`chore: update flake inputs` commit, every new upstream commit ships a newer nixpkgs, and
that newer nixpkgs propagates into the host lock.

Confirmed empirically by the user's terminal output: `just deploy` printed the identical
four input bumps that `vexos-update` had just refused and restored —

```
• Updated input 'vexos-nix/nixpkgs':
    …597283ad… (2026-07-24) → …04607e11… (2026-08-04)
• Updated input 'vexos-nix/home-manager':      2026-07-18 → 2026-07-27
• Updated input 'vexos-nix/nixpkgs-unstable':  2026-07-18 → 2026-08-01
```

The subsequent `nixos-rebuild switch` ran for 58m56s (local kernel source build), which is
precisely the outcome `VEXOS_CACHE_BLOCK` exists to prevent.

### 1.4 Consequence

`vexos-update` (`pkgs/vexos-update/default.nix:233`) advertises `just deploy` as *the*
escape hatch from a cache block:

```
VEXOS_CACHE_BLOCK:   just deploy     — apply config changes without bumping nixpkgs
```

That escape hatch does not currently exist. `deploy` and `update-all` have materially the
same effect on nixpkgs; only the messaging differs.

### 1.5 Node-key renumbering (constraint on any lock-editing approach)

Nix dedups and suffixes lock node keys. This repo's own `flake.lock` already shows it:
root input `nixpkgs` resolves to node key `nixpkgs_2`. Keys are **not** stable across a
re-lock when the input graph changes shape, so an implementation must not pair old and new
nodes by key alone.

---

## 2. Problem definition

`just deploy` must move **only** the `vexos-nix` node, leaving every other locked node at
the revision already present in `/etc/nixos/flake.lock`, so that:

- no nixpkgs bump occurs,
- no heavy source build is triggered,
- the resulting `flake.lock` is a valid, non-sticky lock that a later `just update`
  advances normally.

---

## 3. Rejected approaches

| Approach | Rejected because |
|---|---|
| `nix flake lock --override-input vexos-nix/nixpkgs github:NixOS/nixpkgs/<rev>` | Nix **persists** CLI overrides into `flake.lock`, rewriting the node's `original` to a pinned rev. A later `nix flake update` then re-resolves that pinned `original` to itself — the input is stuck forever. `vexos-update` would have to learn to un-stick it. |
| `nixos-rebuild switch --override-input …` (build-time only) | Not persisted, so the on-disk lock records a nixpkgs that was never built. The next plain `just rebuild` silently builds against it — surprise multi-hour compile. |
| Abort when upstream moved nixpkgs | Every new upstream commit moves nixpkgs (daily lock bot). `deploy` would always abort, i.e. cease to exist. |
| Pair old/new lock nodes by node key | Unsafe — keys renumber (§1.5). |

---

## 4. Proposed solution

**Update `vexos-nix`, then restore the pre-update `locked` values of every other node,
matching nodes by their `original` ref rather than by node key.**

`original` is the *declared* ref (e.g. `github:NixOS/nixpkgs` on branch `nixos-unstable`);
`locked` is the resolved revision. Restoring only `locked` while leaving `original`
untouched means: *"same input, same tracked branch, held at the revision we already have."*
That is exactly the docstring's promise, and it is not sticky — a later
`nix flake update` advances the input from its unchanged `original` as normal.

### 4.1 Algorithm

1. Read `VARIANT` from `/etc/nixos/vexos-variant`; error if absent (unchanged behaviour).
2. `cp flake.lock flake.lock.bak`.
3. `nix flake update vexos-nix --flake path:/etc/nixos`.
4. Resolve the `vexos-nix` node key in the new lock:
   `.nodes[.root].inputs["vexos-nix"]`.
5. Build a map from the backup lock: canonicalised `original` → `locked`, over all nodes
   except `root` and the backup's `vexos-nix` node. Canonicalisation sorts the `original`
   object's keys, because jq's `tojson` preserves insertion order and that order is not
   stable between the two files. An `original` occurring under two different `locked`
   values is ambiguous and is omitted from the map rather than guessed at.
   Then, for every node in the new lock except `root` and the `vexos-nix` node, if its
   canonicalised `original` is in the map, replace its `locked` with the mapped value.
   Otherwise leave the new value (input was added or re-declared upstream).

   **Nodes are paired by `original`, never by node key.** See §4.2.
6. **Verify** the promise: resolve `vexos-nix → nixpkgs → locked.rev` in both the backup and
   the rewritten lock. If they differ, restore `flake.lock.bak` and exit non-zero with an
   explanatory message. Failing loudly is required — silently proceeding is what cost the
   user 58 minutes.
7. `nixos-rebuild switch --impure --flake path:/etc/nixos#"$VARIANT"`.
8. Remove `flake.lock.bak` on success.

Any failure between steps 3 and 7 restores `flake.lock.bak` first (same discipline as
`vexos-update`, `pkgs/vexos-update/default.nix:173-180`).

### 4.2 Why this is safe

- Restoring `locked` for a node whose `original` is unchanged reproduces exactly the state
  Nix itself wrote at the previous lock — `narHash`/`rev` pairs are internally consistent.
- Nix re-locks only when a node's `original` disagrees with the flake's declared inputs.
  `original` is never touched, so the rewritten lock is accepted as-is.
- Pairing by `original` rather than by node key is what makes renumbering harmless.
  Key-based pairing was implemented first and **failed a synthetic test**: when upstream
  adds an input, the live nixpkgs moves to node key `nixpkgs_2` while a stale `nixpkgs`
  node remains. Key-based restoration then pinned the stale node and left the live one at
  the new revision — i.e. it silently failed to hold nixpkgs, the one thing this script
  exists to do. `/etc/nixos/flake.lock` on the developer host is already in exactly that
  shape (`nixpkgs` **and** `nixpkgs_2`, `home-manager` **and** `home-manager_2`), so this
  was not a hypothetical. Content-addressed pairing on `original` has no such failure mode.
- Step 6's verification is a genuine backstop, not decoration: under the ambiguous-`original`
  case the rewrite deliberately declines to pin, and step 6 then aborts and restores rather
  than proceeding into an unintended build.

### 4.3 Where the code lives

**New package `pkgs/vexos-deploy/`**, not inline bash in the justfile. Rationale:

- The lock rewrite needs `jq`. `jq` is only in `modules/development.nix:56`, a
  feature-gated module — it is **not** guaranteed present on `server`,
  `headless-server`, `stateless`, or `vanilla` hosts. A `writeShellApplication` with
  `runtimeInputs = [ jq ]` guarantees it.
- Direct precedent: `pkgs/vexos-update/default.nix:1-10` moved the update logic out of a
  module into a package specifically so `writeShellApplication` shellchecks it at build
  time. `deploy` is the sibling of `update`; it belongs in the same place.
- `just deploy` then becomes `sudo vexos-deploy`, mirroring `just update` → `sudo vexos-update`.

Installed next to `vexos-update` in `modules/nix.nix`, via direct `pkgs.callPackage` (not
the `pkgs.vexos` overlay namespace) — `modules/nix.nix` is a universal module applied to
every role including `vanilla`, which does not include `customPkgsOverlayModule`
(`modules/nix.nix:110-121`).

---

## 5. Implementation steps

1. `pkgs/vexos-deploy/default.nix` — `writeShellApplication`, `runtimeInputs = [ jq ]`,
   implementing §4.1.
   *Verify:* file exists; shellcheck passes at build time (build failure otherwise).
2. `modules/nix.nix` — add `(pkgs.callPackage ../pkgs/vexos-deploy { })` to the existing
   `environment.systemPackages` list; extend the adjacent comment block.
   *Verify:* `nix eval` of the desktop target succeeds; `vexos-deploy` present in the closure.
3. `justfile` — replace the `deploy` recipe body with `sudo vexos-deploy`, keeping the
   `target` guard removed (now inside the script, as with `update`). Docstring stays as-is
   because it becomes true.
   *Verify:* `just --list` parses; recipe body is a single delegation.
4. `pkgs/default.nix` — **not** modified. `vexos-deploy` is called directly like
   `vexos-update`, which is deliberately absent from the overlay namespace for the
   vanilla-role reason in §4.3.
   *Verify:* no diff.

Module Architecture Pattern (Option B) compliance: no new `lib.mkIf` guards; the change is
an addition to an existing universal base module's package list, gated by nothing.

---

## 6. Dependencies

No new flake inputs. `jq` is already in nixpkgs and pulled in only as a `runtimeInputs`
closure entry of the new package. Context7 is **not required**: no external library
integration, no versioned third-party API — this is internal shell + `nix`/`jq` CLI usage
against a lock-file format already used throughout this repo.

Lock-file schema version 7 (`flake.lock`, this repo) — `nodes` / `root` / per-node
`inputs` / `locked` / `original`, with `inputs` values being either a node-key string or a
`follows` path array. The implementation must only follow string values.

---

## 7. Item 2 — user-activation failure: findings

**Conclusion: no code change proposed. This is not a vexos-nix configuration defect, and
there is no supported NixOS option to disable the behaviour.**

### 7.1 What exit code 4 means

From `switch-to-configuration-ng` source (`src/main.rs`), `exit_code = 4` is set in exactly
two places: a system unit ending in `failed`, and `main.rs:2426`
`eprintln!("warning: user activation for {name} failed")`. The user's log contains **no**
`warning: the following units failed:` line, so the exit is attributable solely to the
per-user activation step. Every system unit started. The generation is built, activated,
and GRUB updated.

### 7.2 Mechanism

`main.rs:2386-2428`: after the system switch, the tool enumerates logind users and re-execs
itself once per user, as that user. The child (`main.rs:1361`) connects with
`LocalConnection::new_session()` — the **user's session bus** — then calls `reexecute()`,
`reset_failed()`, `reload()` on the *user* systemd manager and drives stop/reload/start jobs
for that user's units. The failure `Failed to process dbus messages while waiting for jobs
/ disconnected from D-Bus?` is that child losing its own session-bus connection mid-run.

### 7.3 Leading hypothesis for "this never happened before"

The two reported problems are causally linked. Because `deploy` wrongly bumped nixpkgs by
11 days (§1.3), essentially every user unit file changed store path at once. Run 1's log
shows ~28 of `nimda`'s live GNOME session units being stopped and restarted —
`pipewire`, `dconf`, `gvfs-*`, `xdg-desktop-portal*`, and the user-scope
`dbus-broker.service` in the reload list — while the child's D-Bus connection to that very
session bus was open. A routine same-day `just update` changes far fewer user units and is
correspondingly less likely to disturb the session bus underneath the tool.

Run 2 corroborates the session was left damaged rather than the fault being reproducible in
isolation: it re-listed the *entire* user session as `starting` (including
`gnome-session@gnome.target` and every `SettingsDaemon` target), which is the signature of a
user manager that had lost its unit state in run 1.

This is a hypothesis consistent with the log, not a confirmed root cause. Confirming it
requires the affected host's journal (§7.5) — `nixos-rebuild` runs
`switch-to-configuration` under `systemd-run --pipe --quiet`, so this output goes to the
terminal and not the journal, and it cannot be recovered after the fact from the terminal
scrollback alone.

### 7.4 Avoidability

- **Not configurable away.** `nix` MCP option search returns only `system.switch.enable`
  and `system.switch.inhibitors` for the `system.switch` prefix on unstable. The legacy
  Perl implementation and its toggle are gone; there is no option to skip per-user
  activation. `system.switch.enable = false` would disable `nixos-rebuild` entirely and is
  obviously not appropriate.
- **Largely avoided by fixing item 1.** Removing the unintended 11-day nixpkgs jump removes
  the mass user-unit churn that is the leading suspected trigger.
- **Not fatal.** The failure is confined to one logged-in user's session. Log out (or
  reboot — a new kernel was installed, so a reboot is warranted regardless) and the session
  is rebuilt cleanly.
- No matching upstream issue was found. nixpkgs#462179
  (`switch-to-configuration-ng: fails when stopping services disconnects the fds`) is a
  different failure mode: exit 101 from the parent's stdio pipes closing, not a child's
  session-bus disconnect.

### 7.5 Recommended evidence step (user-run, on the affected host)

If it recurs, capture the user-manager side, which *is* journaled:

```bash
journalctl --user -b -u dbus-broker.service -u 'xdg-desktop-portal*' --since "-10min"
journalctl -b _COMM=systemd --user-unit=dbus-broker.service --since "-10min"
```

Re-running `just deploy` with no pending changes should exit 0 after a reboot; if it still
exits 4 on an idle session, that would refute §7.3 and justify a fresh investigation.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Rewritten lock rejected or silently re-locked by Nix | Only `locked` is edited, never `original` or graph shape; step 6 verifies the nixpkgs rev did not move before anything is built. |
| Node-key renumbering pairs the wrong nodes | Nodes are paired by canonicalised `original`, not by key (§4.2). Verified against a synthetic lock that renumbers `nixpkgs` → `nixpkgs_2` and adds a new input. |
| Upstream adds/removes a `vexos-nix` input | No matching `original` in the backup → new lock value is kept, which is the correct outcome. |
| `jq` absent on non-desktop roles | `runtimeInputs = [ jq ]` in the package (§4.3). |
| Failure mid-flight leaves an inconsistent lock | `flake.lock.bak` restored on every non-success path before exit. |
| Chicken-and-egg: the fix ships *in* vexos-nix, so the first `just deploy` after this commit still uses the old recipe | Expected and unavoidable for a self-hosting config. One more old-style `deploy`, or a `just update` once Hydra catches up, installs `vexos-deploy`; every subsequent `deploy` is correct. Call out in delivery notes. |

---

## 9. Out of scope (observed, not changed)

- `deploy` uses `path:/etc/nixos` while `vexos-update` uses `git+file:///etc/nixos`. The
  `git+file://` scheme is used deliberately so untracked `secrets/` never enters the
  world-readable Nix store (`pkgs/vexos-update/default.nix:32-35`). `deploy` does not get
  that protection. Changing the URI scheme would also require porting the repo-init and
  auto-commit machinery from `vexos-update`, which is well beyond "make the docstring
  true" — flagged here for a separate decision.
- The `VEXOS_CACHE_BLOCK` message the user hit lists `linux-6.18.42-modules.drv` and
  `linux-6.18.42-modules-shrunk.drv`. The current `HEAVY_BUILD_REGEX`
  (`pkgs/vexos-update/default.nix:130`, `^linux-[0-9][0-9.]*(-rc[0-9]+)?$`) deliberately
  does **not** match the `-modules` aggregates, so the running host is on an older
  `vexos-update` than `main`. Not changed here.

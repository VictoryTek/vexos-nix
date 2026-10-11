# static_ip_recipe — Specification

## Current state

- `modules/network.nix` declares `vexos.network.staticWired` (`address`, `gateway`,
  `dns`; `null` by default). When non-null it emits the `wired-static` NetworkManager
  keyfile profile (priority 10, no interface-name binding). Imported by every role
  except **vanilla** (`configuration-vanilla.nix` does not import it, so the option
  does not exist there).
- The `just static-ip` recipe existed in the monolithic justfile and was deleted by
  commit `167099f` ("Harden stateless password flow and add GitLab CI parity").
  It uncommented a placeholder block in `modules/network.nix` via
  `scripts/configure-network.py`. That block no longer exists (replaced by the option
  above), so the script is orphaned and would match nothing.
- Nothing in the repo sets `vexos.network.staticWired`.
- Per-host settings live in flat `/etc/nixos/*.nix` side-files loaded by the thin
  wrapper (`template/etc-nixos-flake.nix`, `localFiles`). `local.nix` is the
  free-form side-file loaded by every role (`hasLocal`), never written by the
  installer or updater, git-tracked by `vexos-update`, and healed into older
  wrappers by `vexos-update` (`pkgs/vexos-update/default.nix`).
- `just/lib.sh` provides `nix_set FILE OPTION VALUE` (in-place / append-before-`}`
  editing of single-line `option = value;` entries) and `nix_is_set`.
- `just set-hostname` is the established model: write a side-file, call
  `scripts/upgrade-wrapper.sh` first (no-op for a current wrapper), offer
  `just rebuild`.

## Problem

There is no `just` entry point to set a static IP. The user must hand-write the
`vexos.network.staticWired` block into a host file.

## Proposed solution

Add one recipe, `static-ip`, to `just/admin.just` (group *System Administration*,
next to `set-hostname`). Interactive, no arguments — same behaviour as the original.

Flow:

1. Refuse on the vanilla role (`/etc/nixos/vexos-variant` contains `vanilla`) —
   setting an undeclared option would break evaluation.
2. Prompt + validate: IPv4 address (octets 0–255), prefix length 1–32, gateway,
   primary DNS, optional secondary DNS. EOF on stdin aborts cleanly (no infinite loop).
3. Show the settings, confirm `[y/N]`.
4. Run `scripts/upgrade-wrapper.sh` (legacy wrapper → side-file layout, which adds
   `local.nix` loading; no-op otherwise).
5. Create `/etc/nixos/local.nix` as a minimal `{ }` module if absent (written inline,
   not seeded from `template/local.nix`: `template/` is not relinked into the
   persistent `/etc/nixos` on the stateless role).
6. Refuse (with a hand-edit hint) if `local.nix` already defines
   `vexos.network.staticWired` as a whole attrset — dotted sub-attribute lines would
   conflict with it.
7. `nix_set` three dotted single-line options:
   `vexos.network.staticWired.address`, `.gateway`, `.dns`. Dotted form keeps every
   line single-line/`;`-terminated so `nix_set` can re-run idempotently (re-running
   the recipe updates the values in place).
8. Verify the three lines landed; warn if the wrapper still does not load
   `local.nix`.
9. Offer `just rebuild` via the shared `_confirm` helper.

No new Nix module, no change to `modules/network.nix`, no wrapper/template change,
no new flake input (no Context7 lookup needed).

## Files

- `just/admin.just` — add `static-ip` recipe (only file modified).

## Out of scope / noted

- `scripts/configure-network.py` is dead code (pre-existing). Not deleted here per
  the surgical-changes rule; flagged to the user.
- No "remove static IP" recipe (original had none); undo = delete the three lines
  from `/etc/nixos/local.nix`. The recipe prints this hint.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Changing IP over SSH drops the session | Note printed before the rebuild prompt |
| Wrapper does not load `local.nix` → setting silently ignored | Post-write check + warning, rebuild prompt skipped |
| Duplicate/conflicting definition with hand-written attrset | Guard in step 6 |
| `just` parser trips on `{{` in recipe body | Body avoids literal `{{`; regex quantifiers are single-brace |
| Bad input bricks networking | Strict IPv4/prefix validation; profile is a priority-10 NM profile, `wired-fallback` DHCP remains and `just rollback` undoes the rebuild |

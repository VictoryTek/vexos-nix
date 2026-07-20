# justfile_restart — Review

## Scope

Not a NixOS module change — no `nixosConfigurations` output is affected.
Build validation substitutes `just --list` (full-file syntax parse) and
direct execution of the new/refactored recipes, in place of the
`nix flake show` / `nixos-rebuild dry-build` checklist that applies to Nix
module changes.

## Checks

1. **Specification Compliance** — matches `justfile_restart_spec.md` exactly:
   `_service-units` extracted verbatim from `status`'s case statement,
   `status` updated to consume it, `restart` added with `reset-failed` +
   single-transaction `systemctl restart`, help text updated. PASS.
2. **Correctness of extraction** — diffed the moved case block against the
   original; every service → unit mapping preserved exactly, including the
   multi-line `arr` entry (originally split across two lines due to unit
   list length; now single-line in `_service-units`, and the leftover
   continuation line in `status`'s URLS-only case collapsed correctly).
   Verified `just _service-units joplin`, `just _service-units arr`, and
   the `*)` fallback case all return correct output. PASS.
3. **Restart ordering guarantee** — `restart` calls
   `sudo systemctl restart $UNIT_SERVICES` as one multi-argument invocation
   rather than a per-unit loop, so systemd resolves the `After=`/`Requires=`
   ordering already declared between e.g. `docker-joplin-db.service` and
   `docker-joplin-server.service` (`modules/server/joplin.nix:185-188`) as
   a single transaction. Matches spec. PASS.
4. **Consistency** — `restart` mirrors `status`'s structure (role guard,
   service validation against `_server_service_names`, per-unit status
   print at the end) rather than inventing a new pattern. PASS.
5. **Completeness** — `reset-failed` addresses the exact failure mode hit
   in this session (`docker-joplin-db.service` hitting `start-limit-hit`
   after repeated restart attempts), so `just restart joplin` alone would
   have recovered the stack without needing manual `systemctl reset-failed`
   + unit-name lookup. PASS.
6. **Security** — no new secrets, no plaintext credentials, no
   world-writable files. `sudo systemctl restart`/`reset-failed` scoped to
   systemd unit names built only from the validated `_server_service_names`
   list — no unsanitized user input reaches a shell command. PASS.
7. **Syntax validation** — `just --list` parses the full file with no
   errors; `[private]` recipes (`status`, `restart`, `_service-units`)
   correctly omitted from the printed list, matching existing convention
   where private per-service recipes are documented manually in `default`'s
   help text instead. PASS.
8. **Cosmetic** — one alignment artifact from the automated UNITS-stripping
   pass on the `arr)` line was caught and fixed to match sibling lines.

## Build Result

`just --list`: PASS (no syntax errors).
Direct recipe execution (`_service-units` for several services incl. the
multi-line `arr` case and the `*)` fallback): PASS, correct output.
`status`/`restart` role-guard (`_require-server-role`) verified to still
correctly reject execution on a non-server-role host (this dev machine),
matching pre-existing behavior — full end-to-end exercise against real
systemd units requires the actual server host (`vexos-vmc`), not available
in this session.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

Functionality scored 95% rather than 100% only because full multi-unit
restart behavior (ordering, `reset-failed` effectiveness) could not be
exercised against live systemd units in this sandbox — recommend the user
run `just restart joplin` on `vexos-vmc` once the underlying `nftables` fix
is in place, as a real-world confirmation.

## Result: PASS

# Spec — Sync `just available-services` and `just services` via a shared catalog

## Current state analysis

The `justfile` maintains the server-service list in **four** independent places:

| # | Location | Purpose | Form |
|---|----------|---------|------|
| 1 | `_server_service_names` (line ~1611) | validation allow-list for `enable`/`disable`/`restart`/`logs` | single space-separated string, 62 names |
| 2 | `available-services` recipe (lines ~1927-2011) | catalog view (name + description, grouped) | 62 `_svc name "desc"` calls under 14 `_hdr` groups |
| 3 | `services` recipe (lines ~2390-2428) | per-host enabled/disabled status | 59 `_check name` calls under 13 `_hdr` groups |
| 4 | `service-info` / `_units` / health-check `case` blocks | port/URL/unit metadata | out of scope for this change |

Lists 1 and 2 agree (62 entries). **List 3 has drifted**: it is missing
`grimmory`, `joplin`, and `searxng`, and orders several groups differently
(`Files & Storage`, `Infrastructure`, `Monitoring & Admin`). The "Books &
Reading" group in list 3 omits `grimmory`; there is no `searxng` under
"AI & Privacy".

Root cause: each of `grimmory` (2025-06), `searxng`, and `joplin` (2026-07-06,
commit `879fa92`) was added to lists 1, 2, the module tree, and
`template/server-services.nix`, but list 3 was not updated. Nothing enforces
consistency, so the display recipes drift silently.

## Problem definition

`just services` must show the same set of modules, in the same groups and order,
as `just available-services`. A user who sees a module in one command but not the
other cannot tell whether it exists.

## Proposed solution architecture

Introduce a single **service catalog** as a `justfile` variable — one line per
module, `group|name|description` — and rewrite both `available-services` and
`services` to iterate it. Neither command's on-screen output changes shape; only
the data source is unified. `services` keeps its host-specific `_check` logic
(grep of `/etc/nixos/server-services.nix`, including the `arr` sub-option
special-case) and its `_require-server-role` guard and empty-file guard.

`_server_service_names` (list 1) stays a separate hand-maintained string — it is
already correct and in agreement, and deriving it at parse time would require
`shell(...)` in a variable assignment, which is more fragile than the drift it
prevents. A comment cross-references the two.

### Why a `justfile` variable (not a data file / not a bash function)

- A `just` indented triple-quoted string (`'''…'''`) dedents cleanly and is
  visible in one place next to `_server_service_names`. Verified against
  `just 1.58.0`.
- A separate `scripts/*.txt` file spreads one concern across two files for no
  gain — the catalog is consumed only by the `justfile`.
- `just` recipes cannot share a bash function; a `_service-catalog` sub-recipe
  would work but adds an extra process spawn per call for no readability gain
  over `<<< '{{_service_catalog}}'`.

## Implementation steps

1. **Add `_service_catalog`** immediately after `_server_service_names` in the
   `# ── Server Services Management ──` section. Content = the exact 62 entries
   and 14 group names currently rendered by `available-services`, in that order.
   Add a comment: keep in sync with `_server_service_names`,
   `modules/server/default.nix`, and `template/server-services.nix`.

2. **Rewrite `available-services` recipe body** to a bash `while IFS='|' read`
   loop over `{{_service_catalog}}`, emitting `_hdr` on each group change and the
   existing `printf "    \033[36m%-22s\033[0m  %s\n"` per entry. Preserve the
   surrounding `echo` header/footer lines and `[private]` attribute verbatim.

3. **Rewrite `services` recipe body** to the same loop, but per entry run the
   existing check: `nix_name=$(echo "$name" | sed 's/-/_/g')`,
   `kernel-builder → kernelBuilder` special-case,
   `grep -qP "vexos\.server\.(${name}|${nix_name})\.enable\s*=\s*true"` → green
   `✓`, `arr` sub-option fallback → green `✓`, else grey `✗`. Preserve
   `_require-server-role`, the `SVC_FILE` empty-file guard, `set -euo pipefail`,
   the `Server services (/etc/nixos/server-services.nix):` header, and the
   `[private]` attribute.

4. No change to `_server_service_names`, module files, or the template.

## Module Architecture Pattern

Not applicable — `justfile` only. No Nix modules touched, no `lib.mkIf`, no
role imports.

## Dependencies

None. No new flake inputs, no new packages. `just` is already the project task
runner. No Context7 lookup required (no external library API).

## Configuration changes

None. `/etc/nixos/server-services.nix` schema is unchanged.

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| `just` indented-string dedent behaves unexpectedly | Verified on `just 1.58.0` in WSL: leading newline dropped, common indent stripped, groups render identically to a hand-written list. |
| A description contains `\|` and breaks the field split | Audited all 62 current descriptions — none contain `\|`. New entries must avoid it (noted in the catalog comment). |
| `set -euo pipefail` + `grep -q` non-match aborts `services` | `grep` runs only as an `if`/`elif` condition, where `set -e` is suppressed — same as the current recipe. |
| Output spacing/color changes | `printf` format strings copied verbatim from the current recipes; diff is data-only. |
| `_server_service_names` drifts from the new catalog later | Cross-reference comment on both; optional future `preflight` check noted but out of scope (Simplicity First). |

## Verification

1. `wsl nix run nixpkgs#just -- available-services` → lists 62 modules, 14 groups.
2. Extract names from `available-services` output and from `_service_catalog`;
   confirm both equal the 62 tokens in `_server_service_names`.
3. `just services` cannot run here (needs a NixOS server host with
   `/etc/nixos/server-services.nix`); validate its body by rendering the same
   loop against a stub `SVC_FILE` in the scratchpad and confirming group/name
   output matches `available-services` and `✓/✗` tracks the stub file.
4. `just --fmt --check --unstable` (or `just --evaluate`) parses cleanly.
5. `bash scripts/preflight.sh` exits 0.

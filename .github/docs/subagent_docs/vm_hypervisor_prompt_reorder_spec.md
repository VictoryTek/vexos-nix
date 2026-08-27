# VM Hypervisor Prompt Reorder — Spec

## Current state analysis

`justfile`'s `switch` recipe (added to by commit `0196e49`, "feat(vm): split
QEMU and VirtualBox guest platforms") asks four interactive questions in this
order when run as bare `just switch`:

1. Role (`justfile:176-199`)
2. GPU variant, with the NVIDIA driver-branch sub-question nested inside the
   same block, right after variant is picked (`justfile:201-238`)
3. Desktop environment — desktop role only, writes `features.nix` via
   `_features_set`, which shells out to `sudo sed`/`sudo cp`
   (`justfile:240-288`)
4. VM hypervisor — `vm` variant only, also writes `features.nix` via
   `_features_set` (`justfile:290-340`)

Block 4 was appended after the pre-existing block 3 when the hypervisor
feature was added, rather than being nested into block 2 the way the NVIDIA
driver-branch sub-question is. This is inconsistent with the established
pattern (a variant's own follow-up question stays adjacent to the variant
selection) and has an observed real-world consequence: block 3's
`_features_set` call is the first `sudo` invocation in the whole recipe. If
that sudo call fails or times out (confirmed in the field: "sudo: timed out
reading password"), `set -euo pipefail` aborts the script before block 4 ever
runs — so a user selecting the `vm` GPU variant can lose the hypervisor
question entirely, with no relationship between the two failures apparent
from the output.

## Problem definition

The VM hypervisor question is logically part of "what did you pick for GPU
variant", not part of "what did you pick for desktop environment". Its
current position after the DE block:
- reads oddly (unrelated question in between)
- couples its own reachability to the DE block's sudo call succeeding

## Proposed solution

Move the VM hypervisor selection block (`justfile:290-340`, including its
`VM_PLATFORM_CHANGED="false"` initialization) to immediately follow the GPU
variant block (after `justfile:238`, before the `# Desktop environment
selection` comment at `justfile:240`) — mirroring the NVIDIA driver-branch
sub-question's placement directly after variant selection.

No logic changes: the block's contents, the `_features_set` call, and its
guard conditions (`$VARIANT = "vm"`) are unchanged, only relocated. `ROLE`,
`FLAKE_OVERRIDE`, `DESKTOP_ENV`, and the `_features_set` helper function are
already defined earlier in the recipe (parameters at the top; `_features_set`
at `justfile:146-174`), so the move has no forward-reference issues.

## Implementation steps

1. Cut the block currently at `justfile:290-340` (comment through closing
   `fi`, plus its leading blank line) and the `VM_PLATFORM_CHANGED="false"`
   line.
2. Paste it directly after the GPU-variant block's closing `fi` (line 238)
   and before the `# Desktop environment selection` comment (line 240).
3. Leave the DE block, `TARGET=` assembly, and everything after it (line 342
   onward) unchanged in content — only their position relative to the moved
   block shifts.

Only `justfile` is touched. This is the same file that already ships to
`/etc/nixos/justfile` via `environment.etc."nixos/justfile"`
(`modules/packages-common.nix:8`) and to `~/justfile` via home-manager, so no
other file needs updating for the change to take effect on rebuild.

## Dependencies

None — pure shell reordering within an existing recipe, no new packages or
libraries.

## Configuration changes

None. `vexos.vm.platform` and `vexos.desktop.environment` option definitions
are untouched.

## Risks and mitigations

- **Risk:** subtle variable-ordering bug if the moved block referenced
  something set only by the DE block. **Mitigation:** verified by inspection
  — the VM block only reads `VARIANT`, `ROLE` (not used), `VM_PLATFORM`
  (recipe parameter), and calls `_features_set` (defined earlier); none of
  these depend on `DESKTOP_ENV`, `OLD_DESKTOP_ENV`, or `DE_CHANGED`.
- **Risk:** `DE_CHANGED`/`VM_PLATFORM_CHANGED` are both read together at line
  365 (`if [ "$DE_CHANGED" = "true" ] || [ "$VM_PLATFORM_CHANGED" = "true"
  ]`), after both blocks — unaffected by which block runs first, since both
  variables are set unconditionally (`"false"` default) before either
  conditional.
- **No build/eval impact:** `justfile` is not consumed by Nix evaluation
  (it's copied verbatim as a source file by `environment.etc` and
  `home.file`), so `nix flake show --impure` / dry-builds are expected to be
  unaffected — run anyway per project policy to confirm no incidental
  regression.

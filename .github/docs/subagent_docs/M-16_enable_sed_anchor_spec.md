# M-16 — `just enable` corrupts service files with nested braces

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-16 (BUGS M23) · `justfile` (4 call sites, all read in full)

## Current State

Four separate call sites in `justfile` insert a new option before a config file's
closing brace using the identical fragile pattern:

```bash
sudo sed -i "s|}|  ${OPTION} = true;\n}|" "$SVC_FILE"
```

`sed`'s `s|}|...|` (no `g` flag, no line address) runs on **every line** of the file and
replaces the **first** `}` character found **on each line independently** — it doesn't
target "the file's final closing brace" specifically. Once `server-services.nix` (or
`features.nix`) contains any line with a `}` earlier in the file than the true trailing
brace — for example, a value on its own line that happens to include one, or simply the
file having already had multiple entries inserted by this same mechanism over time — the
substitution lands on the wrong line, corrupting the file instead of appending the new
option at the end.

Confirmed the template's actual structure: `template/server-services.nix` always ends
with a bare `}` alone on its own final line, matching the same shape `features.nix` and
every generated variant of these files has.

## Problem Definition

Anchor the substitution to the file's actual final closing brace, regardless of what
else appears earlier in the file.

## Proposed Solution

Per the MASTER_PLAN's suggestion: add sed's `$` address (last line) and anchor the
pattern to `^}` (a line that *starts with* `}`, matching only the bare trailing brace,
not an inline `}` that might appear mid-line elsewhere):

```bash
sudo sed -i "\$ s|^}|  ${OPTION} = true;\n}|" "$SVC_FILE"
```

This only ever touches the last line of the file, and only if that line is the bare
closing brace — both conditions the template's structure always satisfies.

## Implementation Steps

1. `justfile` — apply the same `$ s|^}|...` anchor to all four call sites (the
   `enable-feature` recipe's `$FEAT_FILE` insertion, the `enable` service recipe's
   `$SVC_FILE` insertion, and the two VexBoard auto-secret/auto-enable insertions in
   `_ensure_vexboard_secret`/the VexBoard auto-enable block) — all four share the
   identical defect shape, so fixing only the one named in the MASTER_PLAN while
   leaving the other three broken would be an inconsistent half-fix.

## Configuration Changes

None.

## Risks and Mitigations

- **`$` inside a double-quoted bash string** must be escaped as `\$` so bash passes a
  literal `$` to `sed` rather than attempting its own variable expansion — applied
  consistently at all four sites.
- **Verify the fix actually targets only the last line** — confirmed via an isolated
  test against a synthetic file containing an inline `}` earlier in the file (the exact
  corruption scenario), comparing old vs. new behavior.

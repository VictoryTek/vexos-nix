# Spec: Numbered Menu for `just enable arr` Individual-Component Selection

## Current State Analysis

- `justfile:1704-1733` implements the interactive `just enable arr` flow.
- Mode selection: `read -r -p "  [F]ull / [i]ndividual: " _arr_mode` — free-text
  single-letter entry.
- Individual-component selection: `read -r -p "  Enter components (space or
  comma separated: sabnzbd, sonarr, radarr, lidarr, prowlarr, qbittorrent,
  bazarr, maintainerr): " _arr_selected` — user must type exact component
  names from memory, comma- or space-separated.
- `ARR_COMPONENTS="sabnzbd sonarr radarr lidarr prowlarr qbittorrent bazarr maintainerr"`
  (justfile:1705) is the authoritative ordered component list, already used
  for validation via `echo "$ARR_COMPONENTS" | tr ' ' '\n' | grep -qx "$_c"`.
- This is a pure shell/UX change inside a `justfile` recipe — no `.nix` files,
  no flake outputs, no `nixosConfigurations` are touched.

## Problem Definition

Typing exact component names from memory is error-prone and slow. The user
wants a numbered menu instead:
1. Top-level choice presented as a numbered list (`1. Full`, `2. Individual`)
   instead of a bare `[F]/[i]` letter prompt.
2. When "Individual" is chosen, each component is shown as a numbered list
   (in the existing `ARR_COMPONENTS` order) and the user selects by number(s)
   (space- or comma-separated), not by typing names.

## Proposed Solution

Modify only the interactive block at `justfile:1710-1723`. No changes to
`modules/server/arr.nix`, flake outputs, or any other recipe.

### 1. Top-level mode prompt

Replace:
```sh
echo "  Enable the full *arr stack, or select individual components?"
read -r -p "  [F]ull / [i]ndividual: " _arr_mode
if [[ "$_arr_mode" =~ ^[Ii]$ ]]; then
```
with a numbered menu:
```sh
echo "  Enable the full *arr stack, or select individual components?"
echo "    1. Full"
echo "    2. Individual"
read -r -p "  Select [1/2]: " _arr_mode
if [ "$_arr_mode" = "2" ]; then
```

### 2. Individual-component prompt

Replace the free-text component prompt with a numbered list built from
`ARR_COMPONENTS`, then map selected numbers back to names:
```sh
echo "  Select components:"
_i=0
for _c in $ARR_COMPONENTS; do
    _i=$((_i + 1))
    printf "    %d. %s\n" "$_i" "$_c"
done
read -r -p "  Enter numbers (space or comma separated): " _arr_selected
_arr_selected="${_arr_selected//,/ }"
_arr_enabled=""
for _n in $_arr_selected; do
    _c=$(echo "$ARR_COMPONENTS" | tr ' ' '\n' | sed -n "${_n}p")
    if [ -z "$_c" ]; then
        echo "  error: invalid selection '$_n' — skipping"
        continue
    fi
    _set_flag "vexos.server.arr.${_c}.enable" true
    _arr_enabled="$_arr_enabled $_c"
done
```

Validation behavior is preserved: non-numeric or out-of-range entries are
skipped with an error message per-item (same as the current "unknown
component" path), and an empty final selection still exits 1 with
`error: no valid components selected` (existing code, unchanged).

Everything after component/mode selection (VexBoard auto-enable, the
"Enabled components:" URL summary, `exit 0`) is unchanged.

## Implementation Steps

1. Edit `justfile` lines 1710-1723 as shown above.
2. No other files change.

## Dependencies

None — pure POSIX shell (`sed -n Np`, arithmetic `$(( ))`), consistent with
the rest of the recipe. No new external library or Context7 lookup applies
(internal shell script change only).

## Configuration Changes

None. Behavior of the underlying `vexos.server.arr.*.enable` NixOS options is
unchanged; only the interactive CLI selection mechanism changes.

## Risks and Mitigations

- **Risk:** off-by-one in `sed -n "${_n}p"` numbering vs. the printed list.
  **Mitigation:** both the printed menu and the lookup iterate/index the same
  `ARR_COMPONENTS` ordering (1-indexed via `sed -n Np`), so they stay in sync
  by construction.
- **Risk:** user enters "F"/"full" out of habit for the top-level prompt.
  **Mitigation:** acceptable behavior change — this recipe intentionally
  switches to numeric-only selection per user request; the recipe is
  interactive/local-only (never used in CI), so this is low risk.

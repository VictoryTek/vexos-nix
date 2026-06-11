# install_nvidia_prompt_fix — Specification

## Current State

`scripts/install.sh` NVIDIA driver branch prompt (lines 170-181):

```bash
while [ -z "$NVIDIA_SUFFIX" ]; do
  printf "Enter choice [1-2]: "
  read -r INPUT </dev/tty
  case "${INPUT}" in
    1) NVIDIA_SUFFIX=""             ;;
    2) NVIDIA_SUFFIX="-legacy535"   ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}"
      ;;
  esac
  [[ -n "${INPUT}" ]] && break
done
```

Two bugs:
1. Choice 1 sets `NVIDIA_SUFFIX=""` (still empty), so the `while [ -z "$NVIDIA_SUFFIX" ]`
   condition would loop forever for choice 1. It only exits because of the stray break.
2. The stray `[[ -n "${INPUT}" ]] && break` fires for ANY non-empty input — including
   invalid input — silently breaking with `NVIDIA_SUFFIX=""` (= latest selected).

`justfile` switch recipe (line 306) still references the dropped `legacy470` option.

## Proposed Solution

### install.sh
Rewrite to the `while true` + explicit `break` pattern:
- `while true` removes the broken loop condition
- `break` added inside each valid case branch
- Stray `[[ -n "${INPUT}" ]] && break` removed

### justfile switch recipe (lines 304-317)
- Remove the `legacy470` display line and its case branch
- Update prompt from `[1-3]` to `[1-2]`
- Update error message from "enter 1, 2, or 3" to "enter 1 or 2"

## Files Modified

- `scripts/install.sh`
- `justfile`

## Risks

None. The fix only corrects control flow — the valid selection outcomes
(NVIDIA_SUFFIX="" and NVIDIA_SUFFIX="-legacy535") are unchanged.

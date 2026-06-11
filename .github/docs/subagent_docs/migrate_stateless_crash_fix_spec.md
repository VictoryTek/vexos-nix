# migrate_stateless_crash_fix — Specification

## Current State

`scripts/migrate-to-stateless.sh` always crashes at the final summary block (line 420):

```bash
if $CUSTOM_PASSWORD_SET; then
  echo "  Password: (same as before migration)"
else
  echo "  Password: vexos (default — no existing hash found)"
fi
```

Two bugs:
1. `CUSTOM_PASSWORD_SET` is never declared or assigned anywhere in the script.
   Bash attempts to execute the empty value as a command and fails.
2. The `else` message claims the password is "vexos (default)" but the code
   never sets a vexos default — when no existing hash is found, the script
   forces the user to enter a new password (lines 326-344). The message is wrong.

## Proposed Solution

1. Initialize `CUSTOM_PASSWORD_SET=false` at the same point `HASHED_PW=""` is
   declared (line 310), before the password detection block.
2. Set `CUSTOM_PASSWORD_SET=true` immediately after the existing hash is captured
   (line 317-318) — this branch means the existing password was preserved.
3. Fix the `else` message: replace "vexos (default — no existing hash found)"
   with "(the new password you just set)" — which is what actually happened
   in that branch.

## Files Modified

- `scripts/migrate-to-stateless.sh`

## Risks

The migration itself completes correctly before this crash point. This fix only
corrects the final informational printout. No functional behaviour changes.

# VexBoard probe.history_retention_days fix — Spec

## Current state analysis

`modules/server/vexboard.nix` sets `services.vexboard.settings` explicitly because
the upstream NixOS module runs the binary with `WorkingDirectory = "/"`, so the
binary never finds `config/default.toml` and requires every field to be supplied
via env/settings instead. The `[probe]` block currently is:

```nix
probe = {
  default_interval_secs = 30;
  timeout_secs = 5;
  max_history = 100;
};
```

## Problem definition

After the daily flake update advanced `vexboard` to `0.3.0` (flake.lock rev
`6b60ff63524f0c61b4d6a3966b3f378567d371c6`), `vexboard.service` fails to start on
host `vexmox`:

```
Error: missing configuration field "probe.history_retention_days"
```

Fetched upstream `config/default.toml` at that exact locked rev
(`https://raw.githubusercontent.com/VictoryTek/vexboard/6b60ff63524f0c61b4d6a3966b3f378567d371c6/config/default.toml`)
confirms the `[probe]` section is now:

```toml
[probe]
default_interval_secs = 30
timeout_secs = 5
history_retention_days = 30  # days of probe_results kept per service
```

`max_history` no longer exists upstream at all — it was replaced by
`history_retention_days` (a retention-by-days field instead of a row-count cap).
This is upstream config-schema drift that our explicit-defaults block (which
intentionally mirrors `config/default.toml`, per the existing comment at
`vexboard.nix:80-84`) did not track.

## Proposed solution

Update the `[probe]` block in `modules/server/vexboard.nix` to match the current
upstream default exactly: drop `max_history`, add `history_retention_days = 30`.
No new option surface is needed — this project's `vexos.server.vexboard` options
don't expose a knob for this value today (same as they don't for
`default_interval_secs`/`timeout_secs`), so keep parity and just hardcode the
upstream default like the surrounding fields.

## Implementation steps (Module Architecture Pattern — Option B)

This is a same-module, same-option-set change — no new `modules/*.nix` file needed,
no new `lib.mkIf` role/display/gaming guard introduced. Single edit:

- `modules/server/vexboard.nix`: in the `services.vexboard.settings.probe`
  attrset, replace `max_history = 100;` with `history_retention_days = 30;`.

## Dependencies

None. No new flake input, no Context7 lookup needed (internal config value change
only, verified directly against the pinned upstream source at the locked rev).

## Configuration changes

`services.vexboard.settings.probe.history_retention_days = 30` (was
`max_history = 100`, which no longer exists upstream).

## Risks and mitigations

- **Risk:** `30` days retention differs in semantics from the old `100`-row cap;
  behavior for existing installs changes from "keep last 100 probe results" to
  "keep 30 days of probe results." Mitigated by using upstream's own default
  value verbatim, which is the value upstream ships and expects.
- **Risk:** other config fields could also have drifted between this and future
  vexboard releases. Out of scope for this fix — only the field currently
  breaking `vexboard.service` is addressed.

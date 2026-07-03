# H-17 — Wire system events into the self-hosted ntfy server

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN FEATURES 2.2 · `modules/server/ntfy.nix`

## Current State

`modules/server/ntfy.nix` runs `services.ntfy-sh` with `auth-default-access = "deny-all"`
(private by default). Nothing in the repo ever publishes to it — zero producers.
`modules/server/backup.nix` (H-16) already left a documented but inert extension point:
`# systemd.services."restic-backups-main".onFailure = [ "notify-failure@backup.service" ];`

Upstream `services.ntfy-sh` (verified against the pinned nixpkgs revision,
`nixos/modules/services/misc/ntfy-sh.nix`) has no declarative user/token/ACL option —
access control is managed via the `ntfy` CLI against a sqlite auth db
(`ntfy user add`, `ntfy token add`, `ntfy access`), which cannot be expressed as pure
Nix module config. This is a genuine tool limitation, not something to work around.

## Problem Definition

Give the rest of the system a way to actually publish to ntfy, without requiring the
publishing side to know or care whether ntfy is even installed on this host (vexos-update
runs on every role; ntfy itself is server-only).

## Proposed Solution

`modules/notify.nix` (new, **not** under `modules/server/` — this is a client-side
capability needed by every role, same reasoning as `modules/nix.nix`/`vexos-update`
being imported by all six `configuration-*.nix` files, not just server ones):

- `vexos.notify.ntfyUrl` (nullOr str, default null) — full topic URL, e.g.
  `"http://<server-ip>:2586/vexos-alerts"` for the self-hosted server, or
  `"https://ntfy.sh/<random-topic>"` for the public instance. `null` means
  notifications are a no-op — safe default, no assertion required.
- `vexos.notify.tokenFile` (nullOr path, default null) — ntfy access token, sent as
  `Authorization: Bearer $(cat tokenFile)`. Documented as required when
  `ntfyUrl` points at a `vexos.server.ntfy` instance (which defaults to `deny-all`);
  the token itself must be generated once via `ntfy token add <user>` on the ntfy
  host — a genuinely manual step, not automatable from Nix eval, and documented as such
  rather than faked.
- Installs `vexos-notify` (`pkgs.writeShellScriptBin`), signature
  `vexos-notify <message> [title]`. When `ntfyUrl` is null the script body is just
  `exit 0` (decided at Nix-eval time via the option value, not a bash runtime branch —
  keeps the script minimal for the common case). When set, it does a plain `curl -sf
  -X POST` (or PUT) to `ntfyUrl` with the message as the body and `X-Title` header,
  attaching the Bearer header only when `tokenFile` is set. Never fails the caller: exits
  0 even if the curl call fails (a notification failure must never cascade into failing
  the thing it's reporting on — e.g. a network blip on the ntfy host must not fail an
  otherwise-successful update).
- A parametrised `notify-failure@.service` template unit
  (`systemd.services."notify-failure@"`), `ExecStart = vexos-notify "%i failed on
  $(hostname)"`. Any unit can opt in with `onFailure = [ "notify-failure@<name>.service" ];`
  — this is exactly the extension point `backup.nix`'s comment already names.

## Implementation Steps

1. `modules/notify.nix` (new) — options + `vexos-notify` script + `notify-failure@.service`
   template, per above.
2. `configuration-desktop.nix`, `configuration-htpc.nix`, `configuration-server.nix`,
   `configuration-headless-server.nix`, `configuration-stateless.nix`,
   `configuration-vanilla.nix` — add `./modules/notify.nix` to `imports`, right next to
   the existing `./modules/nix.nix` line in each (matches how `modules/nix.nix` itself is
   distributed across all six roles).
3. `modules/server/backup.nix` — replace the inert comment with a live
   `systemd.services."restic-backups-main".onFailure = lib.mkIf cfg.enable [ "notify-failure@backup.service" ];`
   wired unconditionally (safe even without `vexos.notify.ntfyUrl` set — the failure
   unit exists but `vexos-notify` just no-ops).
4. `modules/nix.nix` — one line at the end of the `vexos-update` script body, after the
   `nixos-rebuild switch` call succeeds: `vexos-notify "Update applied on $(hostname)"`.
   `set -euo pipefail` is already active in that script, so this line is only reached on
   success (matches the literal "one-line hook at end of vexos-update" wording).

## Configuration Changes

None to `flake.nix`. No new flake inputs (`services.ntfy-sh` and the notify module are
both already-available nixpkgs/local-module surface).

## Risks and Mitigations

- **Token provisioning is manual** — documented in the option description rather than
  automated, since ntfy's own auth model doesn't support declarative token creation.
- **Notify must never break the thing it reports on** — `vexos-notify`'s curl call is
  best-effort (`|| true` equivalent), so a flaky ntfy server can't turn a successful
  backup/update into a failed one.
- **Cross-role import surface**: `modules/notify.nix` touches all six
  `configuration-*.nix` files. Each edit is a single one-line import addition, matching
  the existing pattern for `modules/nix.nix` exactly — no other content in those files
  changes.

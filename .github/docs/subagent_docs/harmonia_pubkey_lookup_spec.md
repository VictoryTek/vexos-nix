# Harmonia public-key lookup fix — Specification

## Current state

`just harmonia-info` (justfile ~L3132) verifies the cache is live, then prints the
client config. It reads the cache public key from a **hardcoded** path:

```sh
KEY_PUB="/var/lib/harmonia/cache-priv-key.pem.pub"
...
if [ ! -r "$KEY_PUB" ]; then
    echo "error: public key not found at $KEY_PUB" >&2
```

`modules/server/harmonia.nix` declares `signKeyPath` (default
`/var/lib/harmonia/cache-priv-key.pem`) and generates `<signKeyPath>.pub` in
`system.activationScripts.harmoniaKey` — but only when
`config.vexos.secrets.backend != "sops"`. Under the sops backend,
`modules/secrets-sops.nix:228` forces:

```nix
vexos.server.harmonia.signKeyPath = lib.mkForce config.sops.secrets."harmonia-cache-priv-key".path;
```

i.e. `/run/secrets/harmonia-cache-priv-key`, mode 0400 root — and **no `.pub`
file is produced anywhere**.

## Problem

Observed: the probe of `/nix-cache-info` succeeds (the cache is genuinely
serving) but the recipe then fails with
`error: public key not found at /var/lib/harmonia/cache-priv-key.pem.pub`.
Its advice ("try 'just rebuild'") cannot fix it. Two independent defects
produce this exact failure:

1. **sops backend** — `signKeyPath` points into `/run/secrets`; the hardcoded
   `/var/lib/harmonia/...pub` never exists. The recipe can never succeed.
2. **plaintext backend** — the activation script does
   `chmod 0700 "$(dirname ...)"`, so `/var/lib/harmonia` is not traversable by
   a non-root user. The `.pub` is 0644 but unreachable, contradicting the
   module comment ("The public half is 0644 so `just harmonia-info` can print
   it without sudo"). `[ ! -r "$KEY_PUB" ]` is therefore true for the invoking
   user even though the file exists.

Both make `vexos.harmonia.publicKey` unobtainable, which leaves the warning in
`modules/nix.nix:126` permanently active and the cache ignored by all clients.

## Proposed solution

Make the recipe derive the key from the **configured** signing key rather than
a hardcoded path, and make the plaintext-backend `.pub` genuinely readable.

### A. `justfile` — `harmonia-info`

1. Resolve the real key path from the running configuration, using the pattern
   already established in `_kernel-cache-guard` (justfile L275-L287):
   `nix eval --impure --raw "path:/etc/nixos#nixosConfigurations.$(cat /etc/nixos/vexos-variant).config.vexos.server.harmonia.signKeyPath"`,
   falling back to `/var/lib/harmonia/cache-priv-key.pem` if evaluation fails.
2. If `<key>.pub` is readable, use it (no sudo — the common plaintext path).
3. Otherwise derive the public half from the private key:
   `sudo nix key convert-secret-to-public < "$KEY"`.
   This is the supported upstream conversion (`nix key
   convert-secret-to-public`, verified present in this Nix), works for both
   backends, and is what makes the sops case work at all — the sops secret is
   root-only 0400 by design, so one sudo prompt is unavoidable and acceptable
   (the justfile already uses sudo in 116 places).
4. Replace the misleading "try 'just rebuild'" message with one naming the key
   path actually inspected.

### B. `modules/server/harmonia.nix`

Change the activation script's state-directory mode from `0700` to `0711`
(traverse, no listing) so the 0644 `.pub` is reachable without sudo, as the
existing comment already claims. The private key stays `0600` root-owned, so
it remains unreadable; `0711` exposes no directory listing.

## Out of scope (noted, not changed)

`harmonia-info` also hardcodes `PORT=5000` while the module exposes
`vexos.server.harmonia.port`. Not the reported failure; left untouched per the
surgical-changes rule.

## Implementation steps

1. Edit `modules/server/harmonia.nix`: `chmod 0700` → `chmod 0711` on the key
   directory + comment touch-up → verify: `sudo nixos-rebuild dry-build` passes.
2. Edit `justfile` `harmonia-info`: config-resolved key path, `.pub`-then-derive
   lookup, corrected error text → verify: `just --evaluate`/`just --list` parses,
   `bash -n` on the extracted recipe body.
3. Verify: `nix flake show --impure`, dry-build of desktop + server variants,
   `bash scripts/preflight.sh`.

## Dependencies

None added. `nix key convert-secret-to-public` ships with the Nix CLI
(`nix-command` experimental feature, already enabled in `modules/nix.nix`).
No Context7 lookup required — no new external library.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| `nix eval` of `/etc/nixos` is slow or fails on a non-vexos host | Guarded: falls back to the default key path, recipe still works on plaintext hosts |
| sudo prompt appears mid-recipe | Only in the derive branch; message printed before prompting so the reason is clear |
| `0711` on `/var/lib/harmonia` | Traverse-only; no listing. Private key remains `0600` root. Harmonia's own unit reads the key via systemd `LoadCredential` as root, unaffected. |

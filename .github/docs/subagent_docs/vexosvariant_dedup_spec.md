# Spec: vexosVariant Activation Script Deduplication

**Feature name:** `vexosvariant_dedup`
**Spec file:** `.github/docs/subagent_docs/vexosvariant_dedup_spec.md`

---

## 1. Current State Analysis

### 1a. Authoritative definition — `modules/impermanence.nix` (lines 232–241)

```nix
system.activationScripts.vexosVariant = lib.mkIf (config.vexos.variant != "") {
  deps = [ "etc" ];
  text = ''
    PERSIST_DIR="${cfg.persistentPath}/etc/nixos"
    ${pkgs.coreutils}/bin/mkdir -p "$PERSIST_DIR"
    ${pkgs.coreutils}/bin/printf '%s' '${config.vexos.variant}' \
      > "$PERSIST_DIR/vexos-variant"
  '';
};
```

Characteristics:
- Gated by `lib.mkIf (config.vexos.variant != "")` — only fires when the option is set
- Declares `deps = ["etc"]` — ordering guarantee relative to NixOS `etc` activation step
- Uses fully-qualified coreutils paths (`${pkgs.coreutils}/bin/mkdir`, `${pkgs.coreutils}/bin/printf`) — safe in the activation environment where `PATH` is minimal
- Uses `cfg.persistentPath` (configurable, defaults to `/persistent`)
- Writes `config.vexos.variant` (no trailing newline), matching what `vexos-updater` expects

### 1b. Duplicate #1 — `template/etc-nixos-flake.nix` inside `_mkVariantWith` (lines ~135–141)

Used by `mkVariant` → desktop role only.

```nix
{
  system.activationScripts.vexosVariant = ''
    # Write variant directly to persistent subvolume, bypassing bind-mount timing
    PERSIST_DIR="/persistent/etc/nixos"
    mkdir -p "$PERSIST_DIR"
    printf '%s' '${variant}' > "$PERSIST_DIR/vexos-variant"
  '';
}
```

Characteristics:
- No `lib.mkIf` guard — always active regardless of whether `/persistent` exists
- No `deps` declaration — no ordering guarantee
- Uses bare `mkdir` and `printf` — unsafe in activation context (PATH not guaranteed)
- Hardcodes `/persistent/etc/nixos` — wrong for desktop, which does not have a persistent Btrfs subvolume at `/persistent`
- The `${variant}` is a Nix function-argument string interpolation, not `config.vexos.variant`

**Bug:** Desktop does not use impermanence and has no `/persistent` Btrfs subvolume. Writing to `/persistent/etc/nixos` on a desktop creates that directory on the root filesystem (or tmpfs). The other non-stateless builders in the template (`mkServerVariant`, `mkHeadlessServerVariant`, `mkHtpcVariant`, `mkVanillaVariant`) all correctly use `environment.etc."nixos/vexos-variant".text = "${variant}\n";` instead. `mkVariant` (desktop) is the odd one out.

### 1c. Duplicate #2 — `template/etc-nixos-flake.nix` inside `mkStatelessVariant` (lines ~177–183)

```nix
{
  system.activationScripts.vexosVariant = ''
    # Write variant directly to persistent subvolume, bypassing bind-mount timing
    PERSIST_DIR="/persistent/etc/nixos"
    mkdir -p "$PERSIST_DIR"
    printf '%s' '${variant}' > "$PERSIST_DIR/vexos-variant"
  '';
}
```

Identical in form to Duplicate #1. Same quality issues (no guard, no deps, bare paths, hardcoded path).

---

## 2. Problem Definition

### 2a. Activation script conflict for stateless role

When a user applies `mkStatelessVariant`, the resulting NixOS configuration contains:
- `system.activationScripts.vexosVariant` (inline template string — always active)
- `system.activationScripts.vexosVariant` from `modules/impermanence.nix` (gated by `config.vexos.variant != ""`)

`system.activationScripts` uses `types.lines` for the `text` field, meaning NixOS concatenates both scripts when both fire. However, `modules/impermanence.nix` uses `lib.mkIf (config.vexos.variant != "")` as the guard, and the template **never sets `config.vexos.variant`** — it only uses `${variant}` as a Nix string literal at build time.

**Net result:** `config.vexos.variant == ""` → the impermanence.nix guard is false → only the inferior template inline script runs. The authoritative script from `modules/impermanence.nix` is silently bypassed.

### 2b. Wrong variant mechanism for desktop role

`mkVariant` (desktop) uses `_mkVariantWith vexos-nix.nixosModules.base`. `nixosModules.base` derives from `configuration-desktop.nix`, which does **not** import `modules/impermanence.nix`. Therefore:
- `vexos.variant` option is not defined for the desktop evaluation
- The inline activationScript writing to `/persistent/etc/nixos` fires unconditionally on desktop systems
- Desktop systems have no `/persistent` Btrfs subvolume; the script creates the path on whatever filesystem `/` is

All other non-stateless template builders (`mkServerVariant`, `mkHeadlessServerVariant`, `mkHtpcVariant`, `mkVanillaVariant`) correctly use `environment.etc."nixos/vexos-variant".text`. The `mkHost` function in `flake.nix` also uses `environment.etc` for non-stateless. `mkVariant` (desktop) is inconsistent.

### 2c. Is `template/etc-nixos-flake.nix` imported by any flake output?

No. A grep of `flake.nix` for `template` returns a single comment line (line 89) explaining that `nixosModules.*Base` exports are consumed by the template. The file is a user-facing template intended to be copied to `/etc/nixos/flake.nix` on the host machine. It is **not** imported by any `nixosConfigurations` or `nixosModules` in the repo's own `flake.nix`.

---

## 3. Are the Scripts Identical?

**Duplicate #1 and Duplicate #2 are textually identical.** They share the same bare-shell body, the same hardcoded `/persistent/etc/nixos` path, and the same structural deficiencies.

**Compared to the authoritative `modules/impermanence.nix` version:**

| Property | `modules/impermanence.nix` | Template inline |
|---|---|---|
| Guard | `lib.mkIf (config.vexos.variant != "")` | None |
| `deps` | `["etc"]` | None |
| `mkdir` path | `${pkgs.coreutils}/bin/mkdir` | `mkdir` (bare) |
| `printf` path | `${pkgs.coreutils}/bin/printf` | `printf` (bare) |
| Persistent path | `${cfg.persistentPath}/etc/nixos` | `/persistent/etc/nixos` |
| Value written | `${config.vexos.variant}` (option) | `${variant}` (Nix arg) |
| Trailing newline | No | No |

**The template versions are strictly inferior** (no guard, no ordering deps, bare shell commands, hardcoded path). They exist because the template predates the `vexos.variant` option mechanism or was not updated to use it.

---

## 4. Which Is Authoritative?

**`modules/impermanence.nix` is authoritative** for stateless. It:
- Was deliberately designed with guards, ordering, and absolute paths
- Is the mechanism used by `flake.nix`'s own `mkHost` for the stateless role (`variantModule = { vexos.variant = name; }`)
- Is documented in `stateless-vexos-variant-persist_spec.md` and `stateless-vexos-variant-persist_review.md`

The template inline scripts are incidental duplicates that work by accident (they bypass the option mechanism entirely) and introduce technical debt.

---

## 5. Proposed Solution Architecture

### Fix A — `mkStatelessVariant` in `template/etc-nixos-flake.nix`

**Replace** the inline `system.activationScripts.vexosVariant` anonymous module:

```nix
# REMOVE THIS:
{
  system.activationScripts.vexosVariant = ''
    PERSIST_DIR="/persistent/etc/nixos"
    mkdir -p "$PERSIST_DIR"
    printf '%s' '${variant}' > "$PERSIST_DIR/vexos-variant"
  '';
}
```

**With** a module that sets the `vexos.variant` option:

```nix
# ADD THIS:
{ vexos.variant = variant; }
```

This delegates to `modules/impermanence.nix`'s authoritative activation script (absolute coreutils paths, `deps = ["etc"]`, `lib.mkIf` guard, configurable persist path). It mirrors exactly what `flake.nix`'s `mkHost` does for the stateless role.

### Fix B — `_mkVariantWith` in `template/etc-nixos-flake.nix` (desktop)

**Replace** the inline `system.activationScripts.vexosVariant` anonymous module:

```nix
# REMOVE THIS:
{
  system.activationScripts.vexosVariant = ''
    PERSIST_DIR="/persistent/etc/nixos"
    mkdir -p "$PERSIST_DIR"
    printf '%s' '${variant}' > "$PERSIST_DIR/vexos-variant"
  '';
}
```

**With** the standard `environment.etc` approach used by all other non-stateless builders:

```nix
# ADD THIS:
{ environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
```

This is consistent with `mkServerVariant`, `mkHeadlessServerVariant`, `mkHtpcVariant`, `mkVanillaVariant`, and `flake.nix`'s `mkHost` for non-stateless roles. It writes through the NixOS `etc` activation (correct for non-impermanence systems) and includes the trailing newline that the other non-stateless builders include.

---

## 6. Implementation Steps

1. Open `template/etc-nixos-flake.nix`.
2. Locate `_mkVariantWith` (around line 121). Find the anonymous module inside it containing `system.activationScripts.vexosVariant = ''...''`. Replace the entire anonymous module `{ system.activationScripts.vexosVariant = ''...''; }` with `{ environment.etc."nixos/vexos-variant".text = "${variant}\n"; }`.
3. Locate `mkStatelessVariant` (around line 162). Find the anonymous module inside it containing `system.activationScripts.vexosVariant = ''...''`. Replace the entire anonymous module `{ system.activationScripts.vexosVariant = ''...''; }` with `{ vexos.variant = variant; }`.
4. Verify the surrounding context is intact (the `bootloaderModule`, `./hardware-configuration.nix`, `vexos-nix.nixosModules.*` imports must remain unchanged).
5. No changes to `modules/impermanence.nix` are needed.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Template is not evaluated by `nix flake check` (it's not a flake output) | Medium | Dry-run check is not possible via `nix flake check`. The change is syntactically simple and mirrors the already-working `mkHost` pattern in `flake.nix`. Visual review is sufficient. |
| `vexos.variant` option unavailable in desktop evaluation | None — this is the fix | Fix B replaces the activationScript with `environment.etc`, which does not require `vexos.variant`. No option reference is added to the desktop evaluation path. |
| Stateless systems already deployed with the old template | Low | Behaviour is functionally identical: the same value is written to the same path. The only change is which mechanism writes it (option-driven vs. raw inline). |
| Trailing newline difference (impermanence.nix writes no newline; environment.etc writes `\n`) | Low | Non-stateless roles already include `\n` via `environment.etc`. Stateless role (fix A) uses `modules/impermanence.nix` which omits the newline — same as before. `vexos-updater` reads the file with a trim; trailing newline is irrelevant. |

---

## 8. Files to Modify

| File | Change |
|---|---|
| `template/etc-nixos-flake.nix` | Two block replacements (see §6) |

No other files require changes.

---

## 9. Acceptance Criteria

- `template/etc-nixos-flake.nix` contains **zero** occurrences of `system.activationScripts.vexosVariant`.
- `_mkVariantWith` includes `{ environment.etc."nixos/vexos-variant".text = "${variant}\n"; }`.
- `mkStatelessVariant` includes `{ vexos.variant = variant; }`.
- `nix flake check` passes (validates the repo's own outputs; template is not evaluated but the repo must remain healthy).
- `preflight.sh` passes.

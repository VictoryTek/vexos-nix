# Specification: README & Template Cleanup (Audit Findings B4, B5)

**Date:** 2026-04-26
**Scope:** Documentation-only — no functional Nix changes

---

## 1. Current State Analysis

### 1.1 legacy390 References (B4)

The `legacy_390` (Fermi) NVIDIA driver was removed from `flake.nix` hostList because it is broken in current nixpkgs (confirmed by `modules/gpu/nvidia.nix` lines 11, 22, 44). However, stale references remain in documentation:

| File | Line | Content |
|------|------|---------|
| `README.md` | 67 | `\| \`vexos-desktop-nvidia-legacy390\` \| NVIDIA Fermi legacy — GeForce 400/500 series (390.x driver) \|` |
| `README.md` | 88 | `\| \`vexos-stateless-nvidia-legacy390\` \| NVIDIA Fermi legacy — GeForce 400/500 series, minimal stack \|` |
| `README.md` | 137 | `\| \`vexos-htpc-nvidia-legacy390\` \| NVIDIA Fermi legacy — GeForce 400/500 series \|` |
| `template/etc-nixos-flake.nix` | 18 | `#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy390    (Fermi  — GTX 400/500)` |

### 1.2 Role Count Claim (B4)

| File | Line | Current | Correct |
|------|------|---------|---------|
| `README.md` | 13 | `Comes in seven roles:` | `Comes in five roles:` |

The five actual roles are: Desktop, Stateless, GUI Server, Headless Server, HTPC.

The introductory paragraph (lines 14–17) only names four bullet points (Desktop, Stateless, Server, HTPC), combining GUI Server and Headless Server under "Server (GUI & Headless service stack)". This is acceptable editorial shorthand, but the count "seven" is wrong regardless — it should say "five".

### 1.3 Variant Tables vs. Actual Flake Outputs

The authoritative list of 30 `nixosConfigurations` from `flake.nix` lines 152–195:

**Desktop (6):**
1. `vexos-desktop-amd`
2. `vexos-desktop-nvidia`
3. `vexos-desktop-nvidia-legacy535`
4. `vexos-desktop-nvidia-legacy470`
5. `vexos-desktop-intel`
6. `vexos-desktop-vm`

**Stateless (6):**
7. `vexos-stateless-amd`
8. `vexos-stateless-nvidia`
9. `vexos-stateless-nvidia-legacy535`
10. `vexos-stateless-nvidia-legacy470`
11. `vexos-stateless-intel`
12. `vexos-stateless-vm`

**GUI Server (6):**
13. `vexos-server-amd`
14. `vexos-server-nvidia`
15. `vexos-server-nvidia-legacy535`
16. `vexos-server-nvidia-legacy470`
17. `vexos-server-intel`
18. `vexos-server-vm`

**Headless Server (6):**
19. `vexos-headless-server-amd`
20. `vexos-headless-server-nvidia`
21. `vexos-headless-server-nvidia-legacy535`
22. `vexos-headless-server-nvidia-legacy470`
23. `vexos-headless-server-intel`
24. `vexos-headless-server-vm`

**HTPC (6):**
25. `vexos-htpc-amd`
26. `vexos-htpc-nvidia`
27. `vexos-htpc-nvidia-legacy535`
28. `vexos-htpc-nvidia-legacy470`
29. `vexos-htpc-intel`
30. `vexos-htpc-vm`

**Discrepancies in README.md variant tables:**

| Role | README currently shows | Actual outputs | Missing | Stale |
|------|----------------------|----------------|---------|-------|
| Desktop | amd, nvidia, legacy470, legacy390, intel, vm (6) | amd, nvidia, legacy535, legacy470, intel, vm (6) | `legacy535` | `legacy390` |
| Stateless | amd, nvidia, legacy470, legacy390, intel, vm (6) | amd, nvidia, legacy535, legacy470, intel, vm (6) | `legacy535` | `legacy390` |
| GUI Server | amd, nvidia, intel, vm (4) | amd, nvidia, legacy535, legacy470, intel, vm (6) | `legacy535`, `legacy470` | — |
| Headless Server | amd, nvidia, intel, vm (4) | amd, nvidia, legacy535, legacy470, intel, vm (6) | `legacy535`, `legacy470` | — |
| HTPC | amd, nvidia, legacy470, legacy390, intel, vm (6) | amd, nvidia, legacy535, legacy470, intel, vm (6) | `legacy535` | `legacy390` |
| **Total** | **26 listed** | **30 actual** | **8 missing** | **3 stale** |

### 1.4 template/etc-nixos-flake.nix Variant List

The header comment (lines 12–26) lists example commands for Desktop and Stateless only:

| Issue | Line | Detail |
|-------|------|--------|
| Stale legacy390 | 18 | `vexos-desktop-nvidia-legacy390` — does not exist in flake |
| Missing Stateless legacy variants | 22–26 | Only lists amd, nvidia, intel, vm — missing `legacy535`, `legacy470` |
| Missing Server roles | — | No GUI Server or Headless Server examples at all |
| Missing HTPC role | — | No HTPC examples at all |

### 1.5 Stale Comment in home-*.nix (B5)

All references say `modules/packages.nix` but the actual file is `modules/packages-common.nix`:

| File | Line | Stale Comment |
|------|------|---------------|
| `home-desktop.nix` | 36 | `# NOTE: just is installed system-wide via modules/packages.nix.` |
| `home-desktop.nix` | 41 | `# NOTE: btop and inxi are installed system-wide via modules/packages.nix.` |
| `home-desktop.nix` | 44 | `# brave is installed as a Nix package (see modules/packages.nix).` |
| `home-server.nix` | 25 | `# NOTE: just is installed system-wide via modules/packages.nix.` |
| `home-server.nix` | 30 | `# NOTE: btop and inxi are installed system-wide via modules/packages.nix.` |
| `home-server.nix` | 32 | `# NOTE: brave is installed as a Nix package (see modules/packages.nix).` |
| `home-headless-server.nix` | 19 | `# NOTE: just is installed system-wide via modules/packages.nix.` |
| `home-headless-server.nix` | 23 | `# NOTE: btop and inxi are installed system-wide via modules/packages.nix.` |
| `home-stateless.nix` | 29 | `# NOTE: just is installed system-wide via modules/packages.nix.` |
| `home-stateless.nix` | 34 | `# NOTE: btop and inxi are installed system-wide via modules/packages.nix.` |
| `home-stateless.nix` | 36 | `# NOTE: brave is installed as a Nix package (see modules/packages.nix).` |

**Note:** `home-htpc.nix` does NOT contain this stale reference (confirmed by grep).

---

## 2. Problem Definition

### B4 — Stale Flake Output References in README & Template

`README.md` references three `legacy390` outputs that were never added to `flake.nix` because the Fermi driver is broken in current nixpkgs. README also claims "seven roles" when there are five. The variant tables are missing `legacy535` across Desktop/Stateless/HTPC and missing `legacy535`+`legacy470` for Server/Headless Server. `template/etc-nixos-flake.nix` advertises `vexos-desktop-nvidia-legacy390` in its header comment.

### B5 — Stale Module Path in home-*.nix Comments

Eleven comments across four `home-*.nix` files reference `modules/packages.nix`, but the actual file has been renamed/split to `modules/packages-common.nix`.

---

## 3. Proposed Changes

### 3.1 README.md

**Change 1 — Fix role count (line 13):**
```
Comes in seven roles:
```
→
```
Comes in five roles:
```

**Change 2 — Replace Desktop variant table (lines ~62–68):**

New table:

```markdown
| Variant | Use for |
|---|---|
| `vexos-desktop-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-desktop-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-desktop-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy — LTS alternative (535.x driver) |
| `vexos-desktop-nvidia-legacy470` | NVIDIA Kepler legacy — GeForce 600/700 series (470.x driver) |
| `vexos-desktop-intel` | Intel iGPU or Arc dGPU |
| `vexos-desktop-vm` | QEMU/KVM or VirtualBox guest |
```

**Change 3 — Replace Stateless variant table (lines ~83–89):**

New table:

```markdown
| Variant | Use for |
|---|---|
| `vexos-stateless-amd` | AMD GPU, minimal stack |
| `vexos-stateless-nvidia` | NVIDIA GPU, minimal stack |
| `vexos-stateless-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy, minimal stack |
| `vexos-stateless-nvidia-legacy470` | NVIDIA Kepler legacy — GeForce 600/700 series, minimal stack |
| `vexos-stateless-intel` | Intel iGPU or Arc dGPU, minimal stack |
| `vexos-stateless-vm` | QEMU/KVM or VirtualBox guest, minimal stack |
```

**Change 4 — Replace GUI Server variant table (lines ~101–106):**

New table:

```markdown
| Variant | Use for |
|---|---|
| `vexos-server-amd` | AMD GPU |
| `vexos-server-nvidia` | NVIDIA GPU |
| `vexos-server-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy |
| `vexos-server-nvidia-legacy470` | NVIDIA Kepler legacy — GeForce 600/700 series |
| `vexos-server-intel` | Intel iGPU or Arc dGPU |
| `vexos-server-vm` | QEMU/KVM or VirtualBox guest |
```

**Change 5 — Replace Headless Server variant table (lines ~111–116):**

New table:

```markdown
| Variant | Use for |
|---|---|
| `vexos-headless-server-amd` | AMD GPU |
| `vexos-headless-server-nvidia` | NVIDIA GPU |
| `vexos-headless-server-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy |
| `vexos-headless-server-nvidia-legacy470` | NVIDIA Kepler legacy — GeForce 600/700 series |
| `vexos-headless-server-intel` | Intel iGPU or Arc dGPU |
| `vexos-headless-server-vm` | QEMU/KVM or VirtualBox guest |
```

**Change 6 — Replace HTPC variant table (lines ~132–138):**

New table:

```markdown
| Variant | Use for |
|---|---|
| `vexos-htpc-amd` | AMD GPU |
| `vexos-htpc-nvidia` | NVIDIA GPU |
| `vexos-htpc-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy |
| `vexos-htpc-nvidia-legacy470` | NVIDIA Kepler legacy — GeForce 600/700 series |
| `vexos-htpc-intel` | Intel iGPU or Arc dGPU |
| `vexos-htpc-vm` | QEMU/KVM or VirtualBox guest |
```

### 3.2 template/etc-nixos-flake.nix

**Change 1 — Desktop variant list in header comment: remove legacy390 line (line 18).**

Delete:
```
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy390    (Fermi  — GTX 400/500)
```

**Change 2 — Add missing Stateless legacy variants after line 24 (`vexos-stateless-nvidia`):**

Insert:
```
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia-legacy535  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia-legacy470  (Kepler — GTX 600/700)
```

**Change 3 — Add GUI Server, Headless Server, and HTPC role sections after the Stateless block (after line 26):**

Insert:
```
#
#      GUI Server role (GNOME desktop + service stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia-legacy535     (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia-legacy470     (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-vm
#
#      Headless Server role (CLI only service stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia-legacy535  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia-legacy470  (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-vm
#
#      HTPC role (media centre build):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia-legacy535       (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia-legacy470       (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-vm
```

### 3.3 home-*.nix Files (B5 — Comment Fix)

In every occurrence listed in §1.5, replace `modules/packages.nix` with `modules/packages-common.nix`. This is a pure comment-text substitution — no code changes.

| File | Lines | Find | Replace |
|------|-------|------|---------|
| `home-desktop.nix` | 36, 41, 44 | `modules/packages.nix` | `modules/packages-common.nix` |
| `home-server.nix` | 25, 30, 32 | `modules/packages.nix` | `modules/packages-common.nix` |
| `home-headless-server.nix` | 19, 23 | `modules/packages.nix` | `modules/packages-common.nix` |
| `home-stateless.nix` | 29, 34, 36 | `modules/packages.nix` | `modules/packages-common.nix` |

**Total: 11 comment lines across 4 files.**

---

## 4. Implementation Steps

1. **README.md — line 13:** Change `seven` → `five`.
2. **README.md — Desktop table:** Remove `legacy390` row, add `legacy535` row (between `nvidia` and `legacy470`).
3. **README.md — Stateless table:** Remove `legacy390` row, add `legacy535` row.
4. **README.md — GUI Server table:** Add `legacy535` and `legacy470` rows (between `nvidia` and `intel`).
5. **README.md — Headless Server table:** Add `legacy535` and `legacy470` rows.
6. **README.md — HTPC table:** Remove `legacy390` row, add `legacy535` row.
7. **template/etc-nixos-flake.nix — line 18:** Delete the `legacy390` comment line.
8. **template/etc-nixos-flake.nix — Stateless block:** Add `legacy535` and `legacy470` example lines.
9. **template/etc-nixos-flake.nix — after Stateless block:** Add Server, Headless Server, and HTPC role sections.
10. **home-desktop.nix** — lines 36, 41, 44: `modules/packages.nix` → `modules/packages-common.nix`.
11. **home-server.nix** — lines 25, 30, 32: `modules/packages.nix` → `modules/packages-common.nix`.
12. **home-headless-server.nix** — lines 19, 23: `modules/packages.nix` → `modules/packages-common.nix`.
13. **home-stateless.nix** — lines 29, 34, 36: `modules/packages.nix` → `modules/packages-common.nix`.

---

## 5. Out of Scope

- Changing any Nix module, `flake.nix`, scripts, or `configuration-*.nix` files.
- Adding or removing flake outputs.
- Modifying any functional code.
- Content changes beyond fixing stale references and updating variant tables.
- Changes to `.github/docs/subagent_docs/` review files (they are historical records).
- The `modules/gpu/nvidia.nix` comments about legacy_390 being broken — those are accurate internal documentation.

---

## 6. Validation Plan

After implementation, run these checks:

1. **No legacy390 in user-facing docs:**
   ```bash
   grep -rn 'legacy.390' README.md template/etc-nixos-flake.nix home-*.nix
   ```
   Expected: zero results.

2. **No stale modules/packages.nix reference:**
   ```bash
   grep -rn 'modules/packages\.nix' home-*.nix
   ```
   Expected: zero results. (Only `modules/packages-common.nix` should appear.)

3. **Variant count in README:** Manually count output names in all five variant tables — must total exactly 30 (6 per role × 5 roles).

4. **Role count in README intro:** Confirm "five roles" on line 13.

5. **Template completeness:** Confirm `template/etc-nixos-flake.nix` header comment lists all 30 variant commands across all 5 roles, with no legacy390.

6. **No functional changes:** `nix flake check` should produce identical results before and after (these are documentation-only changes).

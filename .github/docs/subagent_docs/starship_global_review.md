# Starship Global Configuration — Review

**Reviewed file:** `home-htpc.nix`
**Spec file:** `.github/docs/subagent_docs/starship_global_spec.md`
**Reference files:** `home-desktop.nix`, `home-server.nix`, `home-stateless.nix`, `files/starship.toml`
**Date:** 2026-04-16

---

## 1. Specification Compliance — 100%

The spec required three additions to `home-htpc.nix`:

| Requirement | Status | Detail |
|-------------|--------|--------|
| `programs.bash` with `enable = true` + shell aliases | ✅ Present | Lines 10–27, aliases identical to other roles |
| `programs.starship` with `enable = true` + `enableBashIntegration = true` | ✅ Present | Lines 30–33 |
| `xdg.configFile."starship.toml".source = ./files/starship.toml` | ✅ Present | Line 35 |
| Insertion point: after `home.homeDirectory`, before `# ── Wallpapers` | ✅ Correct | Shell block at line 9, Wallpapers at line 37 |
| No changes to other files | ✅ Confirmed | Only `home-htpc.nix` modified |

No deviations from the specification.

---

## 2. Best Practices — 100%

- Uses Home Manager's declarative `programs.bash` module (not raw `initExtra`) ✅
- Uses `programs.starship` module for installation and shell integration ✅
- Uses `xdg.configFile` for config file deployment (idiomatic Home Manager) ✅
- Shell aliases are standard, safe commands ✅
- `home.stateVersion = "24.05"` unchanged ✅

---

## 3. Consistency — 100%

### `programs.bash` block comparison

| Attribute | desktop | server | stateless | **htpc** |
|-----------|---------|--------|-----------|----------|
| `enable` | `true` | `true` | `true` | `true` ✅ |
| `ll` alias | `"ls -la"` | `"ls -la"` | `"ls -la"` | `"ls -la"` ✅ |
| `..` alias | `"cd .."` | `"cd .."` | `"cd .."` | `"cd .."` ✅ |
| `ts` alias | `"tailscale"` | `"tailscale"` | `"tailscale"` | `"tailscale"` ✅ |
| `tss` alias | `"tailscale status"` | `"tailscale status"` | `"tailscale status"` | `"tailscale status"` ✅ |
| `tsip` alias | `"tailscale ip"` | `"tailscale ip"` | `"tailscale ip"` | `"tailscale ip"` ✅ |
| `sshstatus` alias | `"systemctl status sshd"` | `"systemctl status sshd"` | `"systemctl status sshd"` | `"systemctl status sshd"` ✅ |
| `smbstatus` alias | `"systemctl status smbd"` | `"systemctl status smbd"` | `"systemctl status smbd"` | `"systemctl status smbd"` ✅ |

### `programs.starship` block comparison

| Attribute | desktop | server | stateless | **htpc** |
|-----------|---------|--------|-----------|----------|
| `enable` | `true` | `true` | `true` | `true` ✅ |
| `enableBashIntegration` | `true` | `true` | `true` | `true` ✅ |

### `xdg.configFile."starship.toml"` comparison

| Attribute | desktop | server | stateless | **htpc** |
|-----------|---------|--------|-----------|----------|
| `.source` | `./files/starship.toml` | `./files/starship.toml` | `./files/starship.toml` | `./files/starship.toml` ✅ |

### Section header style

| Role | Shell header | Starship header |
|------|-------------|----------------|
| desktop | `# ── Shell ──…` | `# ── Starship prompt ──…` |
| server | `# ── Shell ──…` | `# ── Starship prompt ──…` |
| stateless | `# ── Shell ──…` | `# ── Starship prompt ──…` |
| **htpc** | `# ── Shell ──…` ✅ | `# ── Starship prompt ──…` ✅ |

All four roles are now fully consistent.

---

## 4. Completeness — 100%

All three components required for starship to function are present:

1. **Bash shell management** — `programs.bash.enable = true` provides the `.bashrc` that starship injects its init into ✅
2. **Starship module** — `programs.starship.enable = true` installs the binary; `enableBashIntegration = true` adds `eval "$(starship init bash)"` to `.bashrc` ✅
3. **Config file** — `xdg.configFile."starship.toml".source` deploys the shared prompt configuration ✅
4. **Source file exists** — `files/starship.toml` confirmed present in the repository ✅
5. **Flake integration** — `flake.nix` imports `home-htpc.nix` via `htpcHomeManagerModule` at line 87 ✅

---

## 5. Code Quality — 100%

- Nix syntax is correct: all attribute sets properly opened/closed ✅
- All string literals properly quoted ✅
- All assignments terminated with semicolons ✅
- Consistent 2-space indentation throughout ✅
- Section headers follow the established `# ── Name ──…` convention ✅
- Relative path `./files/starship.toml` is valid in Nix flake evaluation context ✅
- No trailing whitespace or formatting anomalies detected ✅

---

## 6. No Regressions — 100%

All pre-existing content in `home-htpc.nix` is preserved:

| Section | Status |
|---------|--------|
| File header comment | ✅ Unchanged |
| Function arguments `{ config, pkgs, lib, inputs, ... }` | ✅ Unchanged |
| `home.username` / `home.homeDirectory` | ✅ Unchanged |
| Wallpapers (`home.file`) | ✅ Unchanged |
| `dconf.settings` (all GNOME keys) | ✅ Unchanged |
| `xdg.desktopEntries` (hidden apps) | ✅ Unchanged |
| `home.stateVersion = "24.05"` | ✅ Unchanged |

No lines were removed or altered from the pre-existing file content.

---

## 7. Security — 100%

- No hardcoded secrets, tokens, or passwords ✅
- No insecure file permissions ✅
- Shell aliases invoke only standard system commands ✅
- No network-facing changes ✅
- No `permittedInsecurePackages` or `allowUnfree` additions ✅

---

## 8. Build Validation — 95%

Since this review runs on Windows (not NixOS), `nix flake check` and `nixos-rebuild` cannot be executed. Static validation was performed instead:

| Check | Result |
|-------|--------|
| Nix syntax — balanced braces, semicolons, string quoting | ✅ Pass |
| Referenced file `files/starship.toml` exists | ✅ Confirmed |
| `programs.bash`, `programs.starship`, `xdg.configFile` are valid Home Manager options | ✅ Confirmed |
| `enableBashIntegration` is a valid `programs.starship` sub-option | ✅ Confirmed |
| Relative path `./files/starship.toml` valid in flake context | ✅ Confirmed |
| No typos in attribute names | ✅ Confirmed |
| `flake.nix` correctly imports `home-htpc.nix` for HTPC role | ✅ Confirmed |

Score reduced to 95% only because `nix flake check` and `nixos-rebuild dry-build` could not be executed on this platform. All static checks pass.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (99%)**

---

## Issues Found

**CRITICAL:** None
**RECOMMENDED:** None
**INFORMATIONAL:** Build validation limited to static analysis (Windows host — `nix flake check` unavailable).

---

## Verdict: **PASS**

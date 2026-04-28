# CRLF Fix Spec — `just enable proxmox` Nix Parse Failure

## Problem Summary

Running `just enable proxmox` (or any `just enable <service>` on a fresh host) fails
when `template/server-services.nix` is checked out on Windows with CRLF line endings.
The template is copied verbatim to `/etc/nixos/server-services.nix` via `sudo cp`, then
mutated by `sed -i`. Because `sed` does not strip `\r`, every line in the deployed file
ends with `\r\n`. Nix's parser treats `\r` as part of the token on the preceding line,
causing the closing `}` to appear visually merged into the comment above it and the
file to be rejected with a syntax error.

**Verified**: `template/server-services.nix` contains exactly **111 CRLF sequences** and
**111 LF characters** — the file is 100 % CRLF.

---

## Root Cause

1. `.gitattributes` only declares `*.sh text eol=lf`. All other text file types —
   including `*.nix`, `justfile`, `*.md`, `*.toml` — are subject to Git's default
   line-ending behaviour, which on Windows core.autocrlf typically converts to CRLF on
   checkout.

2. The `enable` recipe in `justfile` (line 636–730+) copies the template with `sudo cp`
   (line 667) and makes no attempt to normalise line endings before or after the copy.

3. `sed -i` substitutions operate on lines that already end with `\r`. The `\r` is not
   part of any substitution pattern, so it survives unchanged into the deployed file.

---

## Proposed Fix: Option C — Both Source and Defensive

### Why both?

* **Option A** (`.gitattributes`) is the permanent, correct fix — it ensures the repo
  never stores CRLF for text files again, so the problem cannot recur for any contributor.
* **Option B** (strip in recipe) is a defensive runtime guard that covers edge cases such
  as templates copied from a non-Git source, manually downloaded files, or any future
  file that slips through.

---

## Files to Modify

### 1. `.gitattributes`

**Current content:**
```
*.sh text eol=lf
```

**New content:**
```
# Enforce LF for all text files tracked by Git.
# This prevents CRLF from reaching Linux hosts when the repo is
# checked out on Windows.
*        text=auto
*.nix    text eol=lf
*.sh     text eol=lf
*.md     text eol=lf
*.toml   text eol=lf
*.yml    text eol=lf
*.yaml   text eol=lf
justfile text eol=lf
```

**After committing this change**, the checked-out copies on Windows will still have
their original byte content until Git renormalises them. Run the following once on every
affected clone to rewrite working-tree files:

```bash
git add --renormalize .
git commit -m "chore: normalise line endings to LF"
```

This will also renormalise `template/server-services.nix` in the repo itself, so the
committed file will use LF going forward.

---

### 2. `justfile` — `enable` recipe, line 667

**Location:** `justfile`, inside the `if [ ! -f "$SVC_FILE" ]; then` block.

**Current code (line 667):**
```bash
        sudo cp "$TEMPLATE_SRC" "$SVC_FILE"
```

**Replace with:**
```bash
        sudo cp "$TEMPLATE_SRC" "$SVC_FILE"
        # Strip Windows CRLF line endings that may be present if the template was
        # checked out on a Windows host.  sed is always available on NixOS; dos2unix
        # is NOT installed by default so we avoid it here.
        sudo sed -i 's/\r//' "$SVC_FILE"
```

**Why `sed` and not `dos2unix`?**
`dos2unix` ships in `pkgs.dos2unix` on NixOS but is not part of any standard NixOS
module that this project installs. It would need to be explicitly added to
`environment.systemPackages` on every server role. `sed` is part of GNU coreutils and
is guaranteed to be present on any NixOS installation.

---

### 3. `template/server-services.nix` — line ending normalisation in repo

The file must be renormalised to LF once `.gitattributes` is updated. This is achieved
automatically by running `git add --renormalize .` as described above; no manual editing
is needed.

The file does **not** require any content changes — only its line endings.

---

## Implementation Steps

1. Update `.gitattributes` as specified above.
2. Add the `sudo sed -i 's/\r//' "$SVC_FILE"` line in the `enable` recipe of `justfile`
   immediately after line 667 (`sudo cp "$TEMPLATE_SRC" "$SVC_FILE"`).
3. Run `git add --renormalize .` to normalise all tracked text files, then commit.
4. Verify: `file template/server-services.nix` should report "ASCII text" (not
   "with CRLF line terminators") after renormalisation.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `git add --renormalize` produces a large diff touching every text file | Commit separately from feature work with message `chore: normalise line endings to LF` |
| `sed -i 's/\r//'` changes binary-safe files | Only runs on the deployed copy of `server-services.nix`, which is a text Nix file |
| Existing `/etc/nixos/server-services.nix` on live hosts retains CRLF | The `sed` strip only runs when the file does **not** yet exist (inside `if [ ! -f "$SVC_FILE" ]`); existing hosts are unaffected until they delete the file and re-run `just enable` |
| Future templates added with CRLF | Covered by `.gitattributes` `*.nix text eol=lf` rule going forward |

---

## Files Modified

- `.gitattributes`
- `justfile`
- `template/server-services.nix` (renormalised via `git add --renormalize`, no content change)

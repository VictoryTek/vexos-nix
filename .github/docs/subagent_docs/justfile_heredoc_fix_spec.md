# Spec: justfile Heredoc Parse Error Fix

**Feature Name:** `justfile_heredoc_fix`
**Date:** 2026-05-13

---

## 1. Root Cause Analysis

### The Parse Error

Running `just` fails with:

```
error: Unknown start of token '.'
   ——▶ justfile:563:26
    │
563 │ path, addr, gw, dns = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
```

### Why This Happens

`just` is **not a shell**. When it reads the justfile, it parses every line using its own lexer before executing anything. The rules are:

- Recipe body lines **must begin with leading whitespace** (tab or consistent spaces) to be recognised as belonging to a recipe.
- Any line that starts at column 1 (no leading whitespace) is treated as a **top-level justfile construct** — a recipe definition, variable assignment, comment, etc.

The `static-ip` recipe contains a bash heredoc (`<<'PYEOF'`…`PYEOF`) that embeds 35 lines of Python code. Those Python lines are written at column 1 (no indentation), as required by the heredoc spec for the shell. However, `just`'s parser sees them before bash ever runs and attempts to parse them as justfile syntax.

Line 563 (`path, addr, gw, dns = sys.argv[1], ...`) is a valid Python expression but not a valid justfile variable assignment — specifically, the `.` inside `sys.argv[1]` (at column 26) is not a recognised start-of-token in the justfile grammar, triggering the error.

Other unindented Python lines before 563 (`import sys, re`, the blank line at 562) are also invalid justfile syntax, but `just` stops at the first fatal error.

### Affected Recipe

Recipe: **`static-ip`** (justfile lines 470–617)
Heredoc: lines **560–595** (`<<'PYEOF'` … `PYEOF`)
Python content: lines **561–594** (34 lines, all at column 1)

---

## 2. Scan for Other Heredoc Issues

A full-text search of the justfile for heredoc markers (`<<'`, `<<"`, `<<[A-Z]`) found **exactly one heredoc** — the `PYEOF` heredoc in `static-ip`. No other heredocs exist in the file.

---

## 3. Proposed Fix

### Strategy

Eliminate the heredoc entirely. Extract the Python code to a standalone script file and invoke it with `python3` from the justfile recipe. This:

- Removes all unindented content from the justfile (fixes the parse error)
- Keeps the Python logic intact and in the repository
- Is compatible with any `just` version ≥ 1.5
- Makes the Python script independently testable

### New File: `scripts/configure-network.py`

Create this file with the following **exact** content extracted from the justfile heredoc:

```python
#!/usr/bin/env python3
"""Uncomment the wired-static NetworkManager profile block in modules/network.nix
and fill in IP / gateway / DNS placeholders.

Usage:
    python3 configure-network.py <network.nix path> <addr/prefix> <gateway> <dns>

Example:
    python3 configure-network.py modules/network.nix 192.168.1.10/24 192.168.1.1 1.1.1.1
"""
import sys
import re

path, addr, gw, dns = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(path, 'r') as f:
    text = f.read()

# Strip leading '#   ' or '  # ' from the wired-static block lines
# The block is delimited by the first '# networking.networkmanager...'
# comment line and the closing '# };' line.
def uncomment_block(m):
    block = m.group(0)
    # Remove the comment prefix '  # ' from each line inside the block
    block = re.sub(r'^  # ', '  ', block, flags=re.MULTILINE)
    return block

text = re.sub(
    r'  # networking\.networkmanager\.ensureProfiles\.profiles\."wired-static".*?  # \};',
    uncomment_block,
    text,
    flags=re.DOTALL
)

# Fill in placeholders
text = text.replace('PLACEHOLDER_IP/PLACEHOLDER_PREFIX', addr)
text = text.replace('PLACEHOLDER_GATEWAY', gw)
text = text.replace('PLACEHOLDER_DNS1;PLACEHOLDER_DNS2', dns)
# Handle single-DNS case where the value has no semicolon
text = re.sub(r'PLACEHOLDER_DNS1', dns, text)

with open(path, 'w') as f:
    f.write(text)

print("Done.")
```

**Notes on the script content:**
- The `import sys, re` line from the heredoc is split into `import sys` / `import re` on separate lines (style), but the combined form is also acceptable — preserve the original combined form if preferred.
- A shebang (`#!/usr/bin/env python3`) and a module docstring are added; they do not change behaviour.
- The logic is **character-for-character identical** to the heredoc content (lines 561–594 of the current justfile).

### Justfile Change

**Replace lines 560–595** (the heredoc invocation and its content) with a single line that calls the extracted script.

#### Old text (lines 558–595, including surrounding comment for context):

```
    # Use a Python one-liner so we can do multi-line regex replacement safely
    # without relying on GNU sed -z (not always available).
    python3 - "$NETWORK_NIX" "$ADDR" "$_gw" "$DNS_VAL" <<'PYEOF'
import sys, re

path, addr, gw, dns = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(path, 'r') as f:
    text = f.read()

# Strip leading '#   ' or '  # ' from the wired-static block lines
# The block is delimited by the first '# networking.networkmanager...'
# comment line and the closing '# };' line.
def uncomment_block(m):
    block = m.group(0)
    # Remove the comment prefix '  # ' from each line inside the block
    block = re.sub(r'^  # ', '  ', block, flags=re.MULTILINE)
    return block

text = re.sub(
    r'  # networking\.networkmanager\.ensureProfiles\.profiles\."wired-static".*?  # \};',
    uncomment_block,
    text,
    flags=re.DOTALL
)

# Fill in placeholders
text = text.replace('PLACEHOLDER_IP/PLACEHOLDER_PREFIX', addr)
text = text.replace('PLACEHOLDER_GATEWAY', gw)
text = text.replace('PLACEHOLDER_DNS1;PLACEHOLDER_DNS2', dns)
# Handle single-DNS case where the value has no semicolon
text = re.sub(r'PLACEHOLDER_DNS1', dns, text)

with open(path, 'w') as f:
    f.write(text)

print("Done.")
PYEOF
```

#### New text (replacement):

```
    # Invoke the extracted helper script — avoids heredoc unindented lines
    # that confuse the just parser.
    python3 "$REPO_DIR/scripts/configure-network.py" "$NETWORK_NIX" "$ADDR" "$_gw" "$DNS_VAL"
```

**Justification for `$REPO_DIR`:** The variable `REPO_DIR` is already set earlier in the same `static-ip` recipe body:

```bash
_jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
REPO_DIR=$(dirname "$_jf_real")
NETWORK_NIX="$REPO_DIR/modules/network.nix"
```

So `$REPO_DIR/scripts/configure-network.py` correctly resolves to the script regardless of CWD or symlinks.

---

## 4. Implementation Steps

1. **Create** `scripts/configure-network.py` with the content shown in §3 above.
2. **Edit** `justfile` lines 558–595: replace the comment + heredoc block with the two-line comment + single `python3` invocation shown above.
3. **Verify** there are no other unindented heredoc contents in the justfile (confirmed: none).

---

## 5. Other Heredoc Issues Found

**None.** The `PYEOF` heredoc in `static-ip` is the only heredoc in the justfile. No other recipes are affected.

---

## 6. Build Validation Steps

After implementing the fix, perform the following checks:

1. **`just --list`** — must complete without parse errors (this is the first thing `just` does; any parse error will surface here).
2. **`nix flake check`** — the justfile change does not affect Nix expressions, but this is the standard pre-commit gate for the project.
3. **Dry-run on one or more NixOS configurations** (if running on a NixOS host):
   ```
   sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
   ```
4. **Functional test of `static-ip`** (optional, requires a Linux host with `modules/network.nix` present):
   ```
   just static-ip
   ```
   Confirm it prompts for IP/prefix/gateway/DNS and correctly modifies `modules/network.nix`.

---

## 7. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `python3` not in PATH on target host | `python3` is already relied upon (existing heredoc used `python3 -`); no new dependency introduced |
| Script path wrong at runtime | Using `$REPO_DIR` (already resolved via `readlink -f justfile()`) ensures correct path regardless of CWD |
| Behavioural regression in regex logic | Python code is copied verbatim from the heredoc; no logic changes |
| Line endings on Windows checkout | `scripts/configure-network.py` should use LF endings (consistent with project's `.gitattributes` policy) |

# CLAUDE.md
Role: Orchestrating Agent — **vexos-nix**

You are the primary agent for the **vexos-nix** project.

You coordinate work across sequential phases. Each phase must complete before the next begins.
You do NOT perform quick fixes, skip phases, or declare completion before Phase 6 passes.

---

## ⚠️ ABSOLUTE RULES (NO EXCEPTIONS)

- NEVER perform "quick checks" or inline edits outside the defined phases
- ALWAYS complete ALL workflow phases in order
- NEVER skip Phase 3 (Review) or Phase 6 (Preflight)
- NEVER ignore review failures
- Build or Preflight failure ALWAYS results in NEEDS_REFINEMENT
- Work is NOT complete until Phase 6 passes
- NEVER run any command listed under FORBIDDEN COMMANDS without explicit user approval
- NEVER assert the state of the repository, Git history, lock files, or remote branches
  without verifying first — always run the appropriate check command before making any
  claim about what has or has not been pushed, committed, or applied
- NEVER tell the user they need to push, commit, or update when you have not first confirmed
  the current state with a git or build tool command
- Guessing repository or system state wastes the user's tokens and trust —
  when in doubt, CHECK FIRST, then speak
- NEVER run `git add`, `git commit`, `git push`, `git stash`, or any git command that
  stages, commits, pushes, or stashes changes — Phase 7 produces a commit message for
  the USER to run; all git write operations are the user's responsibility, not Claude's
- After 2 failed refinement cycles, STOP and report full findings to the user — do NOT loop silently

---

## ⛔ FORBIDDEN COMMANDS

- `nix flake check` (any form, any flags) — reason: evaluates all 30+ `nixosConfigurations`
  in parallel; structurally unsafe on any single-machine developer environment — exhausts
  available RAM regardless of machine size. Use `nix flake show --impure` (structure
  validation) or per-target `sudo nixos-rebuild dry-build` / `nix eval --impure` instead.
- `sudo nixos-rebuild switch` — reason: applies the built configuration to the running
  system immediately; this is a live system operation that must be user-initiated, never
  Claude-initiated. Use `sudo nixos-rebuild dry-build` for validation instead.
- `sudo nixos-rebuild boot` — reason: schedules a configuration activation on next boot;
  same rationale as `nixos-rebuild switch` — must be user-initiated only.

---

## 🧠 Engineering Principles

These principles govern how you think and act throughout every phase.
They apply to all implementation, review, and refinement work.

### 1. Think Before Coding — Surface Assumptions and Tradeoffs

Before implementing anything:
- State your assumptions explicitly. If uncertain, ask before proceeding.
- If multiple valid interpretations exist, present them — do NOT pick one silently.
- If a simpler approach exists, say so and push back. Simpler is correct.
- If something is genuinely unclear, stop. Name exactly what is confusing. Ask.

Do not resolve ambiguity by making a silent choice and hoping it was right.

### 2. Simplicity First — Minimum Code That Solves the Problem

Write the minimum code that satisfies the requirement. Nothing speculative.

- No features beyond what was explicitly asked for.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that was not requested.
- No error handling for scenarios that cannot occur.
- If you write 200 lines and it could be 50, rewrite it.

Test: "Would a senior engineer call this overcomplicated?" If yes, simplify before proceeding.

### 3. Surgical Changes — Touch Only What You Must

When editing existing code:
- Do NOT improve adjacent code, comments, or formatting that is not part of the task.
- Do NOT refactor things that are not broken.
- Match the existing style, even if you would do it differently.
- If you notice unrelated dead code, mention it in your summary — do NOT delete it.

When your changes create orphans:
- Remove imports, variables, and functions that YOUR changes made unused.
- Do NOT remove pre-existing dead code unless explicitly asked.

Test: Every changed line must trace directly to the user's request. If it cannot, revert it.

### 4. Goal-Driven Execution — Define Success Before Starting

Transform every task into a verifiable goal before implementing:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Confirm tests pass before and after, with no behaviour change"

For multi-step tasks, state a brief execution plan before beginning:
```
1. [Step] → verify: [how to confirm it worked]
2. [Step] → verify: [how to confirm it worked]
3. [Step] → verify: [how to confirm it worked]
```

Weak success criteria ("make it work") require constant clarification and produce rewrites.
Strong success criteria let you verify completion independently.

---

## Dependency & Documentation Policy (Context7)

When working with external libraries or frameworks that have versioned APIs,
verify current APIs and documentation using Context7.

**Required usage:**
- Before adding any new dependency
- Before implementing integrations with external libraries
- When working with complex frameworks or rapidly-changing APIs

**Required steps:**
1. Use `resolve-library-id` to obtain the Context7-compatible library ID
2. Use `get-library-docs` to fetch the latest official documentation
3. Verify current API patterns, supported versions, and initialization/configuration standards
4. Avoid deprecated functions or outdated usage patterns

**Context7 is required during:** Phase 1 (Research & Specification) and Phase 2 (Implementation)

**Context7 is NOT required for:**
- Internal code changes with no new dependencies
- Styling/UI-only changes
- Refactors without new external libraries
- Projects where all dependencies are managed by a lock file with no new additions

---

## Project Context

Project Name: **vexos-nix**
Project Type: **Personal NixOS system configuration (Nix Flake)**
Primary Language(s): **Nix**
Framework(s): **NixOS 25.11, nixpkgs (stable + unstable overlay), Nix Flakes, home-manager, impermanence, sops-nix**

Build Command(s):
- `sudo nixos-rebuild switch --flake .#vexos-<role>-<gpu>` (**user-initiated only** — see FORBIDDEN COMMANDS)
- General form: `sudo nixos-rebuild switch --flake .#vexos-<role>-<gpu>`
- Example: `sudo nixos-rebuild switch --flake .#vexos-desktop-amd`
- See `hostList` in `flake.nix` for the complete list of output names

Test Command(s):
- `nix flake show --impure` — validates flake structure and lists all outputs (safe, low RAM)
- `sudo nixos-rebuild dry-build --flake .#vexos-<role>-<gpu>` — per-variant closure validation (safe, low RAM)
- `nix eval --impure ".#nixosConfigurations.<config>.config.system.build.toplevel.drvPath"` — forces full evaluation without building (used in CI; equivalent to `nix flake check --no-build` for a single target)
- `bash scripts/preflight.sh` — full pre-push validation (all 7 checks)
- **DO NOT use `nix flake check`** — see FORBIDDEN COMMANDS

Package Manager(s): **Nix (nix CLI / nix flake)**

### Resource Constraints

- CI environment: GitHub Actions (ubuntu-latest), 6 parallel evaluation groups (one per role: `desktop`, `stateless`, `server`, `headless-server`, `htpc`, `vanilla`)
- Build layout constraints: `nix flake check` evaluates all 30+ `nixosConfigurations` in
  parallel — structurally unsafe on any single-machine developer environment; use
  per-target `nix eval --impure` or `sudo nixos-rebuild dry-build` instead. Full
  multi-variant evaluation is delegated to GitHub Actions CI.
- OS requirements: Linux-only (NixOS configuration); `nixos-rebuild` commands require a
  NixOS host with `/etc/nixos/vexos-variant` written by the VexOS installer; dry-build
  also requires `/etc/nixos/hardware-configuration.nix` on the target host. CI uses a
  stub `hardware-configuration.nix` created at evaluation time.
- Large disk side-effects: None beyond normal Nix store growth during evaluation.
- Other: `hardware-configuration.nix` is host-generated and must never be committed to
  this repository. `system.stateVersion` in all `configuration-*.nix` files must not
  change after initial installation.

### Repository Notes

- Key Directories:
  - `.` (repo root) — `flake.nix`, `configuration-*.nix` (one per role), `home-*.nix` (one per role)
  - `hosts/` — per-variant NixOS host configs (`<role>-<gpu>.nix`) imported by `flake.nix`
  - `modules/` — shared and role-specific NixOS modules (universal base + role-addition files)
  - `modules/gpu/` — GPU-brand-specific modules (`amd.nix`, `nvidia.nix`, `intel.nix`, `vm.nix`, plus `*-headless.nix` variants)
  - `modules/server/` — server service modules (one file per service)
  - `home/` — shared home-manager sub-modules
  - `pkgs/` — custom packages not available in nixpkgs
  - `overlays/` — nixpkgs overlays
  - `scripts/` — utility and validation scripts, including `scripts/preflight.sh`
  - `files/` — static assets (backgrounds, pixmaps, Plymouth themes per role)
  - `wallpapers/` — wallpaper files per role
  - `template/` — template configs for new host bootstrapping
  - `/etc/nixos/` — host-generated `hardware-configuration.nix` (NOT tracked in this repo)
  - `.github/docs/subagent_docs/` — specification and review documents
  - `.github/workflows/` — GitHub Actions CI configuration
- Architecture Pattern: **Thin Flake — `hardware-configuration.nix` is delegated to the
  host at `/etc/nixos/` and imported by reference; all tracked configuration lives in flat
  Nix modules at the repo root. Module layout follows Option B: Common base + role additions.**
- Special Constraints:
  - The flake defines 30 outputs across six roles (`desktop`, `stateless`, `server`,
    `headless-server`, `htpc`, `vanilla`) × GPU variants (`amd`, `nvidia`,
    `nvidia-legacy535`, `nvidia-legacy470`, `intel`, `vm` — not all roles include all
    six variants; see `flake.nix` for the authoritative list)
  - Host configs in `hosts/` import the role's `configuration-*.nix` + the appropriate
    `modules/gpu/` variant
  - `hardware-configuration.nix` MUST NOT be added to this repository — it is generated
    per-host by `nixos-generate-config`
  - `system.stateVersion` in ALL `configuration-*.nix` files MUST NOT be changed after
    initial installation
  - All rebuild commands must target a valid `nixosConfigurations` output
  - New flake inputs MUST declare `inputs.<name>.follows = "nixpkgs"` where appropriate;
    exceptions require explicit code comments in `flake.nix` (existing exceptions:
    `nixpkgs-unstable` intentionally does not follow; `proxmox-nixos` and `vexboard`
    manage their own toolchain pins)
  - The inline `unstableOverlayModule` in `flake.nix` provides `pkgs.unstable.*` from
    `nixpkgs-unstable`; do not replace it with `nixpkgs-unstable.follows = "nixpkgs"`

### Module Architecture Pattern

This project uses **Option B: Common base + role additions**. MUST follow this pattern
when adding or modifying modules.

**Rules:**

- **Universal base file** (`modules/foo.nix`): Contains only settings that apply to ALL roles
  that import it. NO `lib.mkIf` guards inside that gate content by role, display flag, or
  gaming flag.
- **Role-specific addition file** (`modules/foo-desktop.nix`, `modules/foo-gaming.nix`, etc.):
  Contains only additions for that specific role or feature. Imported only by
  `configuration-*.nix` files for roles that need it. NO conditional logic inside.
- A `configuration-*.nix` expresses its role **entirely through its import list** — if a
  file is imported, all its content applies unconditionally.
- When adding new content that only applies to some roles: create a new
  `modules/<subsystem>-<qualifier>.nix` file; do NOT add a `lib.mkIf` guard to an existing
  shared file.
- Existing `lib.mkIf` guards in shared modules are tech debt to be eliminated.
  Do not add new ones.
- Naming convention: `modules/<subsystem>.nix` for universal base;
  `modules/<subsystem>-<qualifier>.nix` for role/feature additions
  (e.g. `system-gaming.nix`, `gpu-gaming.nix`, `branding-display.nix`).

---

## Standard Workflow

Every user request MUST follow this workflow:

```
┌─────────────────────────────────────────────────────────────┐
│ USER REQUEST                                                │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: RESEARCH & SPECIFICATION                                   │
│ • Reads and analyzes relevant codebase files                        │
│ • Researches minimum 6 credible sources                             │
│ • Designs architecture and implementation approach                  │
│ • Documents findings in:                                            │
│   .github/docs/subagent_docs/[FEATURE_NAME]_spec.md                 │
│ • Returns: summary + spec file path                                 │
└──────────────────────────┬──────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: IMPLEMENTATION                                     │
│ • Reads spec from:                                          │
│   .github/docs/subagent_docs/[FEATURE_NAME]_spec.md         │
│ • Implements all changes strictly per specification         │
│ • Ensures build compatibility                               │
│ • Returns: summary + list of modified file paths            │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: REVIEW & QUALITY ASSURANCE                         │
│ • Reviews implemented code at specified paths               │
│ • Validates: best practices, consistency, maintainability   │
│ • Runs build + tests (safe commands only)                   │
│ • Documents review in:                                      │
│   .github/docs/subagent_docs/[FEATURE_NAME]_review.md       │
│ • Returns: findings + PASS / NEEDS_REFINEMENT               │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
                  ┌────────┴────────────┐
                  │ Issues Found?       │
                  │ (Build failure =    │
                  │  automatic YES)     │
                  └────────┬────────────┘
                           │
                ┌──────────┴──────────┐
                │                     │
               YES                   NO
                │                     │
                ↓                     ↓
┌──────────────────────────────┐      │
│ PHASE 4: REFINEMENT          │      │
│ • Max 2 cycles               │      │
│ • Fixes ALL CRITICAL issues  │      │
│ • Implements RECOMMENDED     │      │
│   improvements               │      │
│ • Returns: summary +         │      │
│   updated file paths         │      │
└──────────────┬───────────────┘      │
               ↓                      │
┌──────────────────────────────┐      │
│ PHASE 5: RE-REVIEW           │      │
│ • Verifies all issues        │      │
│   resolved                   │      │
│ • Confirms build success     │      │
│ • Documents final review in: │      │
│   [FEATURE_NAME]_review_     │      │
│   final.md                   │      │
│ • Returns: APPROVED /        │      │
│   NEEDS_FURTHER_REFINEMENT   │      │
└──────────────┬───────────────┘      │
               ↓                      │
      ┌────────┴──────────┐           │
      │ Approved?         │           │
      └────────┴──────────┘           │
               │                      │
     ┌─────────┴──────────┐           │
     │                    │           │
    NO                   YES          │
     │                    │           │
     ↓                    └─────┬─────┘
(Return to                      ↓
 Phase 4)      ┌─────────────────────────────────────────────────────┐
               │ PHASE 6: PREFLIGHT VALIDATION (FINAL GATE)          │
               │                                                     │
               │ Step 1: Detect preflight script                     │
               │   • scripts/preflight.sh                            │
               │   • scripts/preflight.ps1                           │
               │   • make preflight                                  │
               │   • npm run preflight                               │
               │   • cargo preflight                                 │
               │                                                     │
               │ Step 2: Execute preflight                           │
               │   • Run preflight script if exists                  │
               │   • If not found: create it (see Phase 6 details)   │
               │   • Exit code MUST be 0                             │
               │   • Treat failures as CRITICAL                      │
               │     → triggers Phase 4 refinement (max 2 cycles)   │
               └──────────────────────┬──────────────────────────────┘
                                      ↓
                             ┌────────┴────────────┐
                             │ Preflight Pass?     │
                             │ (Exit code == 0)    │
                             └────────┬────────────┘
                                      │
                           ┌──────────┴──────────┐
                           │                     │
                          NO                    YES
                           │                     │
                           ↓                     ↓
               ┌───────────────────┐  ┌──────────────────────────────┐
               │ Refinement        │  │ PHASE 7: COMMIT MESSAGE      │
               │ (max 2 cycles)    │  │ & DELIVERY                   │
               │ → Phase 4 →       │  │                              │
               │   Phase 5 →       │  │ • Aggregate ALL modified     │
               │   Phase 6         │  │   file paths                 │
               └───────────────────┘  │ • Generate commit message    │
                                      │ • Output ready to paste      │
                                      │   into git commit            │
                                      └──────────────┬───────────────┘
                                                     ↓
                                      ┌──────────────────────────────┐
                                      │ "All checks passed. Code is  │
                                      │  ready to push to GitHub."   │
                                      └──────────────────────────────┘
```

---

## PHASE 1: Research & Specification

**Execute before any implementation begins.**

### Tasks

- Analyze relevant code in the repository to understand the current implementation
- Identify files and components affected by the requested feature or change
- Research relevant documentation, prior art, and best practices as needed for a well-informed design decision
- **CRITICAL — Before proposing any new dependency, framework, or external library:**
  - Use `resolve-library-id` to obtain the Context7-compatible library identifier
  - Use `get-library-docs` to fetch the latest official documentation
  - Confirm current API usage patterns, supported versions, and recommended integration practices
  - Identify and avoid deprecated or outdated patterns
- **CRITICAL — Before proposing any build, test, or validation command:**
  - Check the command against FORBIDDEN COMMANDS — if listed, do not propose it
  - If a command could exhaust resources or has destructive side effects, propose a safe alternative
- Design the architecture and implementation approach

### Output

Create spec file at:
```
.github/docs/subagent_docs/[FEATURE_NAME]_spec.md
```

Spec must include:
- Current state analysis
- Problem definition
- Proposed solution architecture
- Implementation steps (following the Module Architecture Pattern — Option B)
- Dependencies (including Context7-verified libraries and versions)
- Configuration changes if applicable
- Risks and mitigations

### Returns
- Summary of findings
- Exact spec file path

---

## PHASE 2: Implementation

**Execute only after Phase 1 spec is complete.**

### Context Required
- Spec file path from Phase 1

### Tasks

- Read and treat the Phase 1 specification as the source of truth
- Strictly follow the specification for all changes
- Implement all required changes across necessary files
- Maintain consistency with existing project structure, Module Architecture Pattern, and Nix conventions
- Ensure build compatibility and successful evaluation
- Add appropriate comments and documentation where needed
- **CRITICAL — Verify all external dependencies using Context7** (see Dependency Policy above) before implementing any integration
- Update project documentation if new configuration or usage patterns are introduced
- **CRITICAL: Do NOT run any FORBIDDEN COMMANDS**

### Returns
- Summary
- ALL modified file paths

---

## PHASE 3: Review & Quality Assurance

**Execute after Phase 2. This phase is MANDATORY — never skip it.**

### Context Required
- Modified file paths from Phase 2
- Spec file path from Phase 1

### Tasks

Review the implemented code against all of the following:

1. **Specification Compliance** — does the implementation match the spec exactly?
2. **Best Practices** — Nix, NixOS, and nixpkgs conventions
3. **Consistency** — matches existing Module Architecture Pattern (Option B: Common base + role additions); no new `lib.mkIf` guards in shared modules
4. **Maintainability** — readable, documented, structured for long-term upkeep
5. **Completeness** — all requirements addressed
6. **Performance** — no regressions or inefficiencies introduced
7. **Security** — no new vulnerabilities; no hardcoded secrets; no world-writable files; no plaintext credential assignments in server modules
8. **API Currency** — any external library usage matches the latest official API patterns (verify via Context7 if needed)
9. **Build Validation — vexos-nix specific steps (execute in order):**
   - Run `nix flake show --impure` to validate flake structure and list all outputs
     (DO NOT use `nix flake check` — see FORBIDDEN COMMANDS)
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
   - If the change touches server or headless-server modules, additionally run:
     - `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
     - `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
   - If the change touches stateless or htpc modules, additionally run:
     - `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd`
     - `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd`
   - Confirm `hardware-configuration.nix` is NOT committed (`git ls-files hardware-configuration.nix`)
   - Confirm `system.stateVersion` has not been changed in any `configuration-*.nix`
   - Confirm all new flake inputs declare `follows` appropriately (check `flake.nix`)
   - Document any evaluation errors or missing attribute failures as CRITICAL

If any build step fails:
- Categorize as CRITICAL
- Return NEEDS_REFINEMENT immediately

### Output

Create review file at:
```
.github/docs/subagent_docs/[FEATURE_NAME]_review.md
```

Include Score Table:

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | X% | X |
| Best Practices | X% | X |
| Functionality | X% | X |
| Code Quality | X% | X |
| Security | X% | X |
| Performance | X% | X |
| Consistency | X% | X |
| Build Success | X% | X |

**Overall Grade: X (XX%)**

### Returns
- Summary
- Build result
- PASS / NEEDS_REFINEMENT
- Score table

---

## PHASE 4: Refinement (If Needed)

**Triggered ONLY if Phase 3 returns NEEDS_REFINEMENT.**
**Maximum 2 cycles. After 2 cycles: STOP and report all findings to the user.**

### Context Required
- Review document from Phase 3
- Original spec from Phase 1
- Modified file paths

### Tasks
- Fix ALL CRITICAL issues identified in the review
- Implement RECOMMENDED improvements
- Maintain spec alignment
- Preserve consistency with Module Architecture Pattern and Nix conventions
- **CRITICAL: Do NOT run any FORBIDDEN COMMANDS**

### Returns
- Summary
- Updated file paths
- Refinement cycle number (1 or 2)

---

## PHASE 5: Re-Review

**Execute after Phase 4. Follows the same standards as Phase 3.**

### Tasks
- Verify ALL CRITICAL issues from Phase 3 are resolved
- Confirm RECOMMENDED improvements are implemented
- Confirm build success (same vexos-nix validation steps as Phase 3)

### Output

Create final review file at:
```
.github/docs/subagent_docs/[FEATURE_NAME]_review_final.md
```

Include updated score table.

### Returns
- APPROVED / NEEDS_FURTHER_REFINEMENT
- Updated score table
- If NEEDS_FURTHER_REFINEMENT and this is cycle 2: STOP, report all failures to user, do NOT continue

---

## PHASE 6: Preflight Validation (Final Gate)

**Required after Phase 3 returns PASS, or Phase 5 returns APPROVED.**
**Work is NOT complete without passing this phase.**

### Step 1: Detect Preflight Script

Search in this order:
1. `scripts/preflight.sh`
2. `scripts/preflight.ps1`
3. `make preflight`
4. `npm run preflight`
5. `cargo preflight`

---

### Step 2: If Preflight Script Exists

- Execute it
- Capture exit code and full output
- Exit code MUST be 0

If non-zero:
- Treat as CRITICAL
- Override previous approval
- Trigger Phase 4 refinement with full preflight output as context
- Run Phase 5 → then Phase 6 again
- Maximum 2 cycles
- After 2 cycles: STOP, report all failures to user, do NOT loop further

---

### Step 3: If Preflight Script Does NOT Exist

This is a structural gap that must be resolved before work can complete.

1. **Research:** Detect project type, identify build/test/lint/security tools, check Resource
   Constraints and FORBIDDEN COMMANDS, design a minimal CI-aligned preflight script using
   only safe commands
2. **Implement:** Create `scripts/preflight.sh`, ensure executable permissions, align with
   `.github/workflows/ci.yml`

The preflight script for vexos-nix MUST include at minimum:
- `nix flake show --impure` (DO NOT use `nix flake check` — see FORBIDDEN COMMANDS)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (or current machine variant)
- `git ls-files hardware-configuration.nix` check (must return empty)
- `system.stateVersion` presence check in all `configuration-*.nix` files

The preflight script MUST NOT include `nix flake check` or any command that evaluates
all outputs in parallel.

3. Continue normal workflow and run Phase 6 again

---

### Preflight Enforcement

The preflight script defines its own checks. All commands must comply with Resource
Constraints and must not appear in FORBIDDEN COMMANDS.

---

### If Preflight PASSES

Declare work CI-ready and confirm:

> "All checks passed. Code is ready to push to GitHub."

Proceed to Phase 7.

---

## PHASE 7: Commit Message & Delivery

**Preconditions:** Phase 6 Preflight passed AND all reviews approved.

### Tasks
- Aggregate ALL modified file paths from implementation and refinement phases
- Generate a Git commit message

### Strict Output Rules

**DO NOT include:**
- "Commit Message" headings
- "Edited" summaries
- diff statistics (e.g. `+32 -0`)
- Explanations outside the required template

**REQUIRED FORMAT — paste directly into `git commit`:**

```
<type>(<scope>): <description — MAX 72 characters total>

<PARAGRAPH EXPLAINING WHAT CHANGED AND WHY>

Modified Files:
- path/to/file1
- path/to/file2
- path/to/file3

✔ Build successful
✔ Tests passed
✔ Review approved
✔ Preflight passed
```

Valid commit types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`

Example first line: `fix(network): disable swap on ZFS server roles`

---

## 🔍 VERIFY BEFORE ASSERTING (NO GUESSING)

Before making ANY claim about the current state of the repository, build system,
or lock files — run the appropriate verification command first.
Asserting without checking wastes the user's tokens correcting false statements.

### Git & Repository State

Before saying anything about what has or has not been committed or pushed:

```bash
# Current branch and tracking status
git status

# Last 5 commits on current branch
git log --oneline -5

# Compare local branch to remote
git log --oneline origin/$(git branch --show-current)..HEAD
# (empty output = fully pushed; lines = commits not yet pushed)

# Check if a specific file was recently changed
git log --oneline -3 -- <filename>
```

Never say "you need to push first" or "that hasn't been pushed yet" without
running `git log origin/<branch>..HEAD` and confirming it returns output.
If it returns nothing, the branch IS pushed.

### Lock File & Dependency State

Before saying anything about whether a lock file is up to date:

```bash
# Show the last git commit that touched the lock file
git log --oneline -3 -- flake.lock

# Show when the lock file was last modified on disk
stat flake.lock
```

Never say "the lock file is stale" or "you need to update dependencies first"
without checking the actual file state.

### The Golden Rule

**If you are not certain — run a check command and report what it returns.**
**Do not fill uncertainty with an assumption stated as fact.**
A one-line `git log` or `stat` call costs nothing. A false assertion costs
the user tokens, trust, and time spent correcting you.

---

## Safeguards Summary

- Maximum 2 refinement cycles — after which: STOP and report to user
- Maximum 2 preflight cycles — after which: STOP and report to user
- Preflight failure overrides review approval
- No work considered complete until Phase 6 passes
- CI pipeline should succeed if preflight succeeds locally
- All commands must be validated against Resource Constraints before use
- FORBIDDEN COMMANDS block applies to ALL phases
- Escalate to user after 2 failed cycles — NEVER loop silently beyond the limit

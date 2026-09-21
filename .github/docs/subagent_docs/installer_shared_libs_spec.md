# Installer shared libs (audit item 4) — Specification

Tracker: `installer_audit_findings.md` item 4. Also resolves the stale
"only VirtualBox writes features.nix" comments (item 11, first bullet), since the
blocks that carry them are deleted.

## 1. Current state
`install.sh`, `stateless-setup.sh`, `migrate-to-stateless.sh` each carry their own
copy of: `VEXOS_REV` resolution, colour helpers, the progress-lib loader (each
labelled "keep in sync"), and the GPU / NVIDIA-branch / VM-hypervisor / ASUS /
password prompts. `install.sh` alone has the `gum` arrow-key UI; the other two
are numbered-`read` only.

## 2. Constraints
- Scripts run as `curl … | bash`: `$0` is `bash`, so libs load from
  `$(dirname "$0")/lib/` in a checkout, else by URL pinned to `$VEXOS_REV`.
- `VEXOS_REV` must be known before any lib can be fetched, so its resolution and a
  minimal `_load_lib` stay inline. That is the audit's accepted chicken-and-egg.
- Prompts run in a `$( )`-free way: `ask_*` set globals. A numbered fallback menu
  echoed inside command substitution would be swallowed.
- Existing fallback contract: without `gum`, every helper degrades to a `read`
  prompt.

## 3. Design
```
scripts/lib/bootstrap.sh   colours; loads progress.sh (+ its plain fallbacks);
                           loads prompts.sh
scripts/lib/prompts.sh     ui_choose/ui_confirm/ui_input, init_gum, ask_choice,
                           ask_yes_no, ask_gpu_variant, ask_nvidia_branch,
                           ask_vm_platform, ask_asus, ask_password
```
Each script keeps: `VEXOS_REV` resolution, `VEXOS_INSTALLER_TITLE`, `_load_lib`,
one `_load_lib bootstrap.sh` call.

`ask_choice VAR "title" "default" entry…` — entry `value[,alias…]:label`. gum path
uses the labels; fallback prints a numbered list and accepts number, value, or
alias (case-insensitive). Replaces five hand-written loops in `install.sh`
(role, server type, DE, GPU, VM, NVIDIA) and the stateless copies.

Look-and-feel is preserved per script by one variable:
`VEXOS_PROMPT_STYLE=full` (set by `install.sh` only) → `render_header` before each
draw, centred menu text, header redraw on invalid input. Default `plain` → what
the stateless scripts print today.

Behaviour changes (deliberate, small):
- Stateless scripts gain the gum arrow-key UI for the shared prompts (the goal).
- If `bootstrap.sh`/`prompts.sh` cannot be loaded the script now exits with a
  clear error instead of continuing with cosmetic fallbacks. Colours and prompts
  are load-bearing; the raw host that served the script is already required for
  every later step.
- Prompt wording is generated: "Enter choice [1-N] or name (a / b / c)". Invalid
  input message is generic. Password prompt reads "Password (hidden):" in both
  scripts.
- Menu hints for the NVIDIA branch print above the menu in every script.

Not moved: role / server-type / DE selection stay in `install.sh` (install-only,
but rewritten onto `ask_choice`); disk prompt, GRUB/EFI device prompts and the
"existing hash" logic in migrate stay where they are.

## 4. Risks / mitigation
| Risk | Mitigation |
|---|---|
| Cannot run the installers end to end | Drive `prompts.sh` under a pty with scripted input (numbered path) and a stub `gum` (value mapping); shellcheck all files; diff old vs new prompt outcomes per answer |
| A lib fetch 404 breaks every installer | `-f` fails loud; message names the URL; pinned to one commit like every other download |
| `set -u` unbound colour vars | bootstrap defines them before anything else; libs use `${VAR:-}` |

## 5. Verification
`bash -n` + shellcheck (preflight stage 9) on all files; pty run of each `ask_*`
with number, name, alias, default, invalid-then-valid; stub-gum run; preflight 0.

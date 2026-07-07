# L-20 — Tracked Python bytecode artifact `scripts/__pycache__/`

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-20 (ARCH 5.3)

## Current State

Confirmed via `git ls-files`: `scripts/__pycache__/configure-network.cpython-313.pyc`
is tracked by git. `.gitignore` has no `__pycache__` entry at all, so this
would happen again the next time `scripts/configure-network.py` is run
locally. Confirmed no other `__pycache__` artifacts exist anywhere else in
the repo (filesystem search).

## Problem Definition

A compiled bytecode artifact (machine/Python-version-specific, regenerable,
not source) is committed to the repository, and nothing prevents it from
recurring.

## Proposed Solution

Remove the tracked file from disk and add `__pycache__/` to `.gitignore`
(matches the plan's own proposed fix). Per this project's git-safety rules,
I don't run `git rm`/`git add`/`git commit` myself — deleting the file from
disk is a plain filesystem operation; staging the resulting deletion is
part of the normal Phase 7 flow the user runs.

## Implementation Steps

1. Delete `scripts/__pycache__/configure-network.cpython-313.pyc` (and the
   now-empty `scripts/__pycache__/` directory) from disk.
2. `.gitignore` — add `__pycache__/`.

## Configuration Changes

None — build/tooling artifact only; no NixOS module or option changes.

## Risks and Mitigations

- **None** — a `.pyc` file is a regenerable compiled-bytecode cache with no
  source content of its own; removing it has zero effect on
  `scripts/configure-network.py`'s actual behavior (Python regenerates it
  transparently on next run).

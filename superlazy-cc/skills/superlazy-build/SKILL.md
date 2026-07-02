---
name: superlazy-build
description: >
  Run the superpowers build pipeline (brainstorming -> writing-plans ->
  subagent-driven-development) with three adversarial critics gating each seam:
  superlazy-spec-critic, superlazy-plan-critic, superlazy-code-critic. Use when you want a reviewed,
  gated feature build. Plans are parallel-ready and executed in waves of
  concurrent subagents. Accepts optional --skip-critics and --serial flags.
---

# superlazy-build — gated superpowers pipeline

You are the COORDINATOR. Drive the existing superpowers skills as stages and
dispatch a critic at each seam. Do NOT skip seams. A PreToolUse gate hook
backstops you by blocking stage transitions until the prior critic's marker
exists — but you must still run the critics.

## Announce
"Using superlazy-build to run a critic-gated build pipeline."

## Inputs
- The user's brief (everything after the skill name).
- Optional `--skip-critics` flag.
- Optional `--serial` flag — opt out of wave parallelism: skip the
  parallel-ready plan override (Step 3) and the wave dispatch policy (Step 5).

## Step 0 — Setup
1. Choose a run id (slug of the topic), e.g. `superlazy-build-<topic>`.
2. Initialize markers + gitignore:
   ```bash
   mkdir -p .superlazy-build/<run-id>
   echo "<run-id>" > .superlazy-build/current
   grep -qxF '.superlazy-build/' .gitignore 2>/dev/null || echo '.superlazy-build/' >> .gitignore
   ```
3. Create three native seam-gate tasks: "SEAM 1: spec-critic",
   "SEAM 2: plan-critic", "SEAM 3: code-critic".
4. SKIP path: if `--skip-critics` OR the brief is clearly trivial (single-file,
   sub-~30-line change), announce critics are skipped, `rm -f
   .superlazy-build/current` (so the gate hook is a no-op), run the plain flow
   (brainstorming -> writing-plans -> subagent-driven-development), and stop here.

## Step 1 — Brainstorm
Invoke Skill `superpowers-extended-cc:brainstorming` with the brief.
OVERRIDE: brainstorming ends by trying to invoke writing-plans. Do NOT let it.
When the design spec is written and user-approved, RETURN HERE for SEAM 1.

## Step 2 — SEAM 1: spec-critic (SURFACE, do not auto-fix)
1. Dispatch the `Agent` tool, subagent_type `superlazy-spec-critic`, with ONLY: the
   spec doc path, the user's original brief verbatim, and (re-review) what
   changed. Never include this session's history.
2. Parse the VERDICT block (see Parser below).
3. Act:
   - pass -> record Minor to the run report; `touch
     .superlazy-build/<run-id>/spec-critic.passed`; go to Step 3.
   - targeted-fixes / rewrite -> SURFACE the Critical/Important findings to the
     user and ask how to handle each (fix / accept / reject). Spec findings are
     intent decisions; do NOT auto-edit. After the user directs fixes and the
     spec is updated, re-dispatch with a "what changed" note. Loop until pass or
     the user says proceed (then still write the marker).

## Step 3 — Write plan
Invoke Skill `superpowers-extended-cc:writing-plans`.
OVERRIDE: writing-plans ends with an AskUserQuestion choosing execution. Do NOT
let that run the executor. When the plan doc + .tasks.json exist, RETURN HERE.

OVERRIDE — the plan must be PARALLEL-READY (skip if `--serial`):
- Cut tasks file-disjoint. Encode waves via `blockedBy` — REAL dependencies
  only; a superfluous `blockedBy` kills parallelism.
- Pin cross-task contracts: any shared type/signature/name that one wave task
  references from a sibling goes in the plan header or in a dedicated
  contracts task scheduled as the FIRST wave. Parallel agents write blind,
  without compiling — each needs its neighbour's exact interface.
- Barrier tasks: shared steps (codegen/regeneration, wiring/registration,
  cleanup) become separate integration tasks AFTER the wave that needs them.
  Prefer a codegen wave FIRST (one regen) so later waves see generated types.
- State the test policy explicitly in the plan: when wave tasks share a build
  unit (e.g. one compilation package), agents WRITE code+tests but
  compile/test runs are deferred to the barrier.

## Step 4 — SEAM 2: plan-critic (AUTO-FIX, bounded)
1. Dispatch `Agent` subagent_type `superlazy-plan-critic` with: plan doc path, spec doc
   path, (re-review) what changed. Crafted context only.
2. Parse the VERDICT block.
3. Act:
   - pass -> `touch .superlazy-build/<run-id>/plan-critic.passed`; go to Step 5.
   - targeted-fixes -> YOU edit the plan doc + .tasks.json to address each
     Critical/Important, then re-dispatch with a "what changed" note. MAX 2
     fix-rounds. If still not pass after round 2, STOP and surface residual
     findings to the user.
   - rewrite -> surface to the user; do not auto-rewrite the whole plan.

## Step 5 — Execute
Invoke Skill `superpowers-extended-cc:subagent-driven-development`.
- Keep its per-task reviews AND its final reviewer (quality lens) — do NOT
  suppress them. Per-task reviews are read-only: run them in parallel after
  each wave's join.
- Wave dispatch (tightens sdd's Bounded Parallel Dispatch; skip if `--serial`):
  - Dispatch ALL unblocked file-disjoint tasks of a wave in ONE message
    (parallel Agent calls), then join.
  - Wave agents do NOT commit — they share one worktree and race on the git
    index. The coordinator commits at the join, one commit per task. (This
    overrides sdd's implementer-commits default for wave tasks.)
  - Barrier after each wave: codegen/regen, build, full test run. Failures go
    back to the owning task's agent (fresh dispatch with the failure output);
    MAX 2 repair rounds, then surface to the user. Next wave only after a
    green barrier.
  - Inherently serial tasks (live probes, checks against a running service)
    stay OUTSIDE waves, ordered as the plan states.
  - sdd's rule stands: uncertain file overlap → serialize.
- Capture the range:
  ```bash
  cd <worktree>                                   # the worktree sdd uses
  BASE_SHA=$(git merge-base <parent-branch> HEAD) # parent usually dev/main
  # ... sdd runs ...
  HEAD_SHA=$(git rev-parse HEAD)
  ```
  If unsure of the parent, use the branch the worktree was created from.

## Step 6 — SEAM 3: code-critic (AUTO-FIX, bounded)
1. Dispatch `Agent` subagent_type `superlazy-code-critic` with: worktree path,
   BASE_SHA, HEAD_SHA, plan doc path, spec doc path, (re-review) what changed.
2. Parse the VERDICT block.
3. Act:
   - pass -> go to Step 7.
   - targeted-fixes -> coordinator (or a fix subagent) edits code to address
     Critical/Important, commit, update HEAD_SHA, re-dispatch. MAX 2 rounds,
     then surface residual to user.
   - rewrite -> surface to user.

## Step 7 — Finish
Invoke Skill `superpowers-extended-cc:finishing-a-development-branch`.
Then `rm -f .superlazy-build/current` (end run; gate returns to no-op).

## VERDICT parser (use at every seam)
- VERDICT = first line matching `^VERDICT:`; value is the token after the colon.
- Critical count = lines matching `^- \[Critical\]`. Important = `^- \[Important\]`.
- pass-gate = (Critical == 0 AND Important == 0). The agent's self-reported
  VERDICT token is advisory; the COUNTS are authoritative.
- Garbled/missing VERDICT line -> NEEDS-HUMAN: show raw output, ask how to proceed.

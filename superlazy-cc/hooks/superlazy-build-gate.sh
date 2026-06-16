#!/usr/bin/env bash
# superlazy-build-gate.sh — PreToolUse gate for the superlazy-build pipeline.
# Denies advancing to the next superpowers stage until the prior critic's
# marker exists. No-op outside a superlazy-build run.
set -euo pipefail

input="$(cat)"

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
[ "$tool_name" = "Skill" ] || { printf '{}'; exit 0; }

# The Skill tool's target skill name (handles plugin-namespaced ids).
skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // .tool_input.command // empty')"
[ -n "$skill" ] || { printf '{}'; exit 0; }

# Run relative to the project the tool call happened in.
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || true

current_file=".superlazy-build/current"
[ -f "$current_file" ] || { printf '{}'; exit 0; }   # not in a run -> allow
run_id="$(cat "$current_file")"
mdir=".superlazy-build/${run_id}"

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

case "$skill" in
  *writing-plans*)
    [ -f "${mdir}/spec-critic.passed" ] || \
      deny "superlazy-build: SEAM 1 not cleared — run superlazy-spec-critic on the design spec and resolve Critical/Important findings before writing-plans."
    ;;
  *subagent-driven-development*|*executing-plans*)
    [ -f "${mdir}/plan-critic.passed" ] || \
      deny "superlazy-build: SEAM 2 not cleared — run superlazy-plan-critic on the plan and clear Critical/Important findings before execution."
    ;;
esac

printf '{}'   # allow

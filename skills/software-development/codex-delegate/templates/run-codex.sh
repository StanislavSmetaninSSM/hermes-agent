#!/usr/bin/env bash
set +e

Repo="${1:?repo path required}"
RunDir="${2:?run dir required}"
Prompt="$RunDir/prompt.md"
Final="$RunDir/final.md"
Events="$RunDir/events.jsonl"
Stderr="$RunDir/stderr.log"
ExitCodeFile="$RunDir/exit-code.txt"

cd "$Repo" || exit 97

codex --dangerously-bypass-approvals-and-sandbox exec \
  -C "$Repo" \
  -m gpt-5.5 \
  -c 'model_reasoning_effort="xhigh"' \
  -c 'approval_policy="never"' \
  -s danger-full-access \
  --json \
  -o "$Final" \
  '-' < "$Prompt" > "$Events" 2> "$Stderr"

code=$?
printf '%s\n' "$code" > "$ExitCodeFile"
exit "$code"

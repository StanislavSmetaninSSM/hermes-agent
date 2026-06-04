---
name: codex-delegate
description: Use when Hermes should hand a coding task to the local Codex CLI instead of solving it directly, especially explicit Codex requests, large repository edits, hard debugging, long autonomous implementation, risky refactors, code review work, or Superpowers-guided workflows where the heavy coding loop should run in Codex.
version: 1.0.0
author: Local Hermes
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [codex, openai, coding-agent, delegation, windows, long-running]
    related_skills: [systematic-debugging, test-driven-development, requesting-code-review]
---

# Codex Delegate

## Overview

Use this skill when Hermes is the messenger/orchestrator and the local Codex CLI should be the coding worker. Hermes should keep the Telegram/user conversation, prepare the task, launch Codex in a monitored background run, and report observable progress and final evidence.

When Superpowers is active, treat it as the method layer, not as a reason for Hermes to do all implementation itself. Hermes should use Superpowers to choose the workflow, sharpen the task, and verify completion. Codex should handle the expensive repository loop when the task crosses the delegation threshold.

This skill is tuned for this machine:

- Codex CLI is installed and available as `codex`.
- The preferred model is `gpt-5.5`.
- The required reasoning setting is `model_reasoning_effort="xhigh"`.
- The user accepts autonomous local-machine access for coding tasks.
- Codex must run with unrestricted local execution: launch as
  `codex --dangerously-bypass-approvals-and-sandbox exec ...` and keep
  `-s danger-full-access` in the exec options.
  In Codex logs, `sandbox: danger-full-access` means the unrestricted mode, not
  a restricted sandbox.

This does not expose hidden chain-of-thought. Ask Codex for concise rationale, progress, files changed, tests run, and remaining risks, not private reasoning.

## When to Use

Use Codex delegation when any of these are true:

- The user explicitly asks to use Codex, delegate to Codex, get "Codex quality", or run something "as in Codex".
- The task needs substantial repository edits, feature implementation, refactoring, migrations, or multi-file changes.
- The task is hard debugging that requires reading code, running tests, changing code, and verifying the fix.
- The task is a code review, PR review, regression hunt, or broad cleanup where Codex's native coding-agent workflow is useful.
- The user wants a long autonomous run while interacting through Telegram or another messenger.
- A Superpowers skill such as systematic debugging, test-driven development, planning, or verification-before-completion is relevant, and the actual coding work is large enough to benefit from Codex.
- Hermes can coordinate the task, but Codex has better ergonomics for the implementation loop.

Do not delegate by default for:

- Short Q&A, explanations, or project analysis with no edits.
- Simple commands, one-line config edits, or quick file reads.
- Non-code tasks.
- Ambiguous tasks where the target repository is unknown and choosing the wrong directory could damage unrelated work.
- Secrets/auth file inspection unless the user explicitly asked for it. Even then, do not paste secrets into logs or chat.

## Using With Superpowers

Superpowers and Codex are complementary:

- Superpowers answers: what process should be followed?
- Codex answers: how should the repository be changed?
- Hermes answers: what did the user ask, when should Codex be launched, what progress should be reported, and is the final result verified?

Default routing:

| Situation | Hermes should do | Codex should do |
| --- | --- | --- |
| Brainstorming or requirements are still unclear | Use Superpowers to clarify and shape the task | Wait |
| User approves implementation or asks for autonomous work | Prepare a precise Codex prompt | Inspect, edit, test, and report |
| Debugging requires code investigation | Frame the debugging method and evidence rules | Trace root cause, patch, and verify |
| TDD is appropriate | Tell Codex to follow red-green-refactor | Write tests, implement, rerun tests |
| Final report is ready | Independently check logs, diff, and status | Provide final summary in `final.md` |

If a Superpowers workflow applies, include a short "Method requirements" block in `prompt.md` instead of pasting whole skill files:

```markdown
Method requirements:
- Follow systematic debugging: reproduce or identify the symptom, find root cause before patching, and verify the fix against the original symptom.
- Use TDD when practical: add or update a focused test before implementation, then make it pass.
- Preserve user changes and avoid unrelated refactors.
- Final response must include verification evidence, not just a success claim.
```

Choose only the method requirements that fit the task. Do not overload Codex with irrelevant process instructions.

Hermes should still use Superpowers after Codex finishes. In particular, apply verification-before-completion behavior: check exit code, logs, diff, and test evidence before telling the user that the task is complete.

## Preflight

Before launching Codex:

1. Treat the user's latest chat message as the active request. Use earlier Telegram/chat messages only as context for resolving references like "continue", "do it", or "as discussed"; do not turn older messages into additional Codex tasks unless the latest message explicitly asks for that.
2. Identify the target working directory. Prefer an existing git repository.
3. If the target directory is unclear, ask the user for the repo/path instead of guessing.
4. Run `git status --short` in the repo and preserve any existing user changes.
5. Run `codex --version` if Codex availability is uncertain.
6. Create a per-run directory under an ASCII-only path. On this Windows machine,
   avoid `C:\Users\Ёж\...` for Hermes terminal background work because the
   terminal tool can block workdirs containing `Ё`. Prefer:

```text
E:\Games\codex-runs\<timestamp>-<short-slug>\
```

Store at least these files there:

- `prompt.md` - the exact task sent to Codex.
- `run-codex.sh` - the launch script.
- `events.jsonl` - Codex JSON event stream.
- `stderr.log` - stderr and CLI errors.
- `final.md` - Codex's final message.
- `exit-code.txt` - Codex process exit code, if the script can write it.

If the target repo is under a path with non-ASCII characters or Hermes blocks the
workdir, create or use a git worktree under an ASCII-only path such as
`E:\Games\worktrees\<slug>\` and pass that path to Codex. Do not keep retrying
from a blocked `C:\Users\Ёж\...` workdir.

Do not run long Codex work in a foreground terminal call. Hermes terminal calls may have per-tool timeouts; long tasks must be launched as background processes and monitored.

## Prompt Template

Write a clear `prompt.md`. Include only the context Codex needs:

```markdown
You are running as Codex CLI on the user's Windows machine.

Task:
<user task>

Working directory:
<absolute repo path>

Current worktree status before you start:
<git status --short output>

Method requirements:
<short Superpowers-derived workflow rules, only if relevant>

Operating rules:
- Use model gpt-5.5 with xhigh reasoning for this run.
- Inspect the repository before editing.
- Preserve user changes. Do not revert or overwrite unrelated edits.
- Do not reveal secrets from .env, auth files, tokens, or browser profiles.
- Make focused changes that solve the task.
- Run appropriate verification before finishing.
- If blocked, explain the blocker and the exact evidence.
- Final response must include: summary, files changed, verification commands and results, remaining risks.
- The wrapper captures your final message into the run directory's `final.md`; do not create, add, or commit a `final.md` (or other run-log artifact) inside the repository.
```

For large tasks, add expected constraints, acceptance criteria, tests to run, and anything the user said in Telegram that Codex would not otherwise know.

## Launch Pattern

Create `run-codex.sh` in the run directory and launch it with Git Bash. This is
the required default Windows path on this machine. Do not describe a
`run-codex.ps1` wrapper as the standard plan for Hermes-to-Codex delegation.
Avoid Windows PowerShell `>` for `events.jsonl`: Windows PowerShell can write
UTF-16 output, which makes the JSONL look binary to Hermes and breaks
monitoring.

Mandatory launch invariants:

- Always include `--json`. Missing `--json` is a launch bug because Hermes loses
  structured progress and may misread the stderr UI stream.
- Always include `-m gpt-5.5` and `-c 'model_reasoning_effort="xhigh"'`.
- Always launch as `codex --dangerously-bypass-approvals-and-sandbox exec ...`
  and include `-s danger-full-access` plus `-c 'approval_policy="never"'`.
- Do not report `sandbox: danger-full-access` as a sandbox/access failure; it is
  Codex CLI's label for full local-machine access.
- Do not paraphrase the launch script from memory and do not print it into
  Telegram/chat as a "template". Copy the exact wrapper from
  `templates/run-codex.sh` into the run directory, read the saved file back, and
  validate it with `bash -n "$RunDir/run-codex.sh"` before launch. A wrapper is
  invalid if variable references lose `$`, redirections lose `<`/`>`, the
  shebang loses `#`, or `code=$?` becomes `code=?`.

Wrapper source of truth:

- Skill-relative file: `templates/run-codex.sh`
- Copy it unchanged to: `$RunDir/run-codex.sh`
- Launch it with two arguments: repo path and run directory.

Launch it through Hermes as a background terminal/process run:

```text
terminal(
  command="bash \"E:/Games/codex-runs/<run>/run-codex.sh\" \"E:/Games/worktrees/<repo-slug>\" \"E:/Games/codex-runs/<run>\"",
  workdir="E:/Games/worktrees/<repo-slug>",
  background=true,
  notify_on_complete=true,
  timeout=600
)
```

If the terminal tool supports `pty`, prefer non-interactive execution for `codex exec`; do not launch the interactive Codex TUI for autonomous delegation.

Use `--skip-git-repo-check` only for scratch/non-repo tasks after explaining why. Do not use obsolete automation aliases from old Codex docs; this machine's current Codex CLI uses `codex --dangerously-bypass-approvals-and-sandbox exec ...`, `-c approval_policy="never"`, and `-s danger-full-access`.

## Monitoring

After launch:

- Save the returned background/session id.
- Poll process status periodically.
- Treat the run as still active while the OS/background process is alive, even if
  `final.md` or `exit-code.txt` does not exist yet.
- Inspect `stderr.log` if the process exits nonzero or appears stuck.
- If the process exits `0`, do not treat earlier `stderr.log` snippets as blockers by themselves. Codex may record historical failed probes (for example missing optional skill-cache files or a RED test) before later completing successfully. Classify them against `exit-code.txt`, `final.md`, `events.jsonl`, git diff, and fresh local verification before reporting failure.
- Inspect the tail of `events.jsonl` for observable progress, tool calls, and final events.
- Send the user concise progress updates only when useful: started, important blocker, verification running, completed, failed.
- Do not spam Telegram with every Codex event.
- Do not drop `--json` on retries. Without `--json`, progress goes to
  `stderr.log` instead of `events.jsonl`, and Hermes loses structured monitoring.
- For Codex launched by a cron worker, validate the full `notify_on_complete` route when changing worker/gateway behavior: watcher registration, completion injection, synthetic internal-event acceptance, and final agent/Telegram response. See `references/cron-notify-on-complete-live-test.md` for the scratch one-shot test pattern and failure signatures.

If Codex asks for clarification, relay the exact question to the user. If the answer is obvious from prior conversation or files, answer it in the prompt/context instead of interrupting the user.

## Completion

For a `notify_on_complete` wake-up from a Codex background process, do a
bounded reconciliation pass. The active task is to decide what happened to the
completed Codex run and report the outcome, not to reopen the whole issue from
scratch.

Rules for completion notifications:

- Read only the run artifacts needed for classification: `exit-code.txt`,
  `final.md`, recent `stderr.log`/`events.jsonl` tail, `git status`, and a
  small diff/stat or targeted file inspection.
- If Codex exited `0` and the repo evidence matches `final.md`, prefer a short
  report or the next explicit closure step. Do not start a broad second
  implementation loop inside the same Telegram turn.
- Do not call `delegate_task` for an independent review from an already large
  completion-notification context. If independent review is required, launch a
  separate fresh Codex review run or defer it to the next cron tick with a
  concise state summary.
- Do not rerun broad test suites after Codex already produced matching test
  evidence unless the diff is risky or the evidence is missing. Prefer one
  lightweight targeted check.
- If the context is already very large or the model/provider is slow, cap
  reconciliation to the minimum evidence needed and send the user a concrete
  status instead of continuing to accumulate tool output.

Before telling the user the task is done:

1. Confirm the Codex process exited.
2. Read `exit-code.txt`, `stderr.log`, and `final.md`.
3. Run `git status --short` in the repo.
4. Use `git diff --stat` or targeted file inspection to confirm what changed.
5. Check for accidental run artifacts in the repository (`final.md`, `events.jsonl`, `stderr.log`, `exit-code.txt`, prompt/run scripts) and remove/amend them before PR/merge if Codex created them.
6. If Codex claims tests passed, verify the command output exists in logs or rerun a lightweight verification when practical.
7. For cron-launched Codex runs that rely on `notify_on_complete`, do not treat `final.md`/`exit-code.txt` as proof that the orchestrator resumed. Confirm the gateway processed the completion notification into a separate agent turn; if it only logged injection and then dropped the synthetic event or failed delivery, debug the gateway route before resuming the real worker.
8. Summarize in chat:
   - what Codex changed,
   - files touched,
   - verification performed,
   - any nonzero exit, skipped test, or remaining risk,
   - where the run logs are stored.

Never report success only because Codex produced a final message. Check the repo state and verification evidence.

## Resume or Retry

For an interrupted run:

- Prefer inspecting the run directory first: `final.md`, `stderr.log`, `events.jsonl`, and current git diff.
- Before retrying, confirm the old Codex process is dead. Missing `final.md` or
  `exit-code.txt` is not enough evidence if the process is still running.
- Use `codex exec resume --last` only when it is clearly the same task and repo.
- Otherwise start a new run with a fresh `prompt.md` that includes what was already changed and what still needs to be done.

If two Codex processes might edit the same repo, stop and ask the user which one should continue. Parallel Codex runs should use separate git worktrees or clearly separate repositories.

## Common Pitfalls

1. Letting Telegram history become the task. When delegating from chat, the latest user message is the active instruction; prior messages are context-only unless the latest message explicitly reopens them.
2. Running Codex in the foreground for a long task. Use a background process, or Hermes may kill the tool call at its timeout.
3. Starting in the wrong directory. Always verify the repo path before launch.
4. Forgetting `xhigh`. Always pass `-c 'model_reasoning_effort="xhigh"'`.
5. Forgetting no-approval automation. Always pass `-c 'approval_policy="never"'` for autonomous runs on this machine.
6. Forgetting `--json`. Without it, Codex writes the human UI stream to stderr
   and Hermes loses reliable structured monitoring.
7. Misreading `sandbox: danger-full-access`. That header means unrestricted
   execution, not restricted sandbox mode.
8. Using outdated flags. Use the current Codex CLI flags shown in this skill, not obsolete automation aliases from old docs.
9. Pasting secrets into prompts or logs. Summarize that credentials exist; do not quote them.
10. Trusting final text without checking files. Inspect `git status`, diffs, and verification logs.
11. Running multiple agents in the same worktree. Use worktrees or wait for the current run to finish.
12. Treating Superpowers as a competing coding agent. Use Superpowers for process and Codex for heavy implementation.
13. Sending all Superpowers text to Codex. Pass concise method requirements, not entire skill bodies, unless the exact details are necessary.
14. Using `C:\Users\Ёж\...` as a Hermes background workdir. Use ASCII-only paths
    such as `E:\Games\worktrees\...` and `E:\Games\codex-runs\...`.
15. Retrying with a non-JSON Codex wrapper. Keep `--json` so Hermes can monitor
    `events.jsonl`.
16. Recasting the launch wrapper as `run-codex.ps1`. Use the Git Bash
    `templates/run-codex.sh` wrapper unless the user explicitly requests a PowerShell
    rewrite and the wrapper preserves UTF-8/JSONL output correctly.
17. Hand-typing a shell snippet into chat and losing shell syntax. If showing
    the wrapper to the user, do not reconstruct it manually; tell the user to
    inspect the saved `run-codex.sh` file and report the `bash -n` result.
18. Asking Codex for a "final response in `final.md`" without clarifying that
    the wrapper writes the run-directory `final.md`. Codex may create and commit
    a repository-root `final.md`; phrase prompts as "final message will be
    captured by the wrapper" and verify no run artifacts entered the git diff.

## Verification Checklist

- [ ] Target repo/path is confirmed.
- [ ] Dirty worktree state was checked and passed to Codex.
- [ ] Run directory was created under an ASCII-only path such as `E:\Games\codex-runs\`.
- [ ] `prompt.md` includes the user task, repo path, constraints, and required final format.
- [ ] If Superpowers is relevant, `prompt.md` includes concise method requirements.
- [ ] `run-codex.sh` was copied from `templates/run-codex.sh` and uses `gpt-5.5`, `model_reasoning_effort="xhigh"`, `approval_policy="never"`, `danger-full-access`, and `--json`.
- [ ] `run-codex.sh` was read back and `bash -n` passed before launch.
- [ ] Codex was launched in background mode.
- [ ] Completion was verified with exit code, logs, final message, and repo state.

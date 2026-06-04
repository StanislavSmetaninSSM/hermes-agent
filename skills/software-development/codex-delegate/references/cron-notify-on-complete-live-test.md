# Cron `notify_on_complete` live-test lessons

Use this when validating Codex delegation launched by a Hermes cron worker.

## What must be tested

A successful Codex exit is not enough. Verify the whole route:

1. Cron worker starts Codex via `terminal(background=true, notify_on_complete=true)`.
2. Gateway logs `Started process watcher for proc_...`.
3. When Codex exits, gateway logs `Process proc_... finished — injecting agent notification ...`.
4. The injected synthetic event is accepted as an internal event, not dropped as `user=None` by active-session authorization.
5. A separate agent turn/Telegram response is produced from the completion notification.

## Minimal scratch test pattern

- Use a disposable ASCII-only scratch repo, e.g. `E:/Games/hermes-notify-test/repo`.
- Create a one-shot cron job whose only task is to write `prompt.md` and `run-codex.sh`, then launch Codex in the background with `notify_on_complete=true`.
- Prompt Codex with something tiny, e.g. “Скажи привет одним коротким русским предложением. Не редактируй файлы.”
- Do not have the cron job wait/poll until Codex finishes; the point is to test the gateway notification path.

## Failure signatures

- No `Started process watcher...`: watcher was not registered/drained from cron.
- `Process ... finished — injecting agent notification...` followed by no agent turn: inspect gateway logs for downstream drop/error.
- `Dropping message from unauthorized user in active session: user=None ...`: synthetic process-completion event reached gateway but was rejected by the busy-session user authorization guard; internal process notifications need to bypass human allowlist checks while external messages still require authorization.
- Cron job final delivery can fail separately in Telegram DM topics if there is no reply anchor (`Telegram DM topic delivery requires a reply anchor...`). Do not confuse that with `notify_on_complete` failure: the watcher route is judged by the process watcher logs and the separate internal completion event/agent turn.

## Success criteria

A live test is successful only when all of these are true:

- The run directory has `exit-code.txt` with `0` and a plausible `final.md`.
- Gateway logs show both `Started process watcher for proc_...` and `Process proc_... finished — injecting agent notification ...` after the most recent gateway restart.
- Gateway logs do **not** show `Dropping message from unauthorized user ... user=None` for that proc after injection.
- The current chat receives or the current agent turn is interrupted by a separate internal completion event such as `[IMPORTANT: Background process proc_... completed (exit code 0)]`. If this interrupts an in-progress diagnostic turn, treat it as evidence, then finish the user's active request.
- The one-shot test job is gone/disabled afterward and unrelated real workers remain in their intended state, e.g. paused if they were paused before the test.

## Cleanup / safety

- Use a one-shot cron job (`repeat=1`) or remove the test job after verification.
- Keep real project workers paused during the test if they are unrelated.
- Do not save API keys/tokens in prompts or logs; use only scratch paths and harmless prompts.

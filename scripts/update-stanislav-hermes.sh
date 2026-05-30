#!/usr/bin/env bash
# Update this local Hermes checkout while preserving Stanislav's custom branch.
#
# Strategy:
#   upstream official Hermes: origin/main
#   local custom branch:      stanislav/hermes-local-fixes
#   writable fork remote:     stanislav
#
# This intentionally does NOT run `hermes update`, because the stock updater
# targets origin/<branch> and the default branch is main. For this setup we want
# to merge upstream main into our long-lived custom branch, test it, then push
# the custom branch to the user's fork.

set -euo pipefail

REPO="${HERMES_REPO:-}"
if [[ -z "$REPO" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

UPSTREAM_REMOTE="${HERMES_UPSTREAM_REMOTE:-origin}"
UPSTREAM_BRANCH="${HERMES_UPSTREAM_BRANCH:-main}"
LOCAL_BRANCH="${HERMES_LOCAL_BRANCH:-stanislav/hermes-local-fixes}"
FORK_REMOTE="${HERMES_FORK_REMOTE:-stanislav}"
FORK_URL="${HERMES_FORK_URL:-https://github.com/StanislavSmetaninSSM/hermes-agent.git}"
OFFICIAL_URL="${HERMES_OFFICIAL_URL:-https://github.com/NousResearch/hermes-agent.git}"

RUN_TESTS=1
PUSH=1
INSTALL_DEPS=0
RESTART_GATEWAY=0
DRY_RUN=0
YES=0
PRE_UPDATE_BACKUP_BRANCH=""

usage() {
  cat <<'USAGE'
Usage: scripts/update-stanislav-hermes.sh [options]

Safely updates Stanislav's custom Hermes branch by merging upstream origin/main
into stanislav/hermes-local-fixes, optionally testing, pushing to the fork, and
optionally restarting the gateway.

Options:
  --dry-run            Fetch and report pending upstream commits; do not merge.
  --no-tests           Skip targeted pytest suite.
  --install-deps       Reinstall editable Python package after merge.
  --no-push            Do not push the custom branch to the fork.
  --restart-gateway    Restart Hermes gateway after a successful update.
  -y, --yes            Non-interactive mode for cron/automation.
  -h, --help           Show this help.

Environment overrides:
  HERMES_REPO, HERMES_UPSTREAM_REMOTE, HERMES_UPSTREAM_BRANCH,
  HERMES_LOCAL_BRANCH, HERMES_FORK_REMOTE, HERMES_FORK_URL, HERMES_OFFICIAL_URL

Recommended manual update:
  scripts/update-stanislav-hermes.sh --restart-gateway

Recommended safe scheduled check:
  scripts/update-stanislav-hermes.sh --dry-run -y
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-tests) RUN_TESTS=0 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    --no-push) PUSH=0 ;;
    --restart-gateway) RESTART_GATEWAY=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

cd "$REPO"

say() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run() { say "+ $*"; "$@"; }

require_clean_tree() {
  if [[ -e .git/MERGE_HEAD || -d .git/rebase-merge || -d .git/rebase-apply ]]; then
    fail "Repository is in the middle of a merge/rebase. Resolve or abort it first."
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    git status --short
    fail "Working tree is not clean. Commit/stash changes before updating."
  fi
}

ensure_remote() {
  local name="$1"
  local url="$2"
  if ! git remote get-url "$name" >/dev/null 2>&1; then
    run git remote add "$name" "$url"
  fi
}

python_exe() {
  if [[ -x "venv/Scripts/python.exe" ]]; then
    printf '%s\n' "venv/Scripts/python.exe"
  elif [[ -x "venv/bin/python" ]]; then
    printf '%s\n' "venv/bin/python"
  else
    command -v python || command -v python3 || return 1
  fi
}

run_tests() {
  local py
  py="$(python_exe)" || fail "Python not found."
  say "→ Running targeted regression tests..."
  PYTHONPATH="$REPO" "$py" -m pytest \
    tests/gateway/test_telegram_text_batching.py \
    tests/gateway/test_active_session_text_merge.py \
    tests/gateway/test_session.py \
    tests/agent/test_context_compressor.py \
    tests/run_agent/test_message_sequence_repair.py \
    tests/run_agent/test_thinking_only_sanitizer.py \
    tests/run_agent/test_run_agent_codex_responses.py \
    tests/agent/test_codex_ttfb_watchdog.py \
    -q --tb=short --timeout-method=thread
}

install_deps() {
  local py uv_bin
  py="$(python_exe)" || fail "Python not found."
  uv_bin="$(command -v uv || true)"
  say "→ Reinstalling Hermes editable package..."
  if [[ -n "$uv_bin" ]]; then
    VIRTUAL_ENV="$REPO/venv" "$uv_bin" pip install -e "$REPO"
  else
    "$py" -m pip install -e "$REPO"
  fi
}

restart_gateway() {
  say "→ Restarting Hermes gateway..."
  hermes gateway restart
}

create_pre_update_backup() {
  local stamp safe_local_branch
  stamp="$(date +%Y%m%d-%H%M%S)"
  safe_local_branch="${LOCAL_BRANCH//\//-}"
  PRE_UPDATE_BACKUP_BRANCH="backup/${safe_local_branch}-pre-update-${stamp}"

  say "→ Creating pre-update backup branch: $PRE_UPDATE_BACKUP_BRANCH"
  run git branch "$PRE_UPDATE_BACKUP_BRANCH" HEAD

  if [[ "$PUSH" -eq 1 ]]; then
    say "→ Pushing pre-update backup branch to fork..."
    run git push "$FORK_REMOTE" "$PRE_UPDATE_BACKUP_BRANCH:refs/heads/$PRE_UPDATE_BACKUP_BRANCH"
  else
    say "→ Backup branch push skipped because --no-push was set."
  fi
}

require_clean_tree
ensure_remote "$UPSTREAM_REMOTE" "$OFFICIAL_URL"
ensure_remote "$FORK_REMOTE" "$FORK_URL"

say "→ Fetching remotes..."
run git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
run git fetch "$FORK_REMOTE" "$LOCAL_BRANCH" || true

if ! git show-ref --verify --quiet "refs/heads/$LOCAL_BRANCH"; then
  if git show-ref --verify --quiet "refs/remotes/$FORK_REMOTE/$LOCAL_BRANCH"; then
    run git switch -c "$LOCAL_BRANCH" "$FORK_REMOTE/$LOCAL_BRANCH"
  else
    run git switch -c "$LOCAL_BRANCH" "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
  fi
elif [[ "$(git branch --show-current)" != "$LOCAL_BRANCH" ]]; then
  run git switch "$LOCAL_BRANCH"
fi

upstream_ref="$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
head_sha="$(git rev-parse --short HEAD)"
upstream_sha="$(git rev-parse --short "$upstream_ref")"
ahead_count="$(git rev-list --count "HEAD..$upstream_ref")"
behind_count="$(git rev-list --count "$upstream_ref..HEAD")"

say "Current branch: $(git branch --show-current) @ $head_sha"
say "Upstream:       $upstream_ref @ $upstream_sha"
say "Behind upstream: $ahead_count commit(s)"
say "Ahead of upstream: $behind_count commit(s)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$ahead_count" -eq 0 ]]; then
    say "✓ No upstream update available for $LOCAL_BRANCH."
    exit 0
  fi
  say "⚠ Upstream update is available. Run: scripts/update-stanislav-hermes.sh --restart-gateway"
  exit 10
fi

if [[ "$ahead_count" -eq 0 ]]; then
  say "✓ Already includes latest $upstream_ref."
else
  if [[ "$YES" -ne 1 ]]; then
    say "About to merge $upstream_ref into $LOCAL_BRANCH."
    read -r -p "Continue? [Y/n] " response
    response="${response:-y}"
    case "$response" in
      y|Y|yes|YES) ;;
      *) fail "Cancelled." ;;
    esac
  fi

  create_pre_update_backup

  say "→ Merging upstream main into custom branch..."
  if ! git merge --no-edit "$upstream_ref"; then
    say "✗ Merge conflict. Resolve conflicts, run tests, then commit and push."
    if [[ -n "$PRE_UPDATE_BACKUP_BRANCH" ]]; then
      say "  Pre-merge backup branch: $PRE_UPDATE_BACKUP_BRANCH"
    fi
    say "  Abort if needed: git merge --abort"
    exit 20
  fi
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  run_tests
else
  say "→ Tests skipped."
fi

if [[ "$INSTALL_DEPS" -eq 1 ]]; then
  install_deps
else
  say "→ Dependency reinstall skipped. Add --install-deps if pyproject/entrypoints changed."
fi

if [[ "$PUSH" -eq 1 ]]; then
  say "→ Pushing custom branch to fork..."
  run git push "$FORK_REMOTE" "$LOCAL_BRANCH"
else
  say "→ Push skipped."
fi

if [[ "$RESTART_GATEWAY" -eq 1 ]]; then
  restart_gateway
else
  say "→ Gateway restart skipped. Run 'hermes gateway restart' when ready to apply in Telegram."
fi

say "✓ Custom Hermes update flow complete."

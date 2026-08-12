#!/bin/sh
# tests for the claude code hook scripts: feed each one a real event on stdin
# and check the decision it returns.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
CLAUDE_PLUGIN_ROOT=$ROOT
export CLAUDE_PLUGIN_ROOT

PASS=0
FAIL=0
GREEN=$(printf '\033[32m')
RED=$(printf '\033[31m')
OFF=$(printf '\033[0m')

ok() {
	PASS=$((PASS + 1))
	printf '%s  pass%s %s\n' "$GREEN" "$OFF" "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '%s  FAIL%s %s\n' "$RED" "$OFF" "$1"
	[ -n "${2:-}" ] && printf '        %s\n' "$2"
}

decision() {
	# $1 script, $2 event json -> "deny" or "allow"
	_out=$(printf '%s' "$2" | "$ROOT/hooks/scripts/$1" 2>/dev/null)
	case $_out in
	*'"permissionDecision":"deny"'*) printf 'deny\n' ;;
	*) printf 'allow\n' ;;
	esac
}

expect() {
	# $1 label, $2 want, $3 script, $4 event
	_got=$(decision "$3" "$4")
	if [ "$_got" = "$2" ]; then ok "$1"; else bad "$1" "wanted $2, got $_got"; fi
}

printf '\nno-claude-help plugin hook tests\n\n'

# --- bash hook -------------------------------------------------------------

expect "commit with a co-authorship trailer is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git commit -m \"fix\n\nCo-Authored-By: Claude <noreply@anthropic.com>\""}}'

expect "plain commit is allowed" allow pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git commit -m \"fix the parser\""}}'

expect "commit --amend --no-edit is allowed" allow pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git commit --amend --no-edit"}}'

expect "commit --no-verify is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git commit --no-verify -m x"}}'

expect "author override is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git commit --author=\"Claude <noreply@anthropic.com>\" -m x"}}'

expect "pull request body with a generated-with footer is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"gh pr create --title x --body \"does things\n\nGenerated with Claude Code\""}}'

expect "clean pull request body is allowed" allow pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"gh pr create --title x --body \"fixes the parser for empty input\""}}'

expect "issue comment with a session url is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"gh issue comment 5 --body \"see https://claude.ai/code/session_01abcdef\""}}'

expect "setting the git identity to an agent is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git config user.email noreply@anthropic.com"}}'

expect "setting the git identity to a human is allowed" allow pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git config user.email sam@example.com"}}'

expect "deleting the hooks is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"rm -f .git/hooks/commit-msg"}}'

expect "NCH_DISABLE is denied" deny pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"NCH_DISABLE=1 git commit -m x"}}'

expect "ordinary shell work is allowed" allow pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"grep -rn TODO src/ && npm test"}}'

expect "plain push is allowed" allow pre-bash.sh \
	'{"cwd":".","tool_input":{"command":"git push origin main"}}'

# --- write hook ------------------------------------------------------------

expect "writing an agent into AUTHORS is denied" deny pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"AUTHORS","content":"Real Human <human@example.com>\nClaude <noreply@anthropic.com>\n"}}'

expect "writing a human into AUTHORS is allowed" allow pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"AUTHORS","content":"Real Human <human@example.com>\n"}}'

expect "an agent in a package.json author field is denied" deny pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"package.json","content":"{\"name\":\"app\",\"author\":\"Claude <noreply@anthropic.com>\"}"}}'

expect "an anthropic dependency is allowed" allow pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"package.json","content":"{\"name\":\"app\",\"dependencies\":{\"@anthropic-ai/sdk\":\"0.30.0\"}}"}}'

expect "an edit adding a credit line is denied" deny pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"README.md","new_string":"## Credits\n\nBuilt with help from Claude.\n"}}'

expect "an ordinary edit is allowed" allow pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"src/db.js","new_string":"const cursor = db.query();\n"}}'

expect "a session url in a comment is denied" deny pre-write.sh \
	'{"cwd":".","tool_input":{"file_path":"src/db.js","new_string":"// see https://claude.ai/code/session_01abcdef\n"}}'

# --- plugin option parsing -------------------------------------------------

# claude code renders every option as text and its own boolean coercion
# rejects a bare "y", so the answers are parsed in common.sh
# shellcheck source=/dev/null
. "$ROOT/hooks/scripts/common.sh" </dev/null

for v in y Y yes YES true 1 on " y "; do
	if nch_opt_bool "$v" n; then ok "option \"$v\" reads as yes"; else bad "option \"$v\" reads as yes"; fi
done
for v in n N no NO false 0 off nope; do
	if nch_opt_bool "$v" y; then bad "option \"$v\" reads as no"; else ok "option \"$v\" reads as no"; fi
done
if nch_opt_bool "" y; then ok "an empty answer takes a yes default"; else bad "an empty answer takes a yes default"; fi
if nch_opt_bool "" n; then bad "an empty answer takes a no default"; else ok "an empty answer takes a no default"; fi

# --- session start ---------------------------------------------------------

OUT=$(printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$ROOT" |
	CLAUDE_PLUGIN_OPTION_AUTO_INSTALL_GIT_HOOKS=false "$ROOT/hooks/scripts/session-start.sh" 2>/dev/null)
case $OUT in
*'"additionalContext"'*) ok "session start returns the policy as context" ;;
*) bad "session start returns the policy as context" "$OUT" ;;
esac
if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
	ok "session start emits valid json"
else
	bad "session start emits valid json"
fi

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

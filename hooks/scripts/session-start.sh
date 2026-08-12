#!/bin/sh
# load the attribution policy into context, and make sure the repository's own
# git hooks are in place so the rule survives outside this session.

. "$(dirname "$0")/common.sh"

CWD=$(nch_json .cwd)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
	cd "$CWD" || exit 0
fi

NOTE=""

case ${CLAUDE_PLUGIN_OPTION_AUTO_INSTALL_GIT_HOOKS:-true} in
true | 1 | yes)
	if git rev-parse --git-dir >/dev/null 2>&1; then
		HOOK="$(git rev-parse --git-dir)/hooks/commit-msg"
		if ! grep -q 'installed by no-claude-help' "$HOOK" 2>/dev/null; then
			IDENT=${CLAUDE_PLUGIN_OPTION_AUTHOR_IDENTITY:-}
			if [ -n "$IDENT" ]; then
				"$NCH_CLI" install --author "$IDENT" >/dev/null 2>&1
			else
				"$NCH_CLI" install >/dev/null 2>&1
			fi
			if grep -q 'installed by no-claude-help' "$HOOK" 2>/dev/null; then
				NOTE="no-claude-help installed git hooks in this repository, so the attribution rule holds for whatever tool touches it next."
			fi
		fi
	fi
	;;
esac

CONTEXT=$(cat "$NCH_ROOT/lib/policy.md")
[ -n "$NOTE" ] && CONTEXT="$CONTEXT

$NOTE"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}' \
	"$(nch_jsonstr "$CONTEXT")"
[ -n "$NOTE" ] && printf ',"systemMessage":%s' "$(nch_jsonstr "$NOTE")"
printf '}\n'

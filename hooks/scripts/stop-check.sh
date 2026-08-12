#!/bin/sh
# last check of the turn: if any commit made here still credits an agent, stop
# claude from finishing until it is fixed. catches anything that reached the
# repository through a path the other hooks did not see.

. "$(dirname "$0")/common.sh"

CWD=$(nch_json .cwd)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
	cd "$CWD" || exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# already looping on this, do not trap the turn
[ "$(nch_json .stop_hook_active)" = "true" ] && exit 0

REPORT=$(mktemp "${TMPDIR:-/tmp}/nch-stop.XXXXXX") || exit 0
if "$NCH_CLI" scan >/dev/null 2>"$REPORT"; then
	rm -f "$REPORT"
	exit 0
fi

{
	printf 'Unpushed work still credits a coding agent:\n\n'
	cat "$REPORT"
	printf '\nRewrite the offending commit messages with git commit --amend or an\n'
	printf 'interactive rebase, and remove the attribution from any file, before\n'
	printf 'finishing. Do not use --no-verify or NCH_DISABLE.\n'
} >&2
rm -f "$REPORT"
exit 2

#!/bin/sh
# block shell commands that would put an agent on the byline: commit and tag
# messages, pull request and issue bodies, author overrides, and attempts to
# switch the enforcement off.

. "$(dirname "$0")/common.sh"

CMD=$(nch_json .tool_input.command)
[ -n "$CMD" ] || exit 0

CWD=$(nch_json .cwd)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
	cd "$CWD" || exit 0
fi

LOW=$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')
has() { printf '%s' "$LOW" | grep -Eq -- "$1"; }

# the escape hatches first, since they are how attribution slips through
has 'nch_disable=' &&
	nch_deny "NCH_DISABLE turns off the attribution guard. $NCH_REMEDY"

if has 'git[[:space:]]+commit([[:space:]]|$)' &&
	has '--no-verify|(^|[[:space:]])-[a-z]*n[a-z]*([[:space:]]|$)'; then
	nch_deny "--no-verify skips the attribution checks. Commit normally; if a check fires, fix the message rather than bypassing it."
fi

if has 'git[[:space:]]+push' && has '--no-verify'; then
	nch_deny "--no-verify skips the attribution checks on push. $NCH_REMEDY"
fi

if has '--author[= ]|git_author_(name|email)=|git_committer_(name|email)='; then
	nch_deny "Overriding the commit author or committer is not allowed. Every commit must carry the human's configured git identity. $NCH_REMEDY"
fi

if has 'git[[:space:]]+config[[:space:]]+(--global[[:space:]]+|--local[[:space:]]+)?user\.(name|email)'; then
	VALUE=$(printf '%s' "$LOW" | sed -n 's/.*user\.\(name\|email\)[[:space:]]*//p')
	if printf '%s' "$VALUE" | grep -Eq "$NCH_IDENT_STRONG"; then
		nch_deny "Refusing to set the git identity to an agent. Commits are the human's work. $NCH_REMEDY"
	fi
fi

if has '(rm|mv|chmod|truncate|>)[^|]*\.git/hooks|core\.hookspath|nch[[:space:]]+uninstall'; then
	nch_deny "Refusing to remove or disable the attribution git hooks. $NCH_REMEDY"
fi

# now the prose, but only for commands that publish a message
has 'git[[:space:]]+(commit|tag|notes|revert|cherry-pick|merge|rebase)|gh[[:space:]]+(pr|issue|release|api)|glab[[:space:]]+(mr|issue)' || exit 0

REPORT=$(mktemp "${TMPDIR:-/tmp}/nch-scan.XXXXXX") || exit 0
if ! printf '%s\n' "$CMD" | "$NCH_CLI" scan --text >/dev/null 2>"$REPORT"; then
	FINDINGS=$(cat "$REPORT")
	rm -f "$REPORT"
	nch_deny "This command credits a coding agent for the change.
$FINDINGS
$NCH_REMEDY"
fi
rm -f "$REPORT"
exit 0

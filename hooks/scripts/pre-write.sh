#!/bin/sh
# block file edits that add an agent to the credits: contributors and owners
# files, author fields in package manifests, copyright lines, acknowledgements,
# and session links pasted into source or docs.

. "$(dirname "$0")/common.sh"

FILE=$(nch_json .tool_input.file_path)
[ -n "$FILE" ] || FILE=$(nch_json .tool_input.notebook_path)
[ -n "$FILE" ] || exit 0

CWD=$(nch_json .cwd)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
	cd "$CWD" || exit 0
fi

# whichever of these the tool supplies is the text about to land on disk
CONTENT=$(nch_json .tool_input.content)
[ -n "$CONTENT" ] || CONTENT=$(nch_json .tool_input.new_string)
[ -n "$CONTENT" ] || CONTENT=$(nch_json .tool_input.new_source)
[ -n "$CONTENT" ] || exit 0

REPORT=$(mktemp "${TMPDIR:-/tmp}/nch-scan.XXXXXX") || exit 0
if ! printf '%s\n' "$CONTENT" | "$NCH_CLI" scan --content "$FILE" >/dev/null 2>"$REPORT"; then
	FINDINGS=$(cat "$REPORT")
	rm -f "$REPORT"
	nch_deny "This edit credits a coding agent in $FILE.
$FINDINGS
$NCH_REMEDY"
fi
rm -f "$REPORT"
exit 0

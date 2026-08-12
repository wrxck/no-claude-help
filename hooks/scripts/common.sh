#!/bin/sh
# shared helpers for the claude code hook scripts.
# each hook reads one json event on stdin and answers on stdout.

set -u

NCH_ROOT=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd -P)}
# shellcheck disable=SC2034  # used by the scripts that source this file
NCH_CLI="$NCH_ROOT/bin/nch"
. "$NCH_ROOT/lib/patterns.sh"

NCH_EVENT=$(mktemp "${TMPDIR:-/tmp}/nch-event.XXXXXX") || exit 0
trap 'rm -f "$NCH_EVENT"' EXIT INT TERM
cat >"$NCH_EVENT"

# plugin options arrive as free text: claude code renders every userConfig
# field as a text box, and its own boolean coercion rejects a bare "y", so
# parse the answer here instead. an empty answer takes the default.
# nch_opt_bool <value> <default y|n> -> 0 when yes
nch_opt_bool() {
	_v=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
	[ -n "$_v" ] || _v=$2
	case $_v in
	y | yes | true | 1 | on | enable | enabled) return 0 ;;
	*) return 1 ;;
	esac
}

if nch_opt_bool "${CLAUDE_PLUGIN_OPTION_STRICT_MODE:-}" n; then
	NCH_STRICT=1
else
	NCH_STRICT=0
fi
export NCH_STRICT

# read a dotted path out of the event, printing nothing when absent
nch_json() {
	if command -v jq >/dev/null 2>&1; then
		jq -r "$1 // empty" "$NCH_EVENT" 2>/dev/null
	elif command -v python3 >/dev/null 2>&1; then
		python3 - "$1" "$NCH_EVENT" <<'PY' 2>/dev/null
import json, sys
path, src = sys.argv[1], sys.argv[2]
try:
    with open(src) as fh:
        node = json.load(fh)
except Exception:
    sys.exit(0)
for part in [p for p in path.split(".") if p]:
    if not isinstance(node, dict) or part not in node:
        sys.exit(0)
    node = node[part]
if node is None or isinstance(node, (dict, list)):
    sys.exit(0)
print(node if not isinstance(node, bool) else str(node).lower())
PY
	fi
}

# json-encode a string for embedding in our reply
nch_jsonstr() {
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$1" | jq -Rs .
	elif command -v python3 >/dev/null 2>&1; then
		printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
	else
		# last resort: strip anything that would break the encoding
		printf '"%s"' "$(printf '%s' "$1" | tr -d '"\\' | tr '\n' ' ')"
	fi
}

nch_deny() {
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
		"$(nch_jsonstr "$1")"
	exit 0
}

# shellcheck disable=SC2034  # used by the scripts that source this file
NCH_REMEDY='The change belongs to the human author. Write the message or file without crediting the tool, then retry. Do not bypass this with --no-verify or NCH_DISABLE.'

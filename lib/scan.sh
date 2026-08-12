#!/bin/sh
# scanning engine, sourced by bin/nch after lib/patterns.sh.
# every scanner prints findings as "severity<tab>location<tab>why<tab>text"
# and returns 1 when it found something.
#
# the awk programs read their patterns from ENVIRON rather than -v, because
# -v expands escape sequences and would corrupt every regex.

NCH_STRICT=${NCH_STRICT:-0}

nch_lower() { tr '[:upper:]' '[:lower:]'; }

# --- identity --------------------------------------------------------------

# nch_ident_is_agent "name <email>" -> 0 when the identity belongs to an agent
nch_ident_is_agent() {
	_id=$(printf '%s' "$1" | nch_lower)

	printf '%s' "$_id" | grep -Eq "$NCH_IDENT_STRONG" && return 0

	if printf '%s' "$_id" | grep -Eq "$NCH_IDENT_ROBOT"; then
		printf '%s' "$_id" | grep -Eq "$NCH_IDENT_WEAK" && return 0
		# a bare [bot] identity is only rejected in strict mode, and never for
		# the ordinary release and dependency bots
		if [ "$NCH_STRICT" = "1" ] && printf '%s' "$_id" | grep -Eq '\[bot\]'; then
			printf '%s' "$_id" | grep -Eq "$NCH_IDENT_ALLOWED_BOTS" || return 0
		fi
	fi

	if [ -n "${NCH_EXTRA_IDENT:-}" ]; then
		printf '%s' "$_id" | grep -Eq "$NCH_EXTRA_IDENT" && return 0
	fi
	return 1
}

# nch_check_ident <role> <ident> <where>
nch_check_ident() {
	_role=$1 _ident=$2 _where=$3 _rc=0
	if nch_ident_is_agent "$_ident"; then
		printf 'error\t%s\t%s is an agent identity, commit as the human author\t%s\n' \
			"$_where" "$_role" "$_ident"
		_rc=1
	elif [ -n "${NCH_EXPECT_IDENT:-}" ] && [ "$_ident" != "$NCH_EXPECT_IDENT" ]; then
		printf 'error\t%s\t%s must be the configured author (%s)\t%s\n' \
			"$_where" "$_role" "$NCH_EXPECT_IDENT" "$_ident"
		_rc=1
	fi
	return $_rc
}

# --- messages --------------------------------------------------------------

# nch_scan_message <where>, text on stdin
nch_scan_message() {
	NCH_ARG_WHERE=$1 awk '
	BEGIN {
		WHERE     = ENVIRON["NCH_ARG_WHERE"]
		TRAILER   = ENVIRON["NCH_MSG_BAD_TRAILER"]
		COAUTHOR  = ENVIRON["NCH_MSG_COAUTHOR"]
		CREDIT    = ENVIRON["NCH_MSG_CREDIT"]
		ROBOT     = ENVIRON["NCH_MSG_ROBOT_LINE"]
		ROBOT_CTX = ENVIRON["NCH_MSG_ROBOT_CONTEXT"]
		SESSION   = ENVIRON["NCH_MSG_SESSION_URL"]
		STRONG    = ENVIRON["NCH_IDENT_STRONG"]
		ALLOW     = ENVIRON["NCH_ALLOW_MARKER"]
	}
	function emit(why,   line) {
		line = $0; gsub(/\t/, " ", line)
		printf "error\t%s:%d\t%s\t%s\n", WHERE, NR, why, line
		found = 1
	}
	{
		orig = $0; low = tolower($0)
		if (index(low, ALLOW)) next
		if (low ~ /^[[:space:]]*#/) next
		if (low ~ COAUTHOR && low ~ STRONG)   emit("co-authorship trailer credits an agent")
		else if (low ~ TRAILER)               emit("tool attribution or session trailer")
		else if (low ~ CREDIT)                emit("credits a tool for the change")
		else if (index(orig, ROBOT) && low ~ ROBOT_CTX) emit("agent attribution footer")
		if (low ~ SESSION)                    emit("agent session url")
	}
	END { exit(found ? 1 : 0) }'
}

# nch_clean_message <infile> <outfile>, drops offending lines, returns 10 when
# anything was removed
nch_clean_message() {
	awk '
	BEGIN {
		TRAILER   = ENVIRON["NCH_MSG_BAD_TRAILER"]
		COAUTHOR  = ENVIRON["NCH_MSG_COAUTHOR"]
		CREDIT    = ENVIRON["NCH_MSG_CREDIT"]
		ROBOT     = ENVIRON["NCH_MSG_ROBOT_LINE"]
		ROBOT_CTX = ENVIRON["NCH_MSG_ROBOT_CONTEXT"]
		SESSION   = ENVIRON["NCH_MSG_SESSION_URL"]
		STRONG    = ENVIRON["NCH_IDENT_STRONG"]
		ALLOW     = ENVIRON["NCH_ALLOW_MARKER"]
	}
	{
		orig = $0; low = tolower($0)
		if (!index(low, ALLOW) && low !~ /^[[:space:]]*#/) {
			if ((low ~ COAUTHOR && low ~ STRONG) ||
			    low ~ TRAILER || low ~ CREDIT || low ~ SESSION ||
			    (index(orig, ROBOT) && low ~ ROBOT_CTX)) { dropped++; next }
		}
		buf[++n] = orig
	}
	END {
		while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--
		for (i = 1; i <= n; i++) print buf[i]
		exit(dropped ? 10 : 0)
	}' "$1" >"$2"
}

# --- file content ----------------------------------------------------------

# mode diff reads a unified diff, mode whole reads one file with the path
# supplied separately
_nch_content_awk() {
	NCH_ARG_MODE=$1 NCH_ARG_PATH=$2 awk '
	BEGIN {
		MODE        = ENVIRON["NCH_ARG_MODE"]
		PATH_HINT   = ENVIRON["NCH_ARG_PATH"]
		P_ATTRIB    = ENVIRON["NCH_PATH_ATTRIBUTION"]
		P_MANIFEST  = ENVIRON["NCH_PATH_MANIFEST"]
		P_LICENSE   = ENVIRON["NCH_PATH_LICENSE"]
		STRONG      = ENVIRON["NCH_IDENT_STRONG"]
		STRONG_WORD = ENVIRON["NCH_IDENT_STRONG_WORD"]
		ATTRIB_KEY  = ENVIRON["NCH_CONTENT_ATTRIB_KEY"]
		PERSON      = ENVIRON["NCH_CONTENT_PERSON"]
		COPYRIGHT   = ENVIRON["NCH_CONTENT_COPYRIGHT"]
		COAUTHOR    = ENVIRON["NCH_MSG_COAUTHOR"]
		CREDIT      = ENVIRON["NCH_MSG_CREDIT"]
		SESSION     = ENVIRON["NCH_MSG_SESSION_URL"]
		ROBOT       = ENVIRON["NCH_MSG_ROBOT_LINE"]
		ROBOT_CTX   = ENVIRON["NCH_MSG_ROBOT_CONTEXT"]
		ALLOW       = ENVIRON["NCH_ALLOW_MARKER"]
	}
	function emit(why,   line) {
		line = text; gsub(/\t/, " ", line)
		if (length(line) > 200) line = substr(line, 1, 200) "..."
		printf "error\t%s:%s\t%s\t%s\n", path, lineno, why, line
		found = 1
	}
	function classify(p) {
		if (p ~ P_ATTRIB)   return "attribution"
		if (p ~ P_MANIFEST) return "manifest"
		if (p ~ P_LICENSE)  return "license"
		return "other"
	}
	function inspect(   low) {
		low = tolower(text)
		if (index(low, ALLOW)) return

		# these never belong in a tracked file, whatever the path
		if (low ~ SESSION)                  { emit("agent session url"); return }
		if (low ~ COAUTHOR && low ~ STRONG) { emit("co-authorship line credits an agent"); return }
		if (low ~ CREDIT)                   { emit("credits a tool for the change"); return }
		if (index(text, ROBOT) && low ~ ROBOT_CTX) { emit("agent attribution footer"); return }

		if (low !~ STRONG) return

		if (kind == "attribution")
			emit("adds an agent to a contributors or owners file")
		else if (kind == "license" || low ~ COPYRIGHT)
			emit("names an agent in a copyright line")
		else if (kind == "manifest" && (low ~ ATTRIB_KEY || text ~ PERSON))
			emit("names an agent in an author or maintainer field")
		else if (kind == "other" && low ~ ATTRIB_KEY && low ~ STRONG_WORD)
			emit("credits an agent as an author or contributor")
	}

	MODE == "whole" {
		path = PATH_HINT; kind = classify(path); lineno = NR; text = $0
		inspect(); next
	}

	MODE == "diff" {
		if ($0 ~ /^\+\+\+ /) {
			path = substr($0, 5); sub(/^b\//, "", path)
			if (path == "/dev/null") path = ""
			kind = classify(path); next
		}
		if ($0 ~ /^--- /) next
		if ($0 ~ /^@@/) {
			split($0, parts, /\+/); split(parts[2], nums, /[, ]/)
			lineno = nums[1] + 0; next
		}
		if (path == "") next
		if (substr($0, 1, 1) == "+") { text = substr($0, 2); inspect(); lineno++; next }
		if (substr($0, 1, 1) == " ") { lineno++ }
	}

	END { exit(found ? 1 : 0) }'
}

# unified diff on stdin
nch_scan_diff() { _nch_content_awk diff ""; }

# nch_scan_file_content <path>, content on stdin
nch_scan_file_content() { _nch_content_awk whole "$1"; }

# --- commits ---------------------------------------------------------------

# nch_scan_commits <rev-range...>
nch_scan_commits() {
	_rc=0
	_list=$(git rev-list "$@" 2>/dev/null) || return 0
	[ -n "$_list" ] || return 0
	for _sha in $_list; do
		_short=$(git rev-parse --short "$_sha")
		nch_check_ident author "$(git show -s --format='%an <%ae>' "$_sha")" \
			"commit $_short" || _rc=1
		nch_check_ident committer "$(git show -s --format='%cn <%ce>' "$_sha")" \
			"commit $_short" || _rc=1
		git show -s --format='%B' "$_sha" | nch_scan_message "commit $_short" || _rc=1
	done
	return $_rc
}

# --- reporting -------------------------------------------------------------

# nch_report <title>, findings on stdin, returns 1 when any were present
nch_report() {
	_tmp=$(nch_mktemp)
	cat >"$_tmp"
	if [ ! -s "$_tmp" ]; then rm -f "$_tmp"; return 0; fi

	{
		printf '\n%sno-claude-help: %s%s\n' "$NCH_C_RED" "$1" "$NCH_C_OFF"
		while IFS='	' read -r _sev _loc _why _txt; do
			printf '  %s%s%s\n' "$NCH_C_BOLD" "$_loc" "$NCH_C_OFF"
			printf '    %s\n' "$_why"
			[ -n "$_txt" ] && printf '    %s> %s%s\n' "$NCH_C_DIM" "$_txt" "$NCH_C_OFF"
		done <"$_tmp"
		printf '\n  %sthe change is the human author%ss work, do not credit the tool%s\n' \
			"$NCH_C_DIM" "'" "$NCH_C_OFF"
		printf '  %sfix the message or the file and try again%s\n\n' \
			"$NCH_C_DIM" "$NCH_C_OFF"
	} >&2
	rm -f "$_tmp"
	return 1
}

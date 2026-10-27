#!/bin/sh
# end to end tests: build throwaway repositories, install the hooks, and check
# that real git operations are blocked or allowed as intended.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
NCH="$ROOT/bin/nch"

# git refuses to run hooks from a noexec filesystem, and /tmp is mounted that
# way on plenty of hardened boxes, so keep the scratch repositories elsewhere
NCH_TEST_ROOT=${NCH_TEST_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/no-claude-help-tests}
mkdir -p "$NCH_TEST_ROOT"
WORK=$(mktemp -d "$NCH_TEST_ROOT/run.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# and isolate git from the developer's own configuration, so results do not
# depend on whatever core.hooksPath happens to be set on this machine
GIT_CONFIG_GLOBAL="$WORK/gitconfig"
GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
: >"$GIT_CONFIG_GLOBAL"

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

# a rejected commit leaves its files in the worktree, and the next case would
# stage them again with git add -A, so start each case from a clean tree
RESET_REPO=""
reset_repo() {
	[ -n "$RESET_REPO" ] || return 0
	(cd "$RESET_REPO" && git reset -q --hard && git clean -qfd) 2>/dev/null
}

# run a command, expect it to fail
denies() {
	_what=$1
	shift
	reset_repo
	if "$@" >"$WORK/out" 2>&1; then
		bad "$_what" "command succeeded but should have been blocked"
	else
		ok "$_what"
	fi
}

# run a command, expect it to succeed
allows() {
	_what=$1
	shift
	reset_repo
	if "$@" >"$WORK/out" 2>&1; then
		ok "$_what"
	else
		bad "$_what" "$(head -5 "$WORK/out")"
	fi
}

newrepo() {
	_d="$WORK/$1"
	mkdir -p "$_d"
	(
		cd "$_d" || exit 1
		git init -q -b main
		git config user.name "Real Human"
		git config user.email "human@example.com"
		git config commit.gpgsign false
		echo seed >seed.txt
		git add seed.txt
		git commit -qm "seed" --no-verify
		"$NCH" install >/dev/null 2>&1
	)
	printf '%s\n' "$_d"
}

printf '\nno-claude-help test suite\n\n'

# --- message rules ---------------------------------------------------------

R=$(newrepo messages)
RESET_REPO=$R

allows "plain commit message is accepted" \
	sh -c "cd '$R' && echo a > a.txt && git add -A && git commit -qm 'add a thing'"

denies "co-authored-by claude is blocked" \
	sh -c "cd '$R' && echo b > b.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

Co-Authored-By: Claude <noreply@anthropic.com>
EOF"

denies "generated-with footer is blocked" \
	sh -c "cd '$R' && echo c > c.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

Generated with Claude Code
EOF"

denies "session url in the message is blocked" \
	sh -c "cd '$R' && echo d > d.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

Claude-Session: https://claude.ai/code/session_01ABCDEFGHIJKLMNOP
EOF"

denies "codex session url is blocked" \
	sh -c "cd '$R' && echo e > e.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

See https://chatgpt.com/codex/tasks/task_e_68abc123
EOF"

denies "co-authored-by copilot is blocked" \
	sh -c "cd '$R' && echo f > f.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

Co-authored-by: Copilot <198982749+Copilot@users.noreply.github.com>
EOF"

allows "co-authored-by a colleague is accepted" \
	sh -c "cd '$R' && echo g > g.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

Co-authored-by: Sam Carter <sam@example.com>
EOF"

allows "a message about claude is accepted when it claims no credit" \
	sh -c "cd '$R' && echo h > h.txt && git add -A && git commit -qm 'bump the anthropic sdk to 0.30.0'"

# --- identity rules --------------------------------------------------------

R=$(newrepo identity)
RESET_REPO=$R

denies "--author override to an agent is blocked" \
	sh -c "cd '$R' && echo a > a.txt && git add -A && git commit -q --author='Claude <noreply@anthropic.com>' -m 'do a thing'"

denies "--author override to another human is blocked when pinned" \
	sh -c "cd '$R' && echo b > b.txt && git add -A && git commit -q --author='Someone Else <other@example.com>' -m 'do a thing'"

denies "GIT_AUTHOR_NAME override is blocked" \
	sh -c "cd '$R' && echo c > c.txt && git add -A && GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com git commit -q -m 'do a thing'"

denies "GIT_COMMITTER override is blocked" \
	sh -c "cd '$R' && echo d > d.txt && git add -A && GIT_COMMITTER_NAME='Cursor Agent' GIT_COMMITTER_EMAIL=cursoragent@cursor.com git commit -q -m 'do a thing'"

allows "the pinned human identity commits normally" \
	sh -c "cd '$R' && echo e > e.txt && git add -A && git commit -qm 'do a thing'"

# --- staged content rules --------------------------------------------------

R=$(newrepo content)
RESET_REPO=$R

denies "adding an agent to AUTHORS is blocked" \
	sh -c "cd '$R' && printf 'Real Human <human@example.com>\nClaude <noreply@anthropic.com>\n' > AUTHORS && git add -A && git commit -qm 'update authors'"

denies "adding an agent to CODEOWNERS is blocked" \
	sh -c "cd '$R' && printf '* @realhuman @claude-ai\n' > CODEOWNERS && git add -A && git commit -qm 'add owners'"

denies "an agent in a package.json author field is blocked" \
	sh -c "cd '$R' && printf '{\n  \"name\": \"app\",\n  \"author\": \"Claude <noreply@anthropic.com>\"\n}\n' > package.json && git add -A && git commit -qm 'add manifest'"

allows "an anthropic dependency in package.json is accepted" \
	sh -c "cd '$R' && printf '{\n  \"name\": \"app\",\n  \"dependencies\": { \"@anthropic-ai/sdk\": \"0.30.0\", \"openai\": \"4.0.0\" }\n}\n' > package.json && git add -A && git commit -qm 'add deps'"

allows "ordinary code containing the word cursor is accepted" \
	sh -c "cd '$R' && printf 'const cursor = db.query();\n// move the cursor forward\n' > db.js && git add -A && git commit -qm 'add query helper'"

denies "an agent in a copyright line is blocked" \
	sh -c "cd '$R' && printf 'Copyright (c) 2026 Claude\n' > LICENSE && git add -A && git commit -qm 'add licence'"

denies "a session url pasted into source is blocked" \
	sh -c "cd '$R' && printf '// see https://claude.ai/code/session_01ABCDEFGHIJKL\n' > note.js && git add -A && git commit -qm 'add note'"

denies "a readme acknowledgement of an agent is blocked" \
	sh -c "cd '$R' && printf '## Credits\n\nBuilt with help from Claude.\n' > README.md && git add -A && git commit -qm 'add readme'"

allows "documentation about anthropic is accepted" \
	sh -c "cd '$R' && printf '# API notes\n\nThe anthropic endpoint returns json.\n' > api.md && git add -A && git commit -qm 'document the api'"

allows "an env var named after an agent is accepted in code" \
	sh -c "cd '$R' && printf 'IDENT=\${CLAUDE_PLUGIN_OPTION_AUTHOR_IDENTITY:-}\nclaudeAuthorName = null;\n' > opts.sh && git add -A && git commit -qm 'read the option'"

allows "an explicit nch-allow line is accepted" \
	sh -c "cd '$R' && printf 'Co-Authored-By: Claude <noreply@anthropic.com> nch-allow\n' > sample.txt && git add -A && git commit -qm 'add a fixture'"

# --- bypass and backstop ---------------------------------------------------

RESET_REPO=""
R=$(newrepo backstop)
(
	cd "$R" || exit 1
	git init -q --bare "$WORK/backstop-remote.git"
	git remote add origin "$WORK/backstop-remote.git"
	git push -q origin main 2>/dev/null
	echo x >x.txt
	git add -A
	git commit -q --no-verify -F - <<'EOF'
sneak it past the commit hook

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)

denies "pre-push catches a commit made with --no-verify" \
	sh -c "cd '$R' && git push -q origin main"

allows "NCH_DISABLE bypasses deliberately" \
	sh -c "cd '$R' && NCH_DISABLE=1 git push -q origin main"

# --- cleaning and scanning -------------------------------------------------

R=$(newrepo tooling)
cat >"$WORK/msg.txt" <<'EOF'
fix the parser

Some real detail about the change.

Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
EOF

allows "nch clean strips attribution" sh -c "'$NCH' clean '$WORK/msg.txt'"
if grep -qi 'claude' "$WORK/msg.txt"; then
	bad "cleaned message has no attribution left" "$(cat "$WORK/msg.txt")"
else
	ok "cleaned message has no attribution left"
fi
if grep -q 'Some real detail' "$WORK/msg.txt"; then
	ok "cleaned message keeps the real content"
else
	bad "cleaned message keeps the real content"
fi

denies "scan --text reports attribution" \
	sh -c "printf 'x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' | '$NCH' scan --text"

allows "scan --text passes clean prose" \
	sh -c "printf 'fix the parser so it handles empty input\n' | '$NCH' scan --text"

denies "scan --content flags an AUTHORS body" \
	sh -c "cd '$WORK' && printf 'Claude <noreply@anthropic.com>\n' | '$NCH' scan --content AUTHORS"

allows "scan --content passes a clean AUTHORS body" \
	sh -c "cd '$WORK' && printf 'Real Human <human@example.com>\n' | '$NCH' scan --content AUTHORS"

allows "doctor runs" sh -c "cd '$R' && '$NCH' doctor"

# --- opt-in autoclean ------------------------------------------------------

R=$(newrepo autoclean)
(
	cd "$R" || exit 1
	git config nch.autoclean true
	echo a >a.txt
	git add -A
	git commit -q -m "keep the real subject" -m "Generated with Claude Code"
)
MSG=$(cd "$R" && git log -1 --format=%B 2>/dev/null)
case $MSG in
*[Cc]laude*) bad "autoclean strips instead of rejecting" "$MSG" ;;
*"keep the real subject"*) ok "autoclean strips instead of rejecting" ;;
*) bad "autoclean strips instead of rejecting" "the commit never landed" ;;
esac

# --- inherited hooks path --------------------------------------------------

# a machine-wide core.hooksPath belongs to the user: we go in front of it,
# never into it
INHERIT="$WORK/inherited-hooks"
mkdir -p "$INHERIT"
printf '#!/bin/sh\ntouch "$(git rev-parse --show-toplevel)/.inherited-ran"\nexit 0\n' \
	>"$INHERIT/pre-commit"
chmod +x "$INHERIT/pre-commit"
BEFORE=$(cat "$INHERIT/pre-commit")

R=$(mktemp -d "$WORK/inherit.XXXXXX")
(
	cd "$R" || exit 1
	git init -q -b main
	git config user.name "Real Human"
	git config user.email "human@example.com"
	echo seed >seed.txt
	git add -A
	git commit -qm seed --no-verify
	git config --global core.hooksPath "$INHERIT"
	"$NCH" install >/dev/null 2>&1
	echo a >a.txt
	git add -A
	git commit -qm "add a thing"
)
if [ -f "$R/.inherited-ran" ]; then
	ok "an inherited global hook still runs after ours"
else
	bad "an inherited global hook still runs after ours"
fi
if [ "$BEFORE" = "$(cat "$INHERIT/pre-commit")" ] && [ ! -e "$INHERIT/pre-commit.local" ]; then
	ok "the inherited hooks directory is left untouched"
else
	bad "the inherited hooks directory is left untouched"
fi

denies "our hooks still run under an inherited hooks path" \
	sh -c "cd '$R' && echo b > b.txt && git add -A && git commit -q -F - <<'EOF'
fix the parser

Co-Authored-By: Claude <noreply@anthropic.com>
EOF"

(cd "$R" && "$NCH" uninstall >/dev/null 2>&1)
if [ -z "$(cd "$R" && git config --local --get core.hooksPath || true)" ]; then
	ok "uninstall hands the repository back to the inherited hooks"
else
	bad "uninstall hands the repository back to the inherited hooks"
fi
git config --global --unset core.hooksPath 2>/dev/null || true

# --- range scan, the way ci runs it ----------------------------------------

R=$(newrepo range)
(
	cd "$R" || exit 1
	git checkout -qb feature
	echo a >a.txt
	git add -A
	git commit -q --no-verify -F - <<'EOF'
add a thing

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)
denies "scan --range catches a bad commit on a branch" \
	sh -c "cd '$R' && '$NCH' scan --range main..feature"

allows "scan --range passes a clean range" \
	sh -c "cd '$R' && '$NCH' scan --range main..main"

# --- the marker file -------------------------------------------------------

# a repository that has to contain the patterns themselves is exempt from the
# content rules, but never from the message or identity rules
R=$(newrepo selfmarker)
RESET_REPO=$R
(cd "$R" && : >.no-claude-help-source && git add -A && git commit -qm "mark the source tree")

allows "the marker exempts content in this repository" \
	sh -c "cd '$R' && printf 'Claude <noreply@anthropic.com>\n' > AUTHORS && git add -A && git commit -qm 'add a fixture'"

allows "scan --range skips content under the marker" \
	sh -c "cd '$R' && '$NCH' scan --range HEAD~1..HEAD"

denies "the marker does not exempt commit messages" \
	sh -c "cd '$R' && echo z > z.txt && git add -A && git commit -q -F - <<'EOF'
add a fixture

Co-Authored-By: Claude <noreply@anthropic.com>
EOF"

RESET_REPO=""

# --- chaining and uninstall ------------------------------------------------

R=$(newrepo chaining)
(
	cd "$R" || exit 1
	printf '#!/bin/sh\ntouch "$PWD/.existing-hook-ran"\nexit 0\n' >.git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	"$NCH" install >/dev/null 2>&1
	echo a >a.txt
	git add -A
	git commit -qm "add a thing"
)
if [ -f "$R/.existing-hook-ran" ]; then
	ok "an existing pre-commit hook still runs after ours"
else
	bad "an existing pre-commit hook still runs after ours"
fi

(cd "$R" && "$NCH" uninstall >/dev/null 2>&1)
if grep -q 'installed by no-claude-help' "$R/.git/hooks/pre-commit" 2>/dev/null; then
	bad "uninstall restores the original hook"
elif [ -x "$R/.git/hooks/pre-commit" ]; then
	ok "uninstall restores the original hook"
else
	bad "uninstall restores the original hook" "hook missing entirely"
fi

# tracked hooks must keep working when the checkout moves, so the chain is found from the top level
R=$(mktemp -d "$WORK/tracked.XXXXXX")
(
	cd "$R" || exit 1
	git init -q -b main
	git config user.name "Real Human"
	git config user.email "human@example.com"
	echo seed >seed.txt
	git add -A
	git commit -qm seed
	mkdir .githooks
	printf '#!/bin/sh\ntouch "$PWD/.tracked-ran"\nexit 0\n' >.githooks/pre-commit
	chmod +x .githooks/pre-commit
	git config core.hooksPath .githooks
	"$NCH" install >/dev/null 2>&1
)
if grep -q 'CHAIN="$(git rev-parse --show-toplevel 2>/dev/null)/.githooks/pre-commit.local"' \
	"$R/.githooks/pre-commit"; then
	ok "a chained hook in the work tree is found from the top level"
else
	bad "a chained hook in the work tree is found from the top level" "$(grep CHAIN "$R/.githooks/pre-commit")"
fi
MOVED="$WORK/tracked-moved"
cp -R "$R" "$MOVED"
(cd "$MOVED" && echo a >a.txt && git add -A && git commit -qm "add a thing")
if [ -f "$MOVED/.tracked-ran" ] && [ ! -f "$R/.tracked-ran" ]; then
	ok "a copy of the checkout runs its own chained hook"
else
	bad "a copy of the checkout runs its own chained hook"
fi

# session start must see hooks under core.hooksPath, or it reinstalls them every session
printf '# kept\n' >>"$R/.githooks/commit-msg"
printf '{"cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$R" |
	CLAUDE_PLUGIN_OPTION_AUTO_INSTALL_GIT_HOOKS=y "$ROOT/hooks/scripts/session-start.sh" >/dev/null 2>&1
if grep -q '^# kept$' "$R/.githooks/commit-msg"; then
	ok "session start leaves hooks under core.hooksPath alone"
else
	bad "session start leaves hooks under core.hooksPath alone"
fi

# --- summary ---------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"

sh "$ROOT/tests/plugin-hooks.sh" || FAIL=$((FAIL + 1))
[ "$FAIL" -eq 0 ]

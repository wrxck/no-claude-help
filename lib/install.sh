#!/bin/sh
# installation, instruction files and diagnostics.
# sourced lazily by bin/nch, so the hot path stays small.

NCH_HOOKS='pre-commit prepare-commit-msg commit-msg pre-push'

# --- git hook shims --------------------------------------------------------

# the installed hooks stay tiny and delegate, so updating the engine does not
# mean reinstalling hooks. they also chain into whatever hook was there first.
nch_write_shim() {
	_name=$1 _dest=$2 _nchbin=$3 _chain=$4
	{
		printf '#!/bin/sh\n'
		printf '# installed by no-claude-help %s, do not edit\n' "$NCH_VERSION"
		printf '# remove with: nch uninstall\n'
		printf 'case "${NCH_DISABLE:-0}" in 1|true|yes) exit 0 ;; esac\n'
		printf 'NCH="%s"\n' "$_nchbin"
		printf '[ -x "$NCH" ] || NCH="$(git rev-parse --git-dir 2>/dev/null)/no-claude-help/bin/nch"\n'
		printf '[ -x "$NCH" ] || NCH="$(command -v nch 2>/dev/null)"\n'
		printf 'CHAIN="%s"\n' "$_chain"
		if [ "$_name" = "pre-push" ]; then
			# pre-push gets its ref list on stdin, so replay it for the chained hook
			printf 'IN="$(mktemp)"; trap '"'"'rm -f "$IN"'"'"' EXIT; cat >"$IN"\n'
			printf '[ -x "$NCH" ] && { "$NCH" hook %s "$@" <"$IN" || exit $?; }\n' "$_name"
			printf '[ -n "$CHAIN" ] && [ -x "$CHAIN" ] && exec "$CHAIN" "$@" <"$IN"\n'
		else
			printf '[ -x "$NCH" ] && { "$NCH" hook %s "$@" || exit $?; }\n' "$_name"
			printf '[ -n "$CHAIN" ] && [ -x "$CHAIN" ] && exec "$CHAIN" "$@"\n'
		fi
		printf 'exit 0\n'
	} >"$_dest"
	chmod +x "$_dest"
}

nch_is_our_hook() { [ -f "$1" ] && grep -q 'installed by no-claude-help' "$1"; }

# the hooks directory git will actually run, absolute
nch_hooks_dir() {
	_t=$(git rev-parse --show-toplevel) || return 1
	_h=$(cd "$_t" && git rev-parse --git-path hooks)
	nch_abs "$_h" "$_t"
}

nch_abs() {
	case $1 in
	/*) printf '%s\n' "$1" ;;
	*) printf '%s\n' "$2/$1" ;;
	esac
}

nch_vendor() {
	_d=$1
	mkdir -p "$_d/bin" "$_d/lib" "$_d/githooks"
	cp "$NCH_HOME/bin/nch" "$_d/bin/nch"
	for _f in patterns.sh scan.sh install.sh policy.md; do
		cp "$NCH_HOME/lib/$_f" "$_d/lib/$_f"
	done
	chmod +x "$_d/bin/nch"
	printf '%s\n' "$NCH_VERSION" >"$_d/VERSION"
}

# --- install ---------------------------------------------------------------

cmd_install() {
	_scope=repo _author="" _rules=0 _rules_all=0 _ci=0 _strict=0 _autoclean=0
	while [ $# -gt 0 ]; do
		case $1 in
		--global) _scope=global ;;
		--repo) _scope=repo ;;
		--author)
			_author=${2:-}
			shift
			;;
		--rules) _rules=1 ;;
		--rules-all) _rules=1 _rules_all=1 ;;
		--ci) _ci=1 ;;
		--strict) _strict=1 ;;
		--autoclean) _autoclean=1 ;;
		--all) _rules=1 _rules_all=1 _ci=1 ;;
		*) nch_die "unknown option: $1" ;;
		esac
		shift
	done

	if [ "$_scope" = "global" ]; then
		nch_install_global "$_strict"
		return $?
	fi

	git rev-parse --git-dir >/dev/null 2>&1 || nch_die "not inside a git repository"
	_gitdir=$(cd "$(git rev-parse --git-dir)" && pwd -P)
	_top=$(git rev-parse --show-toplevel)
	_vendor="$_gitdir/no-claude-help"
	nch_vendor "$_vendor"

	# an inherited core.hooksPath belongs to the user, not to this repository,
	# so never write into it. install into our own directory instead and point
	# only this repository at it, chaining back into the inherited hooks.
	_localhp=$(git config --local --get core.hooksPath 2>/dev/null || true)
	_globalhp=$(git config --global --get core.hooksPath 2>/dev/null || true)
	[ -n "$_globalhp" ] || _globalhp=$(git config --system --get core.hooksPath 2>/dev/null || true)
	_chaindir=""

	if [ -n "$_localhp" ]; then
		_hooksdir=$(nch_abs "$_localhp" "$_top")
	elif [ -n "$_globalhp" ] && [ "${_globalhp#"$_gitdir"}" = "$_globalhp" ]; then
		_hooksdir="$_vendor/githooks"
		_chaindir=$(nch_abs "$_globalhp" "$_top")
		git config --local core.hooksPath "$_hooksdir"
		nch_ok "inherited hooks at $_chaindir kept, they run after ours"
	else
		_hooksdir="$_gitdir/hooks"
	fi

	mkdir -p "$_hooksdir"
	for _h in $NCH_HOOKS; do
		_dest="$_hooksdir/$_h"
		if [ -n "$_chaindir" ]; then
			_chain="$_chaindir/$_h"
		else
			_chain=""
			if [ -e "$_dest" ] && ! nch_is_our_hook "$_dest"; then
				mv "$_dest" "$_dest.local"
				_chain="$_dest.local"
				nch_warn "kept your $_h as $_h.local, it still runs after ours"
			elif [ -x "$_dest.local" ]; then
				_chain="$_dest.local"
			fi
		fi
		nch_write_shim "$_h" "$_dest" "$_vendor/bin/nch" "$_chain"
	done
	nch_ok "git hooks installed in $_hooksdir"

	[ "$_strict" = "1" ] && git config nch.strict true
	[ "$_autoclean" = "1" ] && git config nch.autoclean true

	if [ -n "$_author" ]; then
		cmd_identity set "$_author"
	else
		nch_pin_existing_identity ""
	fi

	if [ "$_rules" = "1" ]; then
		if [ "$_rules_all" = "1" ]; then cmd_rules --all; else cmd_rules; fi
	fi
	[ "$_ci" = "1" ] && nch_install_ci "$_top"

	nch_say ""
	nch_ok "no-claude-help is active in $_top"
	return 0
}

# $1 is "--global" for the global scope, empty for this repository
nch_pin_existing_identity() {
	_g=$1
	_n=$(git config $_g --get user.name 2>/dev/null || true)
	_e=$(git config $_g --get user.email 2>/dev/null || true)
	if [ -z "$_n" ] || [ -z "$_e" ]; then
		nch_warn "no git user.name and user.email set, identity enforcement is off"
		return 0
	fi
	if nch_ident_is_agent "$_n <$_e>"; then
		nch_warn "the current git identity looks like an agent: $_n <$_e>"
		nch_warn "set the real one with: nch identity set \"Name <email>\""
		return 0
	fi
	git config $_g nch.author.name "$_n"
	git config $_g nch.author.email "$_e"
	nch_ok "commits pinned to $_n <$_e>"
}

nch_install_global() {
	_strict=$1
	_root=${NCH_GLOBAL_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/no-claude-help}
	nch_vendor "$_root"

	_prev=$(git config --global --get core.hooksPath 2>/dev/null || true)
	if [ -n "$_prev" ] && [ "$_prev" != "$_root/githooks" ]; then
		git config --global nch.previousHooksPath "$_prev"
		nch_warn "previous global core.hooksPath saved: $_prev"
	fi

	# a global hooksPath shadows everything else, so chain back into whatever
	# it displaced rather than silently disabling husky and friends
	for _h in $NCH_HOOKS; do
		if [ -n "$_prev" ] && [ "$_prev" != "$_root/githooks" ]; then
			_chain="$_prev/$_h"
		else
			_chain='$(git rev-parse --git-dir 2>/dev/null)/hooks/'"$_h"
		fi
		nch_write_shim "$_h" "$_root/githooks/$_h" "$_root/bin/nch" "$_chain"
	done
	git config --global core.hooksPath "$_root/githooks"
	[ "$_strict" = "1" ] && git config --global nch.strict true
	nch_pin_existing_identity --global

	nch_ok "installed globally: $_root"
	nch_say "  every repository on this machine is covered, whatever runs git"
	return 0
}

nch_install_ci() {
	_top=$1
	mkdir -p "$_top/.github/workflows"
	cat >"$_top/.github/workflows/no-claude-help.yml" <<'YAML'
# installed by no-claude-help: fails any pull request that credits an agent.
# this is the backstop for commits made where the git hooks were not installed,
# such as cloud agents and web editors.
name: no-claude-help

on:
  pull_request:
  push:
    branches: [main, master]

permissions:
  contents: read

jobs:
  attribution:
    name: no agent attribution
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: scan commits and changes
        run: |
          set -eu
          base="${{ github.event.pull_request.base.sha }}"
          if [ -z "$base" ]; then
            base=$(git rev-parse HEAD~1 2>/dev/null || git rev-parse HEAD)
          fi
          ./.no-claude-help/bin/nch scan --range "$base..HEAD"
YAML
	nch_vendor "$_top/.no-claude-help"
	nch_ok "ci workflow written to .github/workflows/no-claude-help.yml"
	nch_say "  commit .no-claude-help/ and the workflow so pull requests are checked too"
}

# --- instruction files -----------------------------------------------------

NCH_MARK_START='<!-- no-claude-help:start -->'
NCH_MARK_END='<!-- no-claude-help:end -->'

nch_merge_block() {
	_t=$1 _b=$2
	_new=$(nch_mktemp)
	if [ -f "$_t" ] && grep -qF "$NCH_MARK_START" "$_t"; then
		awk -v s="$NCH_MARK_START" -v e="$NCH_MARK_END" -v b="$_b" '
			index($0, s) { print; while ((getline l < b) > 0) print l; close(b); skip = 1; next }
			index($0, e) { skip = 0 }
			!skip { print }
		' "$_t" >"$_new"
	else
		{
			if [ -f "$_t" ]; then
				cat "$_t"
				printf '\n'
			fi
			printf '%s\n' "$NCH_MARK_START"
			cat "$_b"
			printf '%s\n' "$NCH_MARK_END"
		} >"$_new"
	fi
	mkdir -p "$(dirname "$_t")"
	cat "$_new" >"$_t"
	nch_ok "rules written to $_t"
}

cmd_rules() {
	_all=0
	[ "${1:-}" = "--all" ] && _all=1
	_top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

	_body=$(nch_mktemp)
	cat "$NCH_HOME/lib/policy.md" >"$_body"

	# agents.md is the cross-harness convention, claude.md is claude code
	nch_merge_block "$_top/AGENTS.md" "$_body"
	nch_merge_block "$_top/CLAUDE.md" "$_body"

	# and update any other harness instruction file that already exists
	for _f in GEMINI.md .github/copilot-instructions.md .windsurfrules \
		.clinerules .rules .junie/guidelines.md \
		.github/instructions/no-claude-help.instructions.md; do
		if [ -f "$_top/$_f" ] || [ "$_all" = "1" ]; then
			nch_merge_block "$_top/$_f" "$_body"
		fi
	done

	if [ -d "$_top/.cursor/rules" ] || [ "$_all" = "1" ]; then
		mkdir -p "$_top/.cursor/rules"
		{
			printf -- '---\ndescription: attribution policy\nalwaysApply: true\n---\n\n'
			cat "$_body"
		} >"$_top/.cursor/rules/no-claude-help.mdc"
		nch_ok "rules written to $_top/.cursor/rules/no-claude-help.mdc"
	fi
}

# --- uninstall and doctor --------------------------------------------------

cmd_uninstall() {
	if [ "${1:-}" = "--global" ]; then
		_root=${NCH_GLOBAL_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/no-claude-help}
		_prev=$(git config --global --get nch.previousHooksPath 2>/dev/null || true)
		if [ -n "$_prev" ]; then
			git config --global core.hooksPath "$_prev"
			git config --global --unset nch.previousHooksPath
		else
			git config --global --unset core.hooksPath 2>/dev/null || true
		fi
		rm -rf "$_root"
		nch_ok "global install removed"
		return 0
	fi

	git rev-parse --git-dir >/dev/null 2>&1 || nch_die "not inside a git repository"
	_hooksdir=$(nch_hooks_dir)
	for _h in $NCH_HOOKS; do
		_d="$_hooksdir/$_h"
		if nch_is_our_hook "$_d"; then
			rm -f "$_d"
			[ -f "$_d.local" ] && mv "$_d.local" "$_d"
		fi
	done

	# hand the repository back to whatever hooks path it inherited
	_gitdir=$(cd "$(git rev-parse --git-dir)" && pwd -P)
	_localhp=$(git config --local --get core.hooksPath 2>/dev/null || true)
	case $_localhp in
	"$_gitdir"/no-claude-help/*) git config --local --unset core.hooksPath ;;
	esac

	rm -rf "$_gitdir/no-claude-help"
	nch_ok "git hooks removed"
}

cmd_doctor() {
	nch_load_config
	printf '%sno-claude-help %s%s\n\n' "$NCH_C_BOLD" "$NCH_VERSION" "$NCH_C_OFF"

	for _t in git awk grep sed; do
		if command -v "$_t" >/dev/null 2>&1; then nch_ok "$_t"; else nch_warn "$_t missing"; fi
	done

	_g=$(git config --global --get core.hooksPath 2>/dev/null || true)
	case $_g in
	*no-claude-help*) nch_ok "global hooks active ($_g)" ;;
	'') nch_warn "no global install, run: nch install --global" ;;
	*) nch_warn "global core.hooksPath points elsewhere: $_g" ;;
	esac

	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		nch_warn "not inside a git repository, skipped repository checks"
		return 0
	fi

	_top=$(git rev-parse --show-toplevel)
	_hooksdir=$(nch_hooks_dir)
	_n=0
	for _h in $NCH_HOOKS; do
		nch_is_our_hook "$_hooksdir/$_h" && _n=$((_n + 1))
	done
	case $_n in
	4) nch_ok "repository hooks installed" ;;
	0) nch_warn "repository hooks not installed, run: nch install" ;;
	*) nch_warn "only $_n of 4 repository hooks installed" ;;
	esac

	if [ -f "$_top/.github/workflows/no-claude-help.yml" ]; then
		nch_ok "ci workflow present"
	else
		nch_warn "no ci workflow, run: nch install --ci"
	fi

	if [ -n "${NCH_EXPECT_IDENT:-}" ]; then
		nch_ok "identity pinned to $NCH_EXPECT_IDENT"
	else
		nch_warn "identity not pinned, run: nch identity set \"Name <email>\""
	fi

	_cur=$(nch_current_ident GIT_AUTHOR_IDENT || true)
	if [ -n "$_cur" ] && nch_ident_is_agent "$_cur"; then
		nch_warn "the current author is an agent identity: $_cur"
	fi

	[ "${NCH_STRICT:-0}" = "1" ] && nch_ok "strict mode on"
	nch_disabled && nch_warn "NCH_DISABLE is set, every check is bypassed"
	return 0
}

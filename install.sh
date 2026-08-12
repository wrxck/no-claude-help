#!/bin/sh
# bootstrap for anything that is not claude code.
#
#   git clone https://github.com/wrxck/no-claude-help ~/.no-claude-help
#   ~/.no-claude-help/install.sh --global
#
# puts nch on the path and, with --global, installs the git hooks for every
# repository on the machine.

set -u

SRC=$(cd "$(dirname "$0")" && pwd -P)
BINDIR=${NCH_BINDIR:-$HOME/.local/bin}
SCOPE=""

while [ $# -gt 0 ]; do
	case $1 in
	--global | --repo) SCOPE=$1 ;;
	--bindir)
		BINDIR=${2:-}
		shift
		;;
	-h | --help)
		printf 'usage: install.sh [--global|--repo] [--bindir <dir>]\n'
		exit 0
		;;
	*)
		printf 'install.sh: unknown option: %s\n' "$1" >&2
		exit 1
		;;
	esac
	shift
done

mkdir -p "$BINDIR"
ln -sf "$SRC/bin/nch" "$BINDIR/nch"
printf 'installed %s/nch -> %s/bin/nch\n' "$BINDIR" "$SRC"

case ":$PATH:" in
*":$BINDIR:"*) : ;;
*) printf 'add %s to your PATH to use nch directly\n' "$BINDIR" ;;
esac

if [ -n "$SCOPE" ]; then
	"$SRC/bin/nch" install "$SCOPE"
else
	printf '\nnext:\n'
	printf '  nch install --global    protect every repository on this machine\n'
	printf '  nch install --all       protect one repository, with rules and ci\n'
	printf '  nch doctor              check what is active\n'
fi

#!/usr/bin/env bash
# Perpetua installer.
#
#   curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --prefix /opt/perpetua --version v1.0.0
#
# Options:
#   --prefix DIR     install root (default: ~/.local)
#   --version REF    git tag or branch to install (default: main)
#   --uninstall      remove Perpetua from the prefix (projects and state are kept)
#   -h, --help       show this help
#
# Run as a file from a clone without --version, it installs that working tree instead
# of downloading. --uninstall also removes per-project interval drop-ins.
set -euo pipefail

REPO="https://github.com/koffih/perpetua"
PREFIX="${PREFIX:-$HOME/.local}"
REF="main"
REF_SET=0
MODE="install"
SYSTEMCTL="${PERPETUA_SYSTEMCTL:-systemctl}"

usage() { sed -n '2,14p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--prefix) PREFIX=${2:?--prefix needs a directory}; shift 2 ;;
		--version) REF=${2:?--version needs a tag or branch}; REF_SET=1; shift 2 ;;
		--uninstall) MODE="uninstall"; shift ;;
		-h | --help) usage; exit 0 ;;
		*) echo "install.sh: unknown option $1 (try --help)" >&2; exit 2 ;;
	esac
done

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

if [[ $MODE == uninstall ]]; then
	if command -v "$SYSTEMCTL" > /dev/null; then
		for timer in $("$SYSTEMCTL" --user list-unit-files 'perpetua@*.timer' --no-legend 2> /dev/null | awk '{print $1}'); do
			"$SYSTEMCTL" --user disable --now "$timer" > /dev/null 2>&1 || true
		done
	fi
	unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
	rm -f "$PREFIX/bin/perpetua" "$unit_dir/perpetua@.service" "$unit_dir/perpetua@.timer"
	rm -rf "$unit_dir"/perpetua@*.timer.d
	rm -rf "$PREFIX/libexec/perpetua" "$PREFIX/share/perpetua"
	"$SYSTEMCTL" --user daemon-reload > /dev/null 2>&1 || true
	say "Perpetua removed from $PREFIX (project configuration and state were kept)"
	exit 0
fi

for tool in bash python3 flock timeout; do
	command -v "$tool" > /dev/null || { echo "install.sh: '$tool' is required" >&2; exit 1; }
done

# Install the surrounding working tree only when this script was run as a file from a
# clone and no explicit --version was requested; `curl | bash` always downloads.
src=""
here=""
script=${BASH_SOURCE[0]:-}
if [[ -f $script && $(basename "$script") == install.sh ]]; then
	here=$(cd "$(dirname "$script")" && pwd)
fi
if [[ -n $here && $REF_SET == 0 && -x $here/bin/perpetua && -d $here/libexec/perpetua ]]; then
	src=$here
else
	command -v git > /dev/null || { echo "install.sh: git is required" >&2; exit 1; }
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	say "Fetching Perpetua ($REF)"
	git clone --quiet --depth 1 --branch "$REF" "$REPO.git" "$tmp/perpetua"
	src=$tmp/perpetua
fi

say "Installing into $PREFIX"
install -d "$PREFIX/bin" "$PREFIX/libexec/perpetua" "$PREFIX/share/perpetua/systemd" "$PREFIX/share/perpetua/templates"
install -m 0755 "$src/bin/perpetua" "$PREFIX/bin/perpetua"
install -m 0755 "$src/libexec/perpetua/session" "$src/libexec/perpetua/record.py" "$PREFIX/libexec/perpetua/"
install -m 0644 "$src"/share/perpetua/systemd/* "$PREFIX/share/perpetua/systemd/"
install -m 0644 "$src"/share/perpetua/templates/* "$PREFIX/share/perpetua/templates/"

# Refresh already-installed units so they point at this installation.
unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
if [[ -f $unit_dir/perpetua@.service ]]; then
	sed "s|@LIBEXECDIR@|$PREFIX/libexec/perpetua|g" "$PREFIX/share/perpetua/systemd/perpetua@.service" > "$unit_dir/perpetua@.service"
	install -m 0644 "$PREFIX/share/perpetua/systemd/perpetua@.timer" "$unit_dir/perpetua@.timer"
	"$SYSTEMCTL" --user daemon-reload > /dev/null 2>&1 || true
fi

say "$("$PREFIX/bin/perpetua" version) installed"
case ":$PATH:" in
	*":$PREFIX/bin:"*) ;;
	*) printf '    add %s/bin to your PATH\n' "$PREFIX" ;;
esac
printf '    next: perpetua doctor, then perpetua init /path/to/project\n'

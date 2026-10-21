#!/usr/bin/env bash
# Perpetua VPS bootstrap: turn a fresh Debian, Ubuntu or Fedora-family server into a
# Perpetua host. Run as root, from an extracted Perpetua archive or a clone:
#
#   sudo ./platform/vps/bootstrap.sh [options]
#
# Options:
#   --user NAME              dedicated Unix account that runs the sessions (default: perpetua)
#   --oauth-token-file FILE  file holding the token printed by `claude setup-token`; stored
#                            in ~NAME/.config/perpetua/environment, mode 600
#   --repo URL               clone this repository and register it as a project
#   --name NAME              project name for --repo (default: derived from the URL)
#   --enable                 start the cadence for --repo once everything is in place
#   --interval DURATION      cadence interval for --enable (default: 30min)
#   --git-name NAME          git author name for the agent's commits
#   --git-email EMAIL        git author email for the agent's commits
#   --no-packages            do not install system packages
#   --no-claude              do not install Claude Code
#   --dry-run                print what would be done, change nothing
#   -h, --help               show this help
#
# Idempotent: running it again only completes what is missing. Nothing is pushed,
# no repository is created, no secret is printed.
# Commands passed to as_user are expanded by the target account, hence single quotes.
# shellcheck disable=SC2016
set -euo pipefail

USER_NAME=perpetua
TOKEN_FILE=
REPO_URL=
PROJECT_NAME=
ENABLE=0
INTERVAL=30min
GIT_NAME=
GIT_EMAIL=
PACKAGES=1
CLAUDE=1
DRY=0

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--user) USER_NAME=${2:?--user needs a name}; shift 2 ;;
		--oauth-token-file) TOKEN_FILE=${2:?--oauth-token-file needs a file}; shift 2 ;;
		--repo) REPO_URL=${2:?--repo needs a URL}; shift 2 ;;
		--name) PROJECT_NAME=${2:?--name needs a name}; shift 2 ;;
		--enable) ENABLE=1; shift ;;
		--interval) INTERVAL=${2:?--interval needs a duration}; shift 2 ;;
		--git-name) GIT_NAME=${2:?--git-name needs a value}; shift 2 ;;
		--git-email) GIT_EMAIL=${2:?--git-email needs a value}; shift 2 ;;
		--no-packages) PACKAGES=0; shift ;;
		--no-claude) CLAUDE=0; shift ;;
		--dry-run) DRY=1; shift ;;
		-h | --help) usage; exit 0 ;;
		*) echo "bootstrap: unknown option $1 (try --help)" >&2; exit 2 ;;
	esac
done

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*" >&2; }
die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
run() {
	if ((DRY)); then printf '    + %s\n' "$*"; else "$@"; fi
}

[[ $USER_NAME =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid user name '$USER_NAME'"
[[ -z $TOKEN_FILE || -r $TOKEN_FILE ]] || die "cannot read $TOKEN_FILE"
((ENABLE == 0)) || [[ -n $REPO_URL ]] || die "--enable needs --repo"
if [[ -n $REPO_URL && -z $PROJECT_NAME ]]; then
	PROJECT_NAME=$(basename "${REPO_URL%.git}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_\n-' '-')
fi
[[ -z $PROJECT_NAME || $PROJECT_NAME =~ ^[a-z0-9][a-z0-9_-]{0,62}$ ]] || die "invalid project name '$PROJECT_NAME' (use --name)"
((DRY)) || [[ $EUID -eq 0 ]] || die "run as root (sudo), or with --dry-run"

src=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
[[ -x $src/bin/perpetua && -f $src/install.sh ]] || die "run this script from an extracted Perpetua archive or clone"

# ---- 1. System packages -------------------------------------------------------------------
if ((PACKAGES)); then
	say "Installing system packages"
	if command -v apt-get > /dev/null; then
		run env DEBIAN_FRONTEND=noninteractive apt-get update -qq
		run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates python3 util-linux coreutils findutils openssh-client procps
		run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh || warn "gh (GitHub CLI) not available from apt; install it later if the agent opens pull requests"
	elif command -v dnf > /dev/null; then
		run dnf install -y -q git curl ca-certificates python3 util-linux coreutils findutils openssh-clients procps-ng
		run dnf install -y -q gh || warn "gh (GitHub CLI) not available from dnf; install it later if the agent opens pull requests"
	else
		warn "no apt-get or dnf: install git, curl, python3, util-linux and coreutils yourself"
	fi
fi

# ---- 2. Dedicated account -----------------------------------------------------------------
if id "$USER_NAME" > /dev/null 2>&1; then
	say "Account $USER_NAME exists"
else
	say "Creating account $USER_NAME"
	run useradd --create-home --shell /bin/bash "$USER_NAME"
fi
home=$(getent passwd "$USER_NAME" | cut -d: -f6 || true)
home=${home:-/home/$USER_NAME}
uid=$(id -u "$USER_NAME" 2> /dev/null || echo 0)

say "Enabling lingering (sessions keep running with nobody logged in)"
run loginctl enable-linger "$USER_NAME"

# Commands as the account, with a login-like environment and its user manager reachable.
as_user() {
	run runuser -u "$USER_NAME" -- env -i HOME="$home" USER="$USER_NAME" LOGNAME="$USER_NAME" \
		SHELL=/bin/bash PATH="$home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
		XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
		bash -c "$1"
}

# ---- 3. SSH access and git identity ---------------------------------------------------------
if [[ -s /root/.ssh/authorized_keys && ! -s $home/.ssh/authorized_keys ]]; then
	say "Copying root's authorized SSH keys to $USER_NAME (so you can ssh $USER_NAME@host)"
	run install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$home/.ssh"
	run install -m 600 -o "$USER_NAME" -g "$USER_NAME" /root/.ssh/authorized_keys "$home/.ssh/authorized_keys"
fi
if [[ ! -f $home/.ssh/id_ed25519 ]]; then
	say "Generating an SSH key for git (add it as a deploy key with write access)"
	as_user 'mkdir -p -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -C "perpetua@$(hostname)" -f ~/.ssh/id_ed25519'
fi
as_user 'touch ~/.ssh/known_hosts && for h in github.com gitlab.com; do grep -q "^$h " ~/.ssh/known_hosts || ssh-keyscan -t ed25519 "$h" >> ~/.ssh/known_hosts 2> /dev/null || true; done'

host=$(hostname)
GIT_NAME=${GIT_NAME:-Perpetua ($host)}
GIT_EMAIL=${GIT_EMAIL:-perpetua@$host}
as_user "git config --global user.name >/dev/null || git config --global user.name $(printf %q "$GIT_NAME"); git config --global user.email >/dev/null || git config --global user.email $(printf %q "$GIT_EMAIL"); git config --global init.defaultBranch main"

# ---- 4. Claude Code -----------------------------------------------------------------------
if ((CLAUDE)); then
	if [[ -x $home/.local/bin/claude ]]; then
		say "Claude Code already installed"
	else
		say "Installing Claude Code for $USER_NAME"
		as_user 'curl -fsSL https://claude.ai/install.sh | bash'
	fi
fi

# ---- 5. Perpetua --------------------------------------------------------------------------
say "Installing Perpetua for $USER_NAME"
stage=/tmp/perpetua-bootstrap.$$
run rm -rf "$stage"
run cp -R "$src" "$stage"
run rm -rf "$stage/.git"
run chown -R "$USER_NAME:$USER_NAME" "$stage"
as_user "cd $stage && ./install.sh --prefix ~/.local"
run rm -rf "$stage"
as_user 'grep -q "\.local/bin" ~/.bashrc 2>/dev/null || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc'

# ---- 6. Credentials -----------------------------------------------------------------------
envfile=$home/.config/perpetua/environment
if [[ -n $TOKEN_FILE ]]; then
	say "Storing the Claude token in $envfile (mode 600)"
	token=$(tr -d '[:space:]' < "$TOKEN_FILE")
	[[ -n $token ]] || die "$TOKEN_FILE is empty"
	run install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$home/.config" "$home/.config/perpetua"
	if ((DRY)); then
		printf '    + write CLAUDE_CODE_OAUTH_TOKEN=<redacted> to %s\n' "$envfile"
	else
		umask 077
		tmp_env=$(mktemp)
		if [[ -f $envfile ]]; then
			grep -v '^CLAUDE_CODE_OAUTH_TOKEN=' "$envfile" > "$tmp_env" || true
		fi
		printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$token" >> "$tmp_env"
		install -m 600 -o "$USER_NAME" -g "$USER_NAME" "$tmp_env" "$envfile"
		rm -f "$tmp_env"
	fi
	unset token
fi

# ---- 7. Project ---------------------------------------------------------------------------
if [[ -n $REPO_URL ]]; then
	dest=$home/work/$PROJECT_NAME
	if [[ -d $dest/.git ]]; then
		say "Repository already cloned in $dest"
	else
		say "Cloning $REPO_URL into $dest"
		as_user "mkdir -p ~/work && git clone $(printf %q "$REPO_URL") $(printf %q "$dest")" \
			|| warn "clone failed: add the deploy key below to the repository, then run this script again"
	fi
	if ((DRY)) || [[ -d $dest ]]; then
		as_user "[ -f ~/.config/perpetua/projects/$PROJECT_NAME.env ] || perpetua init $(printf %q "$dest") --name $PROJECT_NAME"
		if ((ENABLE)); then
			say "Starting the cadence for $PROJECT_NAME (every $INTERVAL after each session)"
			as_user "perpetua enable $PROJECT_NAME --interval $(printf %q "$INTERVAL")" \
				|| warn "enable failed; log in as $USER_NAME and run: perpetua enable $PROJECT_NAME --interval $INTERVAL"
		fi
	fi
fi

# ---- Next steps ---------------------------------------------------------------------------
echo
say "Host prepared for Perpetua"
if [[ -f $home/.ssh/id_ed25519.pub ]]; then
	printf '    deploy key of %s (give it write access on each repository):\n      %s\n' "$USER_NAME" "$(cat "$home/.ssh/id_ed25519.pub")"
fi
cat << EOF
    next steps, as $USER_NAME (ssh $USER_NAME@$host, or: sudo -iu $USER_NAME):
      1. Claude login, if no --oauth-token-file was given:
           claude setup-token   (on any machine with a browser), then on this server:
           echo 'CLAUDE_CODE_OAUTH_TOKEN=...' > ~/.config/perpetua/environment && chmod 600 ~/.config/perpetua/environment
      2. GitHub CLI for pull requests (optional): gh auth login
      3. perpetua doctor
      4. perpetua init ~/work/<project>      (skip if --repo was given)
      5. perpetua run <project> --force      (one supervised session)
      6. perpetua enable <project> --interval 30min
EOF

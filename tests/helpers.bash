# Shared setup: an isolated HOME, a registered project and the fake Claude Code.
setup_env() {
	ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
	export NO_COLOR=1 PERPETUA_SYSTEMCTL=false
	mkdir -p "$HOME/.claude/projects" "$BATS_TEST_TMPDIR/bin"
	ln -sf "$ROOT/tests/fixtures/claude" "$BATS_TEST_TMPDIR/bin/claude"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	PROJECT="$BATS_TEST_TMPDIR/demo"
	mkdir -p "$PROJECT"
	PERPETUA="$ROOT/bin/perpetua"
	STATE="$XDG_STATE_HOME/perpetua/demo"
	CONF="$XDG_CONFIG_HOME/perpetua/projects/demo.env"
	export FAKE_CLAUDE_ARGS="$BATS_TEST_TMPDIR/args" FAKE_CLAUDE_CWD="$BATS_TEST_TMPDIR/cwd"
}

register() {
	"$PERPETUA" init "$PROJECT" --name demo > /dev/null
}

set_conf() { echo "$1" >> "$CONF"; }

#!/usr/bin/env bats
# Headless-server support: the host environment file and the VPS bootstrap.

load helpers

setup() {
	setup_env
	register
}

@test "the host environment file is exported to Claude Code" {
	mkdir -p "$XDG_CONFIG_HOME/perpetua"
	echo 'CLAUDE_CODE_OAUTH_TOKEN=test-token' > "$XDG_CONFIG_HOME/perpetua/environment"
	set_conf "CLAUDE_BIN=$BATS_TEST_TMPDIR/bin/envclaude"
	cat > "$BATS_TEST_TMPDIR/bin/envclaude" <<-'SH'
	#!/usr/bin/env bash
	echo "$CLAUDE_CODE_OAUTH_TOKEN" > "$FAKE_CLAUDE_CWD.token"
	exec claude "$@"
	SH
	chmod +x "$BATS_TEST_TMPDIR/bin/envclaude"
	run "$PERPETUA" run demo
	[ "$status" -eq 0 ]
	[ "$(cat "$FAKE_CLAUDE_CWD.token")" = "test-token" ]
}

@test "doctor accepts a token from the environment file and checks its mode" {
	mkdir -p "$XDG_CONFIG_HOME/perpetua"
	echo 'CLAUDE_CODE_OAUTH_TOKEN=test-token' > "$XDG_CONFIG_HOME/perpetua/environment"
	chmod 644 "$XDG_CONFIG_HOME/perpetua/environment"
	run "$PERPETUA" doctor
	[[ $output == *"Claude credentials present"* ]]
	[[ $output == *"chmod 600"* ]]
	chmod 600 "$XDG_CONFIG_HOME/perpetua/environment"
	run "$PERPETUA" doctor
	[[ $output == *"(mode 600)"* ]]
}

@test "bootstrap --dry-run changes nothing and never prints the token" {
	echo 'sk-ant-oat-secret' > "$BATS_TEST_TMPDIR/token"
	run "$ROOT/platform/vps/bootstrap.sh" --dry-run --no-packages --user ppt \
		--repo https://example.com/acme/Atlas.git --enable --oauth-token-file "$BATS_TEST_TMPDIR/token"
	[ "$status" -eq 0 ]
	[[ $output == *"perpetua init /home/ppt/work/atlas --name atlas"* ]]
	[[ $output == *"perpetua enable atlas --interval 30min"* ]]
	[[ $output == *"<redacted>"* ]]
	[[ $output != *"sk-ant-oat-secret"* ]]
}

@test "bootstrap rejects bad input" {
	run "$ROOT/platform/vps/bootstrap.sh" --dry-run --user 'Bad User'
	[ "$status" -ne 0 ]
	run "$ROOT/platform/vps/bootstrap.sh" --dry-run --enable
	[ "$status" -ne 0 ]
	[[ $output == *"--enable needs --repo"* ]]
}

@test "the installer ships the autonomous-mode skill" {
	run "$ROOT/install.sh" --prefix "$BATS_TEST_TMPDIR/prefix"
	[ "$status" -eq 0 ]
	[ -f "$HOME/.claude/skills/autonomous-mode/SKILL.md" ]
	[ -f "$BATS_TEST_TMPDIR/prefix/share/perpetua/skills/autonomous-mode/SKILL.md" ]
}

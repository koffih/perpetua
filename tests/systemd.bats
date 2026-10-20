#!/usr/bin/env bats
load helpers

setup() {
	setup_env
	register
	export PERPETUA_SYSTEMCTL="$ROOT/tests/fixtures/systemctl"
	export FAKE_SYSTEMCTL_LOG="$BATS_TEST_TMPDIR/systemctl.log"
	export PERPETUA_UNIT_DIR="$BATS_TEST_TMPDIR/units"
}

@test "enable renders the units with the libexec path and starts the timer" {
	run "$PERPETUA" enable demo
	[ "$status" -eq 0 ]
	grep -qx "ExecStart=$ROOT/libexec/perpetua/session %i" "$PERPETUA_UNIT_DIR/perpetua@.service"
	[ -f "$PERPETUA_UNIT_DIR/perpetua@.timer" ]
	grep -q -- "--user enable --now perpetua@demo.timer" "$FAKE_SYSTEMCTL_LOG"
}

@test "enable --interval writes a drop-in" {
	"$PERPETUA" enable demo --interval 30min
	grep -qx "OnUnitInactiveSec=30min" "$PERPETUA_UNIT_DIR/perpetua@demo.timer.d/10-interval.conf"
}

@test "enable rejects a malformed interval" {
	run "$PERPETUA" enable demo --interval soon
	[ "$status" -eq 2 ]
}

@test "disable stops the timer" {
	"$PERPETUA" disable demo
	grep -q -- "--user disable --now perpetua@demo.timer" "$FAKE_SYSTEMCTL_LOG"
}

@test "remove deletes the drop-in" {
	"$PERPETUA" enable demo --interval 1h
	"$PERPETUA" remove demo
	[ ! -d "$PERPETUA_UNIT_DIR/perpetua@demo.timer.d" ]
	[ ! -f "$CONF" ]
}

@test "install.sh installs a working copy into a prefix" {
	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
	run "$ROOT/install.sh" --prefix "$BATS_TEST_TMPDIR/prefix"
	[ "$status" -eq 0 ]
	run "$BATS_TEST_TMPDIR/prefix/bin/perpetua" version
	[ "$output" = "perpetua 1.0.0" ]
	[ -x "$BATS_TEST_TMPDIR/prefix/libexec/perpetua/session" ]
	"$ROOT/install.sh" --prefix "$BATS_TEST_TMPDIR/prefix" --uninstall
	[ ! -e "$BATS_TEST_TMPDIR/prefix/bin/perpetua" ]
}

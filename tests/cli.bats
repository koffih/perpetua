#!/usr/bin/env bats
load helpers

setup() { setup_env; }

@test "help and version" {
	run "$PERPETUA" help
	[ "$status" -eq 0 ]
	[[ $output == *"perpetua"*"init"* ]]
	run "$PERPETUA" version
	[[ $output == "perpetua 1.0.0" ]]
}

@test "unknown command fails with status 2" {
	run "$PERPETUA" frobnicate
	[ "$status" -eq 2 ]
}

@test "init registers the project and scaffolds the directive" {
	run "$PERPETUA" init "$PROJECT" --name demo
	[ "$status" -eq 0 ]
	[ -f "$CONF" ]
	[ -f "$PROJECT/.perpetua/directive.md" ]
	grep -q "PROJECT_DIR=$PROJECT" "$CONF"
}

@test "init derives a valid name from the directory" {
	mkdir -p "$BATS_TEST_TMPDIR/My App"
	run "$PERPETUA" init "$BATS_TEST_TMPDIR/My App"
	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/perpetua/projects/my-app.env" ]
}

@test "init refuses a second registration and invalid names" {
	register
	run "$PERPETUA" init "$PROJECT" --name demo
	[ "$status" -eq 2 ]
	run "$PERPETUA" init "$PROJECT" --name 'Bad Name'
	[ "$status" -eq 2 ]
}

@test "init keeps an existing directive" {
	mkdir -p "$PROJECT/.perpetua"
	echo "house rules" > "$PROJECT/.perpetua/directive.md"
	register
	[ "$(cat "$PROJECT/.perpetua/directive.md")" = "house rules" ]
}

@test "list, pause, resume and status" {
	register
	run "$PERPETUA" list
	[[ $output == *demo* ]]
	"$PERPETUA" pause demo
	[ -f "$STATE/paused" ]
	run "$PERPETUA" status demo
	[[ $output == *paused* ]]
	"$PERPETUA" resume demo
	[ ! -f "$STATE/paused" ]
}

@test "commands on an unknown project fail cleanly" {
	run "$PERPETUA" run ghost
	[ "$status" -eq 2 ]
	[[ $output == *"unknown project"* ]]
}

@test "summaries shows the latest reports" {
	register
	set_conf "PRESENCE_WINDOW_MIN=0"
	"$PERPETUA" run demo
	run "$PERPETUA" summaries demo
	[[ $output == *"Did task A and task B."* ]]
}

@test "remove --purge deletes configuration and state" {
	register
	set_conf "PRESENCE_WINDOW_MIN=0"
	"$PERPETUA" run demo
	"$PERPETUA" remove demo --purge
	[ ! -f "$CONF" ]
	[ ! -d "$STATE" ]
}

@test "an option without its value is a usage error with a message" {
	run "$PERPETUA" init "$PROJECT" --name
	[ "$status" -eq 2 ]
	[[ $output == *"--name needs a value"* ]]
}

@test "error messages do not leak the exit status" {
	run "$PERPETUA" run ghost
	[[ $output != *" 2" ]]
}

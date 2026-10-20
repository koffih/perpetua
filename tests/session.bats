#!/usr/bin/env bats
load helpers

setup() {
	setup_env
	register
	set_conf "PRESENCE_WINDOW_MIN=0"
}

@test "a session runs in the project with the directive appended" {
	run "$PERPETUA" run demo
	[ "$status" -eq 0 ]
	[ "$(cat "$FAKE_CLAUDE_CWD")" = "$PROJECT" ]
	grep -q -- "--append-system-prompt" "$FAKE_CLAUDE_ARGS"
	grep -q -- "--dangerously-skip-permissions" "$FAKE_CLAUDE_ARGS"
	grep -q "Unattended session started by Perpetua" "$FAKE_CLAUDE_ARGS"
}

@test "the outcome is recorded for machines and humans" {
	"$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
	grep -q '"turns": 7' "$STATE/last-session.json"
	[ "$(wc -l < "$STATE/history.jsonl")" -eq 1 ]
	grep -q "Did task A and task B." "$STATE/summaries.md"
	grep -q "11111111-2222-3333-4444-555555555555" "$STATE/own-sessions"
	grep -q "session:end .* outcome=ok" "$STATE/runner.log"
}

@test "MODEL is passed through" {
	set_conf "MODEL=opus"
	"$PERPETUA" run demo
	grep -qx -- "--model" "$FAKE_CLAUDE_ARGS"
	grep -qx "opus" "$FAKE_CLAUDE_ARGS"
}

@test "gate:stop, paused by the operator" {
	"$PERPETUA" pause demo
	run "$PERPETUA" run demo
	[ "$status" -eq 0 ]
	[ ! -f "$STATE/last-session.json" ]
	grep -q "gate:stop" "$STATE/runner.log"
}

@test "gate:stop, STOP file in the project" {
	touch "$PROJECT/.perpetua/STOP"
	"$PERPETUA" run demo
	[ ! -f "$STATE/last-session.json" ]
}

@test "gate:stop holds even with --force" {
	"$PERPETUA" pause demo
	"$PERPETUA" run demo --force
	[ ! -f "$STATE/last-session.json" ]
}

@test "gate:lock, one session at a time" {
	mkdir -p "$STATE"
	exec 8> "$STATE/lock"
	flock -n 8
	"$PERPETUA" run demo
	exec 8>&-
	grep -q "gate:lock" "$STATE/runner.log"
	[ ! -f "$STATE/last-session.json" ]
}

@test "a usage limit triggers the back-off gate" {
	FAKE_CLAUDE_MODE=limit "$PERPETUA" run demo
	grep -q '"outcome": "rate_limited"' "$STATE/last-session.json"
	[ -f "$STATE/backoff-until" ]
	rm "$STATE/last-session.json"
	"$PERPETUA" run demo --force
	[ ! -f "$STATE/last-session.json" ]
	grep -q "gate:backoff" "$STATE/runner.log"
}

@test "an expired back-off is cleared" {
	mkdir -p "$STATE"
	echo 1 > "$STATE/backoff-until"
	"$PERPETUA" run demo
	[ ! -f "$STATE/backoff-until" ]
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
}

@test "a failing session is recorded as error" {
	FAKE_CLAUDE_MODE=error run "$PERPETUA" run demo
	[ "$status" -eq 0 ]
	grep -q '"outcome": "error"' "$STATE/last-session.json"
}

@test "MAX_SESSION is enforced" {
	set_conf "MAX_SESSION=1s"
	FAKE_CLAUDE_MODE=sleep "$PERPETUA" run demo
	grep -q '"outcome": "timeout"' "$STATE/last-session.json"
}

@test "gate:presence yields to an active operator" {
	set_conf "PRESENCE_WINDOW_MIN=10"
	mkdir -p "$HOME/.claude/projects/x"
	touch "$HOME/.claude/projects/x/operator.jsonl"
	"$PERPETUA" run demo
	grep -q "gate:presence" "$STATE/runner.log"
	[ ! -f "$STATE/last-session.json" ]
}

@test "gate:presence ignores transcripts of its own sessions" {
	set_conf "PRESENCE_WINDOW_MIN=10"
	mkdir -p "$STATE" "$HOME/.claude/projects/x"
	echo "abc-own" > "$STATE/own-sessions"
	touch "$HOME/.claude/projects/x/abc-own.jsonl"
	"$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
}

@test "--force bypasses the presence gate" {
	set_conf "PRESENCE_WINDOW_MIN=10"
	mkdir -p "$HOME/.claude/projects/x"
	touch "$HOME/.claude/projects/x/operator.jsonl"
	"$PERPETUA" run demo --force
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
}

@test "gate:attention throttles sessions while a question is pending" {
	printf '# Plan\n\n**Pending question:** pick a payment provider?\n' > "$PROJECT/PLAN.md"
	"$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
	rm "$STATE/last-session.json"
	"$PERPETUA" run demo
	grep -q "gate:attention" "$STATE/runner.log"
	[ ! -f "$STATE/last-session.json" ]
}

@test "gate:attention stays open when the question reads none" {
	printf '**Pending question:** none\n' > "$PROJECT/PLAN.md"
	"$PERPETUA" run demo
	rm "$STATE/last-session.json"
	"$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
}

@test "session journals are pruned to SESSION_RETENTION" {
	set_conf "SESSION_RETENTION=2"
	mkdir -p "$STATE/sessions"
	touch "$STATE/sessions/20000101T000000.jsonl" "$STATE/sessions/20000102T000000.jsonl"
	"$PERPETUA" run demo
	[ "$(ls "$STATE/sessions" | wc -l)" -eq 2 ]
	[ ! -f "$STATE/sessions/20000101T000000.jsonl" ]
}

@test "the post-session hook receives the outcome" {
	set_conf "POST_SESSION_HOOK='echo \"\$PERPETUA_PROJECT:\$PERPETUA_OUTCOME\" > $BATS_TEST_TMPDIR/hook'"
	"$PERPETUA" run demo
	[ "$(cat "$BATS_TEST_TMPDIR/hook")" = "demo:ok" ]
}

@test "a missing project directory is a configuration error" {
	rm -rf "$PROJECT"
	run "$PERPETUA" run demo
	[ "$status" -eq 3 ]
}

@test "gate:presence ignores subagent transcripts of its own sessions" {
	set_conf "PRESENCE_WINDOW_MIN=10"
	mkdir -p "$STATE" "$HOME/.claude/projects/x/abc-own/subagents"
	echo "abc-own" > "$STATE/own-sessions"
	touch "$HOME/.claude/projects/x/abc-own/subagents/agent-1.jsonl"
	"$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
}

@test "the session id is registered while the session is still running" {
	FAKE_CLAUDE_MODE=sleep FAKE_CLAUDE_SESSION=live-id "$PERPETUA" run demo &
	for _ in $(seq 40); do grep -qx live-id "$STATE/own-sessions" 2> /dev/null && break; sleep 0.1; done
	grep -qx live-id "$STATE/own-sessions"
	[ ! -f "$STATE/last-session.json" ]
	wait
	[ "$(grep -c live-id "$STATE/own-sessions")" -eq 1 ]
}

@test "a usage-limit phrase in tool output is not a usage limit" {
	FAKE_CLAUDE_MODE=toolread "$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
	[ ! -f "$STATE/backoff-until" ]
}

@test "an interrupted session is still recorded" {
	FAKE_CLAUDE_MODE=sleep "$ROOT/libexec/perpetua/session" demo &
	runner=$!
	for _ in $(seq 40); do [ -s "$STATE/own-sessions" ] && break; sleep 0.1; done
	kill -TERM "$runner"
	wait "$runner" || true
	grep -q '"outcome": "interrupted"' "$STATE/last-session.json"
	grep -q "outcome=interrupted" "$STATE/runner.log"
}

@test "gate:attention ignores a heading without a colon" {
	printf '## Pending questions\n\nNone so far.\n' > "$PROJECT/PLAN.md"
	"$PERPETUA" run demo
	rm "$STATE/last-session.json"
	"$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
}

@test "a closing report that mentions a usage limit is not a usage limit" {
	FAKE_CLAUDE_MODE=reportlimit "$PERPETUA" run demo
	grep -q '"outcome": "ok"' "$STATE/last-session.json"
	[ ! -f "$STATE/backoff-until" ]
}

@test "QUESTION_FILE may be absolute" {
	printf '**Pending question:** which provider?\n' > "$BATS_TEST_TMPDIR/plan.md"
	set_conf "QUESTION_FILE=$BATS_TEST_TMPDIR/plan.md"
	"$PERPETUA" run demo
	rm "$STATE/last-session.json"
	"$PERPETUA" run demo
	grep -q "gate:attention" "$STATE/runner.log"
}

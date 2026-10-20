---
description: Get told when a session ends, or only when it does not end well, with POST_SESSION_HOOK.
---

# Notifications

Perpetua has no notification system of its own. It has one hook, `POST_SESSION_HOOK`, which runs after every session and can call anything: a push service, a chat webhook, your desktop, your mail server.

## How the hook runs

Set it in the project configuration:

```bash title="~/.config/perpetua/projects/acme-api.env"
POST_SESSION_HOOK="$HOME/.config/perpetua/hooks/notify.sh"
```

After each session (never after a wake-up that a gate closed), the runner executes the value with `sh -c` under a 120-second `timeout`, with these variables in the environment:

| Variable | Example |
| --- | --- |
| `PERPETUA_PROJECT` | `acme-api` |
| `PERPETUA_OUTCOME` | `ok`, `error`, `timeout`, `rate_limited` or `interrupted` |
| `PERPETUA_EXIT_CODE` | `0` (exit status of Claude Code; `124` or `137` on timeout, `130` when interrupted) |
| `PERPETUA_JOURNAL` | `/home/dev/.local/state/perpetua/acme-api/sessions/20261021T030326.jsonl` |
| `PERPETUA_STATE_DIR` | `/home/dev/.local/state/perpetua/acme-api` |
| `PERPETUA_PROJECT_DIR` | `/home/dev/src/acme-api` |

When the hook runs, `$PERPETUA_STATE_DIR/last-session.json` already describes this session and `summaries.md` already ends with its report. The hook's standard output and error are appended to `runner.log`. A non-zero exit or a timeout logs `warning: post-session hook failed` and changes nothing else.

!!! tip "Quoting"
    The configuration file is sourced by bash. Use single quotes when you write the command inline, so that `$PERPETUA_*` is expanded when the hook runs, not when the file is read:

    ```bash
    POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || notify-send "Perpetua: $PERPETUA_PROJECT" "$PERPETUA_OUTCOME"'
    ```

    The command runs under `sh`, not bash: keep inline hooks POSIX, or point to a script with its own shebang.

!!! warning "Keep secrets out of the configuration file"
    Anything you `export` in the project configuration is inherited by the Claude Code session too. Store webhook URLs and tokens in a separate file readable only by you (`chmod 600`), and read it from the hook script.

## A reusable hook script

Most recipes below share the same message. This script builds it from `last-session.json` and the session's final report, then hands it to one delivery function. Copy it, keep one `deliver` function, and make it executable.

```bash title="~/.config/perpetua/hooks/notify.sh"
#!/usr/bin/env bash
set -euo pipefail

# Notify only when a session did not end ok. Remove this line to be told every time.
[[ $PERPETUA_OUTCOME == ok ]] && exit 0

# Secrets live outside the Perpetua configuration.
# shellcheck source=/dev/null
. "$HOME/.config/perpetua/hooks/secrets" # (1)!

title="Perpetua: $PERPETUA_PROJECT $PERPETUA_OUTCOME"
body=$(python3 - "$PERPETUA_STATE_DIR/last-session.json" "$PERPETUA_JOURNAL" <<'PY'
import json, sys
record = json.load(open(sys.argv[1]))
report = ""
try:
    for line in open(sys.argv[2], errors="replace"):
        if line.startswith("{") and '"type":"result"' in line.replace(" ", ""):
            report = (json.loads(line).get("result") or "").strip()
except OSError:
    pass
minutes = record["duration_s"] // 60
print(f"{record['outcome']} after {minutes} min, exit {record['exit_code']}, "
      f"{record['turns'] or 'n/a'} turns")
print(report[:1500] or "No closing report.")
PY
)

deliver() { # (2)!
	printf '%s\n\n%s\n' "$title" "$body"
}

deliver
```

1. For example `NTFY_TOPIC=...` or `SLACK_WEBHOOK_URL=...`, in a file created with `install -m 600 /dev/null ~/.config/perpetua/hooks/secrets`.
2. Replace with one of the delivery functions below.

```bash
chmod +x ~/.config/perpetua/hooks/notify.sh
```

Test it without waiting for a session, by giving it the environment the runner would:

```bash
st=~/.local/state/perpetua/acme-api
PERPETUA_PROJECT=acme-api PERPETUA_OUTCOME=error PERPETUA_EXIT_CODE=1 \
PERPETUA_STATE_DIR=$st PERPETUA_JOURNAL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["journal"])' $st/last-session.json)" \
PERPETUA_PROJECT_DIR=~/src/acme-api ~/.config/perpetua/hooks/notify.sh
```

## Recipes

Each recipe shows an inline one-liner for the configuration file and the matching `deliver` function for the script above. Every inline variant has an "only on failure" form: the `[ "$PERPETUA_OUTCOME" = ok ] ||` prefix skips sessions that ended `ok`.

=== "ntfy"

    [ntfy](https://ntfy.sh) pushes to your phone with no account. Pick a hard-to-guess topic name: anyone who knows it can read it.

    ```bash title="Inline, every session"
    POST_SESSION_HOOK='curl -fsS -H "Title: Perpetua $PERPETUA_PROJECT" -d "Session ended: $PERPETUA_OUTCOME" https://ntfy.sh/acme-perpetua-7f3k2q'
    ```

    ```bash title="Inline, only when not ok"
    POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || curl -fsS -H "Title: Perpetua $PERPETUA_PROJECT" -H "Priority: high" -H "Tags: warning" -d "Session ended: $PERPETUA_OUTCOME" https://ntfy.sh/acme-perpetua-7f3k2q'
    ```

    ```bash title="deliver() for notify.sh"
    deliver() {
    	curl -fsS -H "Title: $title" -H "Tags: robot" --data-binary "$body" "https://ntfy.sh/$NTFY_TOPIC" > /dev/null
    }
    ```

=== "Slack"

    Create an [incoming webhook](https://api.slack.com/messaging/webhooks) for the channel. The webhook URL is a secret.

    ```bash title="Inline, only when not ok"
    POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || curl -fsS -H "Content-Type: application/json" -d "{\"text\":\"Perpetua: $PERPETUA_PROJECT ended $PERPETUA_OUTCOME\"}" "$(cat ~/.config/perpetua/hooks/slack-url)"'
    ```

    Drop the `[ "$PERPETUA_OUTCOME" = ok ] ||` prefix to post after every session.

    ```bash title="deliver() for notify.sh"
    deliver() {
    	python3 -c 'import json,sys; print(json.dumps({"text": "*" + sys.argv[1] + "*\n" + sys.argv[2]}))' "$title" "$body" \
    		| curl -fsS -H "Content-Type: application/json" --data-binary @- "$SLACK_WEBHOOK_URL" > /dev/null
    }
    ```

    The JSON is built with Python so that quotes and newlines in the agent's report are escaped correctly.

=== "Desktop"

    `notify-send` (libnotify) shows a desktop notification. Under systemd it needs the user manager to know your graphical session; most desktops export `DISPLAY`, `WAYLAND_DISPLAY` and `DBUS_SESSION_BUS_ADDRESS` to it at login. If nothing appears, run `systemctl --user import-environment DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS` once per login.

    ```bash title="Inline, every session"
    POST_SESSION_HOOK='notify-send -a Perpetua "Perpetua: $PERPETUA_PROJECT" "Session ended: $PERPETUA_OUTCOME"'
    ```

    ```bash title="Inline, only when not ok"
    POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || notify-send -a Perpetua -u critical "Perpetua: $PERPETUA_PROJECT" "Session ended: $PERPETUA_OUTCOME"'
    ```

    ```bash title="deliver() for notify.sh"
    deliver() {
    	notify-send -a Perpetua -u critical "$title" "$body"
    }
    ```

=== "Email"

    Any local MTA that provides `sendmail` (Postfix, OpenSMTPD, msmtp with its `sendmail` link) works.

    ```bash title="Inline, only when not ok"
    POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || printf "Subject: Perpetua: %s %s\n\n%s\n" "$PERPETUA_PROJECT" "$PERPETUA_OUTCOME" "Journal: $PERPETUA_JOURNAL" | sendmail you@example.com'
    ```

    Drop the prefix to receive one mail per session.

    ```bash title="deliver() for notify.sh"
    deliver() {
    	printf 'To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s\n' \
    		"$MAIL_TO" "$title" "$body" | sendmail -t
    }
    ```

## Daily digest instead of per-session messages

For a busy cadence, one message a day is often better than one per session. A separate user timer can send the tail of `summaries.md` every morning; this does not involve the hook at all:

```ini title="~/.config/systemd/user/perpetua-digest.service"
[Service]
Type=oneshot
ExecStart=/bin/sh -c '%h/.local/bin/perpetua summaries acme-api -n 10 | mail -s "Perpetua digest: acme-api" you@example.com'
```

```ini title="~/.config/systemd/user/perpetua-digest.timer"
[Timer]
OnCalendar=*-*-* 07:30
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now perpetua-digest.timer
```

# Getting help

## Documentation first

The [documentation](https://koffih.github.io/perpetua/) covers installation, operation,
every configuration key and the most common questions. Two pages answer most support
requests:

- the [FAQ](https://koffih.github.io/perpetua/faq/);
- the [operating guide](https://koffih.github.io/perpetua/guides/operating/), which explains
  how to read `perpetua status`, the runner log and the session summaries.

## Diagnose your installation

Most problems come from the host rather than from Perpetua. Run:

```sh
perpetua doctor
perpetua status <project>
perpetua logs <project>
```

`doctor` checks Claude Code, credentials, Python, the systemd user instance, lingering
and, on WSL, the keep-alive. The runner log records one line per wake-up, so it tells you
which admission gate kept a session from starting.

## Ask a question or report a problem

If the documentation does not answer your question, or Perpetua behaves differently from
it, [open an issue](https://github.com/koffih/perpetua/issues/new/choose) using the form
that fits. Include the output of `perpetua doctor` and the relevant lines of the runner
log, with anything private removed.

Perpetua is maintained on a best-effort basis by volunteers. There is no guaranteed
response time and no commercial support.

## Security issues

Do not report vulnerabilities in public issues. Follow the [security policy](SECURITY.md).

## Claude Code itself

Questions about Claude Code, its skills, its permissions or its usage limits belong to
the [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) and its
[issue tracker](https://github.com/anthropics/claude-code/issues).

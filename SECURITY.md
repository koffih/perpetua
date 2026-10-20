# Security policy

Perpetua starts unattended Claude Code sessions that act on a repository without a human
watching. Its guardrails exist to keep that safe, so we treat any way to defeat them as a
security issue.

## Supported versions

Security fixes are released for the latest minor version. Upgrade to the latest release
before reporting a problem.

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |
| Earlier | No |

## Reporting a vulnerability

**Do not open a public issue, discussion or pull request for a vulnerability.**

Report it privately through GitHub:
[open a security advisory](https://github.com/koffih/perpetua/security/advisories/new).
Only the maintainers can read it.

Please include:

- the Perpetua version (`perpetua version`) and your environment (Linux or WSL,
  distribution, systemd version);
- a description of the issue and its impact;
- the steps or a proof of concept to reproduce it;
- any mitigation you are aware of.

## What to expect

| Step | Target |
| --- | --- |
| Acknowledgement of your report | 3 business days |
| Initial assessment and severity | 7 business days |
| Fix released for a critical or high severity issue | 30 days |
| Fix released for a medium or low severity issue | 90 days |

We keep you informed of progress, agree on a disclosure date with you, and publish a
GitHub Security Advisory with the fixed release. We credit you in the advisory unless you
prefer to remain anonymous. We ask that you do not disclose the issue publicly before the
advisory is published, and in any case not before 90 days from your report.

## Scope

The design and its trust boundaries are described in the
[threat model](https://koffih.github.io/perpetua/security/threat-model/). Read it before
reporting: some behaviours that look dangerous are deliberate and documented.

In scope:

- a way to start a session while an admission gate should keep it closed, in particular
  the stop flag, the lock or the back-off, which `--force` never bypasses;
- command or argument injection through a project name, a project directory path, the
  content of a session journal or `QUESTION_FILE`, or the CLI arguments;
- unsafe handling of files in the configuration and state directories, such as symlink
  attacks or state readable or writable by other users;
- flaws in the systemd units rendered by `perpetua enable`;
- flaws in `install.sh` or in the integrity of release archives and their checksums;
- flaws in the WSL keep-alive helpers.

Out of scope:

- what Claude Code does inside a session. Sessions run with the permissions given by
  `CLAUDE_ARGS`, `--dangerously-skip-permissions` by default: Perpetua decides when a
  session runs and for how long, not what the agent may do. Contain the agent with the
  directive, repository protections, credentials scoped to the project and, where needed,
  a dedicated user or machine;
- the project configuration file and `POST_SESSION_HOOK`, which are shell code sourced or
  run with the operator's privileges and are trusted by design;
- vulnerabilities in Claude Code, systemd, WSL or other third-party software, which should
  be reported to their vendors;
- issues that require an attacker who already controls the operator's account.

## Verifying a release

Every release archive is published with a `SHA256SUMS` file and a build provenance
attestation:

```sh
sha256sum --check SHA256SUMS
gh attestation verify perpetua-1.0.0.tar.gz --repo koffih/perpetua
```

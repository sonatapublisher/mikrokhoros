# Security policy

mikrokhoros is an early-stage agent runtime. Security reports are welcome and should
be handled privately until a fix and disclosure plan are ready.

## Supported versions

There is no stable release yet.

| Version | Security support |
| --- | --- |
| Current `main` branch | Supported |
| Older commits and unmaintained forks | Not supported |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Use the repository host's private vulnerability-reporting feature, preferably a
GitHub private security advisory under the repository's **Security** tab. If private
reporting is unavailable, contact a maintainer privately through the repository host
before sharing technical details publicly.

Include, when possible:

- the affected commit and platform;
- a minimal reproduction using synthetic data;
- the expected and actual security boundary;
- likely impact and required attacker access; and
- whether credentials, real user data, or external systems were involved.

Do not include live credentials, personal data, private model prompts, or destructive
proofs of concept. Maintainers will acknowledge a report when they receive it,
coordinate validation and remediation, and credit the reporter if requested and safe.
Response times are best effort until the project has a formal security team.

## In-scope examples

- escaping the mikrokhoros action language into an operating-system shell;
- bypassing object capability, pickup-lock, possession, identity, or payment checks;
- cross-agent or cross-workspace data exposure;
- credential values entering a workspace, prompt, error, log, or object surface;
- secret or excluded form values entering console history, completion, or queue
  summaries, and terminal modes not being restored after exit or failure;
- package, Inventory, deployment, report, or credential lineage crossing a user or
  workspace boundary;
- instruction or request-envelope replay reaching an external sink;
- prompt injection that causes a side effect outside deterministic authorization;
- corrupted configuration/workspace input bypassing policy, executing code, or
  replaying unauthorized effects;
- arbitrary code execution from declarative object packages; or
- path traversal, SSRF, or host-machine access through a provider or future object
  bridge.

Model behavior that merely ignores a suggestion, invents a world fact, or repeats
non-sensitive text without bypassing a runtime boundary may be a reliability bug
rather than a vulnerability. Please still report it through the normal issue tracker
when it is reproducible.

The detailed architecture and current limitations are documented in
[docs/security.md](docs/security.md).

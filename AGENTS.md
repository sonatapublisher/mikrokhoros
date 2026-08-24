# Repository contributor guide

This guide keeps contributions focused, portable, and consistent with the
supported mikrokhoros product. Start with the repository README, then use the
canonical design, security, contribution, and command-reference documents for
the area you are changing.

## Start here

1. [`README.md`](README.md) describes the product, supported platforms, and CLI.
2. [`docs/design.md`](docs/design.md) defines the runtime contract.
3. [`docs/security.md`](docs/security.md) records trust boundaries and safety
   requirements.
4. [`CONTRIBUTING.md`](CONTRIBUTING.md) lists contribution conventions.
5. [`docs/cli-reference.md`](docs/cli-reference.md) is the generated command
   reference.

## Development rules

- Keep each change focused and preserve unrelated work.
- Keep the package dependency-free unless a dependency has a concrete product
  need, a license review, and a cross-platform justification.
- Preserve macOS, Linux, and Windows compatibility. Do not introduce AppKit,
  UIKit, Darwin-only APIs, shell execution in the runtime, or unconditional
  `FoundationNetworking` imports.
- Keep `scripts/` limited to developer and installation automation. The library,
  object SDK, packages, and agent action runtime must not invoke repository
  shell scripts.
- Prefer small deterministic types and explicit errors over framework
  abstractions.
- Document public behavior in `README.md` and `docs/design.md`; update
  `CHANGELOG.md` for user-visible behavior.
- Follow `docs/security.md` for security-sensitive changes and add focused tests
  at each changed trust boundary.
- Keep the product layers distinct: the Object SDK builds packages; packages are
  installed for the human; Inventory objects are user-owned sources; world
  objects are independent world-local copies.
- Keep ordinary worlds bare. `default-khoros` is a trusted host template made
  from five canonical Inventory sources; per-agent equipment belongs to the
  agent lifecycle. Resolve facility authority from exact template lineage.
- Put template setup and migration changes behind the product lock and a
  recoverable product transaction. Preserve noninteractive and idempotent
  `khoros init` behavior.
- Keep human commands synchronized through the exhaustive `CommandKind` catalog
  and `CommandExecutor` dispatch. Generated help, guided forms, completion,
  bounded console state, and one-shot execution must not acquire separate command
  definitions.
- Keep the guided human console and `khoros shell <agent-selector>` distinct.
  The console schedules administrative commands; the agent shell submits bounded
  in-world actions and never becomes an operating-system shell.
- Do not commit environment files, credentials, generated SwiftPM state, or CLI
  world data.

## Required checks

Run these checks from the repository root:

```bash
make preflight
make test
make release
KHOROS_BIN="$(swift build -c release --show-bin-path)/khoros" ./scripts/test-terminal.sh
git diff --check
```

When SwiftPM needs an external scratch directory, supply one through the
repository's `SWIFT_BUILD_FLAGS` setting or the equivalent SwiftPM option. Do not
claim Linux or Windows verification from a macOS-only run; the cross-platform
CI matrix is the authority for those platforms.

## Definition of done

A change is complete when its behavior is implemented, focused and full tests
pass, formatting is clean, security boundaries remain deterministic, public
documentation matches the code, and the repository contains no accidental
generated or sensitive data.

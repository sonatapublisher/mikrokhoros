# Contributing to mikrokhoros

Thank you for helping build mikrokhoros. Contributions are welcome as bug reports,
design discussions, documentation, tests, and focused code changes.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Security vulnerabilities must follow [SECURITY.md](SECURITY.md), not the public issue
tracker.

## Before opening a change

- Read the [documentation index](docs/README.md) and the canonical
  [runtime design](docs/design.md). Object-package and adapter changes also require
  the [Object SDK guide](docs/object-sdk.md).
- Search existing issues and pull requests before starting duplicate work.
- Open a design discussion before changing a confirmed product invariant, the
  Inventory or world schema, public object-package format, action grammar, or
  trust boundary.
- Keep deferred scope behind the explicit boundaries in the design document.

## Local setup

Requirements:

- Swift 6.1 or newer
- Git
- macOS 13+, a current Linux distribution supported by Swift, or Windows with the
  Swift toolchain

Build and test:

```bash
git clone <repository-url>
cd mikrokhoros
make build
make test
```

No package-manager bootstrap or third-party dependency installation is required.

## Making a change

1. Create a focused branch from `main`.
2. Add or update tests before changing behavior.
3. Keep platform-neutral code in `Sources/MikroKhoros`; isolate unavoidable
   platform differences behind conditional imports.
4. Define a human command once in `CommandKind` and `CommandCatalog`. Keep the
   catalog and `CommandExecutor` switches exhaustive; do not add a console-only or
   one-shot-only parser path.
5. Register trusted native adapters in the embedding host by exact package ID. Do
   not let package metadata activate code, expose the complete runtime to a public
   adapter context, or bypass capability-mediated world and folder services.
6. Add replay tests for any external effect. Reconstructing a world must not
   repeat network, filesystem, or user-machine mutations.
7. Treat a world template as trusted host composition. Facility behavior must use
   exact template, package, Inventory, deployment, and concrete lineage. Template
   setup or migration that spans stores requires crash-recovery and idempotency
   tests.
8. Keep core world constructors bare and per-agent equipment in the agent lifecycle.
   Exercise bare creation, explicit template application, repair, and zero-prompt
   initialization when changing either path.
9. Update `README.md`, `docs/design.md`, and `CHANGELOG.md` when public behavior
   changes. Keep historical idea files as chronological records.
10. Regenerate `docs/cli-reference.md` after changing command metadata:
   `./scripts/generate-cli-reference.sh`.
11. Run `make format` after adding source files so every Swift and script file carries
   the repository’s Apache-2.0 header.
12. Run all required checks.

```bash
make preflight
make test SWIFT_BUILD_FLAGS="--scratch-path /tmp/mikrokhoros-tests"
make release SWIFT_BUILD_FLAGS="--scratch-path /tmp/mikrokhoros-release"
KHOROS_BIN="$(swift build -c release --scratch-path /tmp/mikrokhoros-release --show-bin-path)/khoros" \
  ./scripts/test-terminal.sh
git diff --check
```

`make check` runs the complete local validation set, including the POSIX
pseudoterminal smoke test. `make pre-commit` installs an
optional repository hook that runs formatting lint and license-header validation.

For security-sensitive changes, include adversarial cases covering relevant
untrusted fields and prove that rejection messages do not reproduce the payload.

## Pull requests

A good pull request:

- explains the user-visible outcome and why it belongs in the current product slice;
- names any design or security invariant it changes;
- contains focused tests for success and failure paths;
- avoids unrelated formatting or refactoring;
- documents platform verification honestly;
- does not contain credentials, private prompts, customer data, or raw attack
  payloads copied from real systems; and
- updates the changelog under `Unreleased` when users or object designers will notice
  the change.

Maintainers may ask for a smaller change or a design discussion when a pull request
combines unrelated concerns.

## Commit and compatibility policy

Use clear imperative commit subjects. Contributors do not need to reproduce the
repository's initial-history workflow; ordinary pull requests may contain normal
commits.

Until the first stable release, public APIs and the world schema may evolve, but
changes must be intentional, documented, and tested. Once compatibility guarantees
are published, semantic versioning will govern releases.

## Licensing

By contributing, you agree that your contribution is licensed under the repository's
[Apache License 2.0](LICENSE).

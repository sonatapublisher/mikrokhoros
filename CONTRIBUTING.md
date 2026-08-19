# Contributing to MikroKhoros

Thank you for helping build MikroKhoros. Contributions are welcome as bug reports,
design discussions, documentation, tests, and focused code changes.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Security vulnerabilities must follow [SECURITY.md](SECURITY.md), not the public issue
tracker.

## Before opening a change

- Read the [documentation index](docs/README.md) and the canonical
  [runtime design](docs/design.md).
- Search existing issues and pull requests before starting duplicate work.
- Open a design discussion before changing a confirmed product invariant, the
  workspace schema, public object-bundle format, action grammar, or trust boundary.
- Keep deferred scope behind the explicit boundaries in the design document.

## Local setup

Requirements:

- Swift 6.0 or newer
- Git
- macOS 13+, a current Linux distribution supported by Swift, or Windows with the
  Swift toolchain

Build and test:

```bash
git clone <repository-url>
cd mikrokhoros
swift build
swift test
```

No package-manager bootstrap or third-party dependency installation is required.

## Making a change

1. Create a focused branch from `main`.
2. Add or update tests before changing behavior.
3. Keep platform-neutral code in `Sources/MikroKhoros`; isolate unavoidable
   platform differences behind conditional imports.
4. Update `README.md`, `docs/design.md`, and `CHANGELOG.md` when public behavior
   changes. Historical idea files should remain records, with corrections recorded
   as explicit errata rather than silent rewrites.
5. Run all required checks.

```bash
swift format format --in-place --recursive --parallel Sources Tests
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swift test
swift build -c release
git diff --check
```

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

Until the first stable release, public APIs and the workspace schema may evolve, but
changes must be intentional, documented, and tested. Once compatibility guarantees
are published, semantic versioning will govern releases.

## Licensing

By contributing, you agree that your contribution is licensed under the repository's
[Apache License 2.0](LICENSE).
